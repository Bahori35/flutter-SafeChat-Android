import os
import uuid
import pymysql
import socketio
import uvicorn
import bcrypt
import firebase_admin
from firebase_admin import credentials, messaging
from fastapi import FastAPI, HTTPException, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from typing import Optional
from jose import jwt
from datetime import datetime, timedelta

# DB Configuration
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_NAME = os.getenv("DB_NAME", "chat_app_db")
DB_PORT = int(os.getenv("DB_PORT", 3306))
SECRET_KEY = os.getenv("JWT_SECRET", "super_secret_jwt_key_whatsapp_clone_2026")

# --- FIREBASE ADMIN INITIALIZATION ---
firebase_initialized = False
try:
    key_path = os.path.join(os.path.dirname(__file__), "safechet-bildirim-firebase-adminsdk-fbsvc-9989ea95a3.json")
    if not firebase_admin._apps:
        if os.path.exists(key_path):
            cred = credentials.Certificate(key_path)
            firebase_admin.initialize_app(cred)
            firebase_initialized = True
            print("[OK] Firebase Admin SDK basariyla yuklendi!")
        else:
            print(f"[UYARI] Firebase key dosyasi bulunamadi: {key_path}")
    else:
        firebase_initialized = True
        print("[OK] Firebase Admin SDK zaten calisiyor!")
except Exception as e:
    print(f"[HATA] Firebase Admin baslatilamadi: {e}")

def send_fcm_push(user_id: int, title: str, body: str, data_payload: dict = None):
    if not firebase_initialized:
        return
    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("SELECT fcm_token FROM users WHERE id = %s", (user_id,))
            row = cursor.fetchone()
        conn.close()

        if not row or not row.get("fcm_token"):
            print(f"[FCM UYARI] Kullanici #{user_id} icin veritabaninda fcm_token bulunamadi (NULL)! Bildirim atilamadi.")
            return

        fcm_token = row["fcm_token"]
        msg_data = {k: str(v) for k, v in (data_payload or {}).items()}
        
        # High priority Android DATA-ONLY payload (prevent duplicate notification from Android OS)
        msg_data["title"] = str(title)
        msg_data["body"] = str(body)
        
        message = messaging.Message(
            data=msg_data,
            android=messaging.AndroidConfig(
                priority="high",
                ttl=timedelta(seconds=60) if msg_data.get("type") == "call" else timedelta(hours=24),
            ),
            token=fcm_token,
        )
        response = messaging.send(message)
        print(f"[FCM] Push bildirimi basariyla gonderildi (Kullanici ID: {user_id}): {response}")
    except Exception as e:
        print(f"[FCM HATA] Bildirim gonderilemedi (Kullanici ID: {user_id}): {e}")


def hash_password(password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception:
        return False

def get_db_connection():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        port=DB_PORT,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True
    )

def init_db():
    try:
        # First connect without db to create database if not exists
        conn = pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASSWORD, port=DB_PORT, autocommit=True)
        with conn.cursor() as cursor:
            cursor.execute(f"CREATE DATABASE IF NOT EXISTS {DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
        conn.close()

        # Connect to chat_app_db and create tables
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(50) UNIQUE NOT NULL,
                display_name VARCHAR(100) NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                photo_url VARCHAR(255) DEFAULT '',
                status VARCHAR(255) DEFAULT 'Hey there! I am using this app.',
                fcm_token TEXT NULL,
                is_online BOOLEAN DEFAULT FALSE,
                last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            """)

            try:
                cursor.execute("ALTER TABLE users ADD COLUMN fcm_token TEXT NULL;")
            except Exception:
                pass

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id INT AUTO_INCREMENT PRIMARY KEY,
                sender_id INT NOT NULL,
                receiver_id INT NOT NULL,
                content TEXT NOT NULL,
                message_type ENUM('text', 'image', 'audio', 'call') DEFAULT 'text',
                is_delivered BOOLEAN DEFAULT FALSE,
                is_read BOOLEAN DEFAULT FALSE,
                media_url VARCHAR(255) NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
            );
            """)

            try:
                cursor.execute("ALTER TABLE messages ADD COLUMN is_delivered BOOLEAN DEFAULT FALSE;")
            except Exception:
                pass

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS call_logs (
                id INT AUTO_INCREMENT PRIMARY KEY,
                caller_id INT NOT NULL,
                receiver_id INT NOT NULL,
                call_type ENUM('audio', 'video') NOT NULL,
                call_status ENUM('missed', 'accepted', 'rejected', 'ended') NOT NULL,
                duration_seconds INT DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (caller_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
            );
            """)
        conn.close()
        print("[OK] MariaDB baglantisi ve tablolar hazir!")
    except Exception as e:
        print(f"[UYARI] MariaDB baslatma uyarisi: {e}")

init_db()

# Socket.IO & FastAPI App
sio = socketio.AsyncServer(async_mode="asgi", cors_allowed_origins="*")
app = FastAPI(title="Chat & Call MariaDB Backend")
socket_app = socketio.ASGIApp(sio, app)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Active sockets: user_id -> sid
active_sockets = {}
# Active pending calls: receiver_id (str) -> callData (dict)
active_pending_calls = {}

class RegisterRequest(BaseModel):
    username: str
    password: str
    displayName: Optional[str] = ""

class LoginRequest(BaseModel):
    username: str
    password: str

class FcmTokenRequest(BaseModel):
    userId: int
    fcmToken: str

class MessageDeliveredRequest(BaseModel):
    receiverId: int
    senderId: Optional[int] = None
    messageId: Optional[int] = None

@app.get("/api/calls/pending/{userId}")
def get_pending_call(userId: str):
    call_data = active_pending_calls.get(str(userId))
    return {"hasPendingCall": call_data is not None, "callData": call_data}

# Create uploads directory if not exists
UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        ext = os.path.splitext(file.filename)[1]
        if not ext:
            ext = ".jpg"
        unique_filename = f"{uuid.uuid4().hex}{ext}"
        file_path = os.path.join(UPLOAD_DIR, unique_filename)
        
        contents = await file.read()
        with open(file_path, "wb") as f:
            f.write(contents)
            
        public_url = f"http://46.197.188.20:3000/uploads/{unique_filename}"
        return {"status": "success", "url": public_url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Dosya yuklenemedi: {e}")

class UpdateProfileRequest(BaseModel):
    userId: int
    displayName: Optional[str] = None
    photoUrl: Optional[str] = None
    status: Optional[str] = None

@app.post("/api/users/profile")
def update_profile(req: UpdateProfileRequest):
    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute("SELECT * FROM users WHERE id = %s", (req.userId,))
        user = cursor.fetchone()
        if not user:
            conn.close()
            raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")

        new_name = req.displayName.strip() if req.displayName is not None and req.displayName.strip() else user["display_name"]
        new_photo = req.photoUrl.strip() if req.photoUrl is not None and req.photoUrl.strip() else user["photo_url"]
        new_status = req.status.strip() if req.status is not None else user["status"]

        cursor.execute(
            "UPDATE users SET display_name = %s, photo_url = %s, status = %s WHERE id = %s",
            (new_name, new_photo, new_status, req.userId)
        )
        cursor.execute("SELECT * FROM users WHERE id = %s", (req.userId,))
        updated_user = cursor.fetchone()
    conn.close()

    return {
        "status": "success",
        "message": "Profil başarıyla güncellendi",
        "user": {
            "id": updated_user["id"],
            "username": updated_user["username"],
            "displayName": updated_user["display_name"],
            "photoUrl": updated_user["photo_url"],
            "status": updated_user["status"],
            "isOnline": updated_user["is_online"] == 1
        }
    }

@app.post("/api/users/fcm-token")
def update_fcm_token(req: FcmTokenRequest):
    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute("UPDATE users SET fcm_token = %s WHERE id = %s", (req.fcmToken, req.userId))
    conn.close()
    return {"status": "success", "message": "FCM Token guncellendi"}

@app.post("/api/messages/delivered")
async def report_delivered_rest(req: MessageDeliveredRequest):
    conn = get_db_connection()
    with conn.cursor() as cursor:
        if req.messageId:
            cursor.execute("UPDATE messages SET is_delivered = 1 WHERE id = %s", (req.messageId,))
        elif req.senderId and req.receiverId:
            cursor.execute("UPDATE messages SET is_delivered = 1 WHERE sender_id = %s AND receiver_id = %s", (req.senderId, req.receiverId))
        else:
            cursor.execute("UPDATE messages SET is_delivered = 1 WHERE receiver_id = %s", (req.receiverId,))
    conn.close()

    if req.senderId:
        sender_sid = active_sockets.get(str(req.senderId))
        if sender_sid:
            await sio.emit("messages_delivered", {"senderId": str(req.senderId), "receiverId": str(req.receiverId), "messageId": req.messageId}, to=sender_sid)

    return {"status": "success"}


@app.post("/api/auth/register")
def register(req: RegisterRequest):
    clean_username = req.username.strip().lower()
    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute("SELECT id FROM users WHERE username = %s", (clean_username,))
        if cursor.fetchone():
            conn.close()
            raise HTTPException(status_code=400, detail="Bu kullanıcı adı zaten alınmış.")

        hashed_pw = hash_password(req.password)
        name = req.displayName.strip() if req.displayName else clean_username
        photo_url = f"https://ui-avatars.com/api/?name={name}&background=075E54&color=fff"

        cursor.execute(
            "INSERT INTO users (username, display_name, password_hash, photo_url) VALUES (%s, %s, %s, %s)",
            (clean_username, name, hashed_pw, photo_url)
        )
        user_id = cursor.lastrowid

    conn.close()
    token = jwt.encode({"id": user_id, "username": clean_username}, SECRET_KEY, algorithm="HS256")
    return {
        "message": "Kayıt başarılı",
        "token": token,
        "user": {
            "id": user_id,
            "username": clean_username,
            "displayName": name,
            "photoUrl": photo_url,
            "isOnline": True
        }
    }

@app.post("/api/auth/login")
def login(req: LoginRequest):
    clean_username = req.username.strip().lower()
    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute("SELECT * FROM users WHERE username = %s", (clean_username,))
        user = cursor.fetchone()
        if not user or not verify_password(req.password, user["password_hash"]):
            conn.close()
            raise HTTPException(status_code=400, detail="Kullanıcı adı veya şifre hatalı.")

        cursor.execute("UPDATE users SET is_online = TRUE WHERE id = %s", (user["id"],))

    conn.close()
    token = jwt.encode({"id": user["id"], "username": user["username"]}, SECRET_KEY, algorithm="HS256")
    return {
        "message": "Giriş başarılı",
        "token": token,
        "user": {
            "id": user["id"],
            "username": user["username"],
            "displayName": user["display_name"],
            "photoUrl": user["photo_url"],
            "status": user["status"],
            "isOnline": True
        }
    }

@app.get("/api/users")
def get_users(currentUserId: Optional[int] = 0):
    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute(
            "SELECT id, username, display_name AS displayName, photo_url AS photoUrl, status, is_online AS isOnline, last_seen AS lastSeen FROM users WHERE id != %s",
            (currentUserId,)
        )
        users = cursor.fetchall()
    conn.close()

    # Dynamically match online status from real-time connected sockets
    for u in users:
        uid_str = str(u["id"])
        u["isOnline"] = uid_str in active_sockets

    return users

@app.get("/api/messages/{user1}/{user2}")
def get_messages(user1: int, user2: int):
    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute(
            """SELECT id, sender_id AS senderId, receiver_id AS receiverId, content, message_type AS type, is_delivered AS isDelivered, is_read AS isRead, media_url AS mediaUrl, created_at AS timestamp 
               FROM messages 
               WHERE (sender_id = %s AND receiver_id = %s) OR (sender_id = %s AND receiver_id = %s) 
               ORDER BY created_at ASC""",
            (user1, user2, user2, user1)
        )
        messages = cursor.fetchall()
    conn.close()
    return messages

# --- SOCKET.IO REALTIME & WEBRTC SIGNALING ---

@sio.event
async def connect(sid, environ):
    print(f"[SOCKET] Baglanti: {sid}")

@sio.event
async def join(sid, user_id):
    active_sockets[str(user_id)] = sid
    print(f"[USER] Kullanici baglandi: ID {user_id}")

    # Update database
    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("UPDATE users SET is_online = 1 WHERE id = %s", (user_id,))
            # Mark all pending messages to this user as delivered
            cursor.execute("UPDATE messages SET is_delivered = 1 WHERE receiver_id = %s AND is_delivered = 0", (user_id,))
        conn.close()
    except Exception as e:
        print(f"[DB ERR] {e}")

    await sio.emit("user_status_change", {"userId": str(user_id), "isOnline": True})


@sio.event
async def send_message(sid, data):
    print(f"[SOCKET] send_message tetiklendi: {data}")
    sender_id = data.get("senderId")
    receiver_id = data.get("receiverId")
    content = data.get("content")
    msg_type = data.get("type", "text")

    receiver_sid = active_sockets.get(str(receiver_id))
    is_delivered = bool(receiver_sid)

    conn = get_db_connection()
    sender_name = "Biri"
    with conn.cursor() as cursor:
        cursor.execute(
            "INSERT INTO messages (sender_id, receiver_id, content, message_type, is_delivered, is_read) VALUES (%s, %s, %s, %s, %s, 0)",
            (sender_id, receiver_id, content, msg_type, is_delivered)
        )
        msg_id = cursor.lastrowid
        cursor.execute("SELECT display_name, username FROM users WHERE id = %s", (sender_id,))
        sender_row = cursor.fetchone()
        if sender_row:
            sender_name = sender_row.get("display_name") or sender_row.get("username") or "Biri"
    conn.close()

    saved_message = {
        "id": msg_id,
        "senderId": sender_id,
        "senderName": sender_name,
        "receiverId": receiver_id,
        "content": content,
        "type": msg_type,
        "isDelivered": is_delivered,
        "isRead": False,
        "timestamp": str(datetime.now())
    }

    if receiver_sid:
        await sio.emit("receive_message", saved_message, to=receiver_sid)
    await sio.emit("message_sent", saved_message, to=sid)

    # Trigger FCM Push Notification
    try:
        target_uid = int(receiver_id)
        print(f"[FCM] send_message push cagriliyor -> Target UID: {target_uid}")
        send_fcm_push(
            user_id=target_uid,
            title=f"Yeni Mesaj: {sender_name}",
            body=content if msg_type == "text" else "Yeni bir medya mesajı aldınız.",
            data_payload={
                "type": "message",
                "messageId": str(msg_id),
                "senderId": str(sender_id),
                "receiverId": str(receiver_id),
                "senderName": sender_name,
                "content": content,
            }
        )
    except Exception as e:
        print(f"[FCM HATA] send_message icinde push hatasi: {e}")


@sio.event
async def message_delivered(sid, data):
    # Receiver reports that messages were delivered
    sender_id = data.get("senderId")
    receiver_id = data.get("receiverId")
    msg_id = data.get("messageId")

    conn = get_db_connection()
    with conn.cursor() as cursor:
        if msg_id:
            cursor.execute("UPDATE messages SET is_delivered = 1 WHERE id = %s", (msg_id,))
        elif sender_id and receiver_id:
            cursor.execute("UPDATE messages SET is_delivered = 1 WHERE sender_id = %s AND receiver_id = %s", (sender_id, receiver_id))
    conn.close()

    sender_sid = active_sockets.get(str(sender_id))
    if sender_sid:
        await sio.emit("messages_delivered", {"senderId": str(sender_id), "receiverId": str(receiver_id), "messageId": msg_id}, to=sender_sid)


@sio.event
async def message_read(sid, data):
    # Receiver opened the chat / read the message
    sender_id = data.get("senderId")
    receiver_id = data.get("receiverId")
    msg_id = data.get("messageId")

    conn = get_db_connection()
    with conn.cursor() as cursor:
        if msg_id:
            cursor.execute("UPDATE messages SET is_delivered = 1, is_read = 1 WHERE id = %s", (msg_id,))
        elif sender_id and receiver_id:
            cursor.execute("UPDATE messages SET is_delivered = 1, is_read = 1 WHERE sender_id = %s AND receiver_id = %s", (sender_id, receiver_id))
    conn.close()

    sender_sid = active_sockets.get(str(sender_id))
    if sender_sid:
        await sio.emit("messages_read", {"senderId": str(sender_id), "receiverId": str(receiver_id), "messageId": msg_id}, to=sender_sid)


@sio.event
async def call_user(sid, data):
    print(f"[SOCKET] call_user tetiklendi: {data.get('callType')} -> Receiver: {data.get('receiverId')}")
    receiver_id = data.get("receiverId")
    caller_data = data.get("caller", {})
    caller_name = caller_data.get("displayName") or caller_data.get("username") or "Biri"
    call_type_str = data.get("callType", "video")

    # Store pending call in memory so killed/background app can retrieve it on launch
    active_pending_calls[str(receiver_id)] = data

    receiver_sid = active_sockets.get(str(receiver_id))
    if receiver_sid:
        await sio.emit("incoming_call", data, to=receiver_sid)

    # Always trigger high-priority FCM wake-up call notification
    try:
        target_uid = int(receiver_id)
        print(f"[FCM] call_user push cagriliyor -> Target UID: {target_uid}")
        send_fcm_push(
            user_id=target_uid,
            title=f"Gelen { 'Görüntülü' if call_type_str == 'video' else 'Sesli' } Arama",
            body=f"{caller_name} sizi arıyor...",
            data_payload={
                "type": "call",
                "callerName": caller_name,
                "callType": call_type_str,
                "callerId": caller_data.get("uid", ""),
            }
        )
    except Exception as e:
        print(f"[FCM HATA] call_user icinde push hatasi: {e}")


@sio.event
async def answer_call(sid, data):
    caller_id = data.get("callerId")
    # Remove from pending
    for r_id, c_data in list(active_pending_calls.items()):
        if str(c_data.get("caller", {}).get("uid")) == str(caller_id):
            active_pending_calls.pop(r_id, None)

    caller_sid = active_sockets.get(str(caller_id))
    if caller_sid:
        await sio.emit("call_answered", data, to=caller_sid)

@sio.event
async def ice_candidate(sid, data):
    target_user_id = data.get("targetUserId")
    target_sid = active_sockets.get(str(target_user_id))
    if target_sid:
        await sio.emit("ice_candidate", data, to=target_sid)

@sio.event
async def end_call(sid, data):
    target_user_id = data.get("targetUserId") if isinstance(data, dict) else None
    
    # Remove from pending calls
    for r_id in list(active_pending_calls.keys()):
        active_pending_calls.pop(r_id, None)

    if target_user_id:
        target_sid = active_sockets.get(str(target_user_id))
        if target_sid:
            print(f"[CALL] Arama sonlandirildi -> Hedef: {target_user_id}")
            await sio.emit("call_ended", {}, to=target_sid)
    else:
        # Broadcast to others if specific target is not given
        for uid, s in list(active_sockets.items()):
            if s != sid:
                await sio.emit("call_ended", {}, to=s)

@sio.event
async def disconnect(sid):
    for uid, s in list(active_sockets.items()):
        if s == sid:
            del active_sockets[uid]
            print(f"[USER] Kullanici ayrildi: ID {uid}")
            try:
                conn = get_db_connection()
                with conn.cursor() as cursor:
                    cursor.execute("UPDATE users SET is_online = 0, last_seen = NOW() WHERE id = %s", (uid,))
                conn.close()
            except Exception as e:
                print(f"[DB ERR] {e}")

            await sio.emit("user_status_change", {"userId": str(uid), "isOnline": False})
            break


if __name__ == "__main__":
    uvicorn.run("main:socket_app", host="0.0.0.0", port=3000, reload=True)
