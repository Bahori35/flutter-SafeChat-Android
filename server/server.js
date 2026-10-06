const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
require('dotenv').config();

const db = require('./db');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
});

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'secret_key';

app.use(cors());
app.use(express.json());

// In-memory map for active socket connections: userId -> socketId
const activeSockets = new Map();

// --- REST API: AUTHENTICATION ---

// 1. Register
app.post('/api/auth/register', async (req, res) => {
  const { username, displayName, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Kullanıcı adı ve şifre zorunludur.' });
  }

  const cleanUsername = username.trim().toLowerCase();

  try {
    const [existing] = await db.query('SELECT id FROM users WHERE username = ?', [cleanUsername]);
    if (existing.length > 0) {
      return res.status(400).json({ error: 'Bu kullanıcı adı zaten alınmış.' });
    }

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(password, salt);
    const name = displayName?.trim() || cleanUsername;
    const photoUrl = `https://ui-avatars.com/api/?name=${encodeURIComponent(name)}&background=075E54&color=fff`;

    const [result] = await db.query(
      'INSERT INTO users (username, display_name, password_hash, photo_url) VALUES (?, ?, ?, ?)',
      [cleanUsername, name, passwordHash, photoUrl]
    );

    const userId = result.insertId;
    const token = jwt.sign({ id: userId, username: cleanUsername }, JWT_SECRET, { expiresIn: '30d' });

    res.status(201).json({
      message: 'Kayıt başarılı.',
      token,
      user: {
        id: userId,
        username: cleanUsername,
        displayName: name,
        photoUrl,
        isOnline: true,
      },
    });
  } catch (err) {
    console.error('Register error:', err);
    res.status(500).json({ error: 'Sunucu hatası.' });
  }
});

// 2. Login
app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Kullanıcı adı ve şifre zorunludur.' });
  }

  const cleanUsername = username.trim().toLowerCase();

  try {
    const [rows] = await db.query('SELECT * FROM users WHERE username = ?', [cleanUsername]);
    if (rows.length === 0) {
      return res.status(400).json({ error: 'Kullanıcı adı veya şifre hatalı.' });
    }

    const user = rows[0];
    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(400).json({ error: 'Kullanıcı adı veya şifre hatalı.' });
    }

    const token = jwt.sign({ id: user.id, username: user.username }, JWT_SECRET, { expiresIn: '30d' });

    // Set online
    await db.query('UPDATE users SET is_online = TRUE WHERE id = ?', [user.id]);

    res.json({
      message: 'Giriş başarılı.',
      token,
      user: {
        id: user.id,
        username: user.username,
        displayName: user.display_name,
        photoUrl: user.photo_url,
        status: user.status,
        isOnline: true,
      },
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Sunucu hatası.' });
  }
});

// 3. Get All Users (Contacts)
app.get('/api/users', async (req, res) => {
  const currentUserId = req.query.currentUserId;
  try {
    const [rows] = await db.query(
      'SELECT id, username, display_name AS displayName, photo_url AS photoUrl, status, is_online AS isOnline, last_seen AS lastSeen FROM users WHERE id != ?',
      [currentUserId || 0]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Kullanıcılar alınamadı.' });
  }
});

// 4. Get Chat Messages
app.get('/api/messages/:user1/:user2', async (req, res) => {
  const { user1, user2 } = req.params;
  try {
    const [rows] = await db.query(
      `SELECT id, sender_id AS senderId, receiver_id AS receiverId, content, message_type AS type, is_read AS isRead, media_url AS mediaUrl, created_at AS timestamp 
       FROM messages 
       WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) 
       ORDER BY created_at ASC`,
      [user1, user2, user2, user1]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Mesajlar alınamadı.' });
  }
});

// --- REALTIME SOCKET.IO & WEBRTC SIGNALING ---

io.on('connection', (socket) => {
  console.log(`🔌 Yeni bağlantı: ${socket.id}`);

  // User joins socket room with their User ID
  socket.on('join', async (userId) => {
    socket.userId = userId;
    activeSockets.set(userId.toString(), socket.id);
    await db.query('UPDATE users SET is_online = TRUE WHERE id = ?', [userId]);
    io.emit('user_status_change', { userId, isOnline: true });
    console.log(`👤 Kullanıcı bağlandı: ID ${userId}`);
  });

  // --- 1. CHAT MESSAGING ---
  socket.on('send_message', async (data) => {
    const { senderId, receiverId, content, type, mediaUrl } = data;

    try {
      const [result] = await db.query(
        'INSERT INTO messages (sender_id, receiver_id, content, message_type, media_url) VALUES (?, ?, ?, ?, ?)',
        [senderId, receiverId, content, type || 'text', mediaUrl || null]
      );

      const savedMessage = {
        id: result.insertId,
        senderId,
        receiverId,
        content,
        type: type || 'text',
        isRead: false,
        mediaUrl: mediaUrl || null,
        timestamp: new Date(),
      };

      // Send to recipient if online
      const receiverSocketId = activeSockets.get(receiverId.toString());
      if (receiverSocketId) {
        io.to(receiverSocketId).emit('receive_message', savedMessage);
      }

      // Echo back to sender
      socket.emit('message_sent', savedMessage);
    } catch (err) {
      console.error('Mesaj kaydetme hatası:', err);
    }
  });

  // Mark messages as read
  socket.on('mark_read', async ({ currentUserId, peerId }) => {
    await db.query(
      'UPDATE messages SET is_read = TRUE WHERE receiver_id = ? AND sender_id = ?',
      [currentUserId, peerId]
    );
    const peerSocketId = activeSockets.get(peerId.toString());
    if (peerSocketId) {
      io.to(peerSocketId).emit('messages_read_by_peer', { peerId: currentUserId });
    }
  });

  // --- 2. WEBRTC AUDIO & VIDEO CALL SIGNALING ---

  // Call Initiation (Offer)
  socket.on('call_user', (data) => {
    const { caller, receiverId, offer, callType } = data;
    const receiverSocketId = activeSockets.get(receiverId.toString());

    if (receiverSocketId) {
      io.to(receiverSocketId).emit('incoming_call', {
        caller,
        offer,
        callType,
      });
    } else {
      socket.emit('call_failed', { reason: 'Kullanıcı çevrimdışı' });
    }
  });

  // Call Answer (Accept)
  socket.on('answer_call', (data) => {
    const { callerId, answer } = data;
    const callerSocketId = activeSockets.get(callerId.toString());
    if (callerSocketId) {
      io.to(callerSocketId).emit('call_answered', { answer });
    }
  });

  // ICE Candidates Exchange
  socket.on('ice_candidate', (data) => {
    const { targetUserId, candidate } = data;
    const targetSocketId = activeSockets.get(targetUserId.toString());
    if (targetSocketId) {
      io.to(targetSocketId).emit('ice_candidate', { candidate });
    }
  });

  // End Call / Reject
  socket.on('end_call', (data) => {
    const { targetUserId } = data;
    const targetSocketId = activeSockets.get(targetUserId.toString());
    if (targetSocketId) {
      io.to(targetSocketId).emit('call_ended');
    }
  });

  // Disconnect
  socket.on('disconnect', async () => {
    if (socket.userId) {
      activeSockets.delete(socket.userId.toString());
      await db.query('UPDATE users SET is_online = FALSE WHERE id = ?', [socket.userId]);
      io.emit('user_status_change', { userId: socket.userId, isOnline: false });
      console.log(`🔌 Kullanıcı ayrıldı: ID ${socket.userId}`);
    }
  });
});

server.listen(PORT, () => {
  console.log(`🚀 Chat & Call Sunucusu Port ${PORT} üzerinde çalışıyor.`);
});
