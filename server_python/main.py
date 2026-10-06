import os
import pymysql
import socketio
import uvicorn
import bcrypt
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
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
                is_online BOOLEAN DEFAULT FALSE,
                last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            """)

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id INT AUTO_INCREMENT PRIMARY KEY,
                sender_id INT NOT NULL,
                receiver_id INT NOT NULL,
                content TEXT NOT NULL,
                message_type ENUM('text', 'image', 'audio', 'call') DEFAULT 'text',
                is_read BOOLEAN DEFAULT FALSE,
                media_url VARCHAR(255) NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
            );
            """)

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

class RegisterRequest(BaseModel):
    username: str
    password: str
    displayName: Optional[str] = ""

class LoginRequest(BaseModel):
    username: str
    password: str

# --- REST API ---

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
    return users

@app.get("/api/messages/{user1}/{user2}")
def get_messages(user1: int, user2: int):
    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute(
            """SELECT id, sender_id AS senderId, receiver_id AS receiverId, content, message_type AS type, is_read AS isRead, media_url AS mediaUrl, created_at AS timestamp 
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
    await sio.emit("user_status_change", {"userId": user_id, "isOnline": True})

@sio.event
async def send_message(sid, data):
    sender_id = data.get("senderId")
    receiver_id = data.get("receiverId")
    content = data.get("content")
    msg_type = data.get("type", "text")

    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute(
            "INSERT INTO messages (sender_id, receiver_id, content, message_type) VALUES (%s, %s, %s, %s)",
            (sender_id, receiver_id, content, msg_type)
        )
        msg_id = cursor.lastrowid
    conn.close()

    saved_message = {
        "id": msg_id,
        "senderId": sender_id,
        "receiverId": receiver_id,
        "content": content,
        "type": msg_type,
        "isRead": False,
        "timestamp": str(datetime.now())
    }

    receiver_sid = active_sockets.get(str(receiver_id))
    if receiver_sid:
        await sio.emit("receive_message", saved_message, to=receiver_sid)
    await sio.emit("message_sent", saved_message, to=sid)

@sio.event
async def call_user(sid, data):
    receiver_id = data.get("receiverId")
    receiver_sid = active_sockets.get(str(receiver_id))
    if receiver_sid:
        await sio.emit("incoming_call", data, to=receiver_sid)
    else:
        await sio.emit("call_failed", {"reason": "Kullanıcı çevrimdışı"}, to=sid)

@sio.event
async def answer_call(sid, data):
    caller_id = data.get("callerId")
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
    target_user_id = data.get("targetUserId")
    target_sid = active_sockets.get(str(target_user_id))
    if target_sid:
        await sio.emit("call_ended", to=target_sid)

@sio.event
async def disconnect(sid):
    for uid, s in list(active_sockets.items()):
        if s == sid:
            del active_sockets[uid]
            await sio.emit("user_status_change", {"userId": uid, "isOnline": False})
            break

if __name__ == "__main__":
    uvicorn.run("main:socket_app", host="0.0.0.0", port=3000, reload=True)
