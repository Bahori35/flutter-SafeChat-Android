import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Generate unique chat room ID for 2 users
  String getChatRoomId(String user1, String user2) {
    List<String> ids = [user1, user2];
    ids.sort();
    return ids.join('_');
  }

  // Get stream of all users except current user
  Stream<List<UserModel>> getUsersStream(String currentUserId) {
    return _firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs
          .where((doc) => doc.id != currentUserId)
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // Stream single user profile
  Stream<UserModel> getUserStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    });
  }

  // Search users by username or displayName
  Future<List<UserModel>> searchUsers(String query, String currentUserId) async {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty) return [];

    final snapshot = await _firestore.collection('users').get();
    return snapshot.docs
        .where((doc) => doc.id != currentUserId)
        .map((doc) => UserModel.fromMap(doc.data(), doc.id))
        .where((u) =>
            u.username.contains(cleanQuery) ||
            u.displayName.toLowerCase().contains(cleanQuery))
        .toList();
  }

  // Send a new message
  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String messageContent,
    MessageType type = MessageType.text,
    String? mediaUrl,
  }) async {
    final chatRoomId = getChatRoomId(senderId, receiverId);
    final timestamp = DateTime.now();

    final messageDoc = _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .doc();

    final newMessage = MessageModel(
      id: messageDoc.id,
      senderId: senderId,
      receiverId: receiverId,
      content: messageContent,
      type: type,
      timestamp: timestamp,
      isRead: false,
      mediaUrl: mediaUrl,
    );

    // Save message in subcollection
    await messageDoc.set(newMessage.toMap());

    // Update chat room metadata for recent chat list
    await _firestore.collection('chat_rooms').doc(chatRoomId).set({
      'chatRoomId': chatRoomId,
      'users': [senderId, receiverId],
      'lastMessage': messageContent,
      'lastMessageTime': Timestamp.fromDate(timestamp),
      'lastSenderId': senderId,
      'unreadCount_$receiverId': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  // Stream messages of a chat room
  Stream<List<MessageModel>> getMessagesStream(String senderId, String receiverId) {
    final chatRoomId = getChatRoomId(senderId, receiverId);
    return _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String currentUserId, String peerId) async {
    final chatRoomId = getChatRoomId(currentUserId, peerId);
    
    // Reset unread count for current user
    await _firestore.collection('chat_rooms').doc(chatRoomId).set({
      'unreadCount_$currentUserId': 0,
    }, SetOptions(merge: true));

    // Update unread flags in messages
    final unreadMessages = await _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .where('receiverId', isEqualTo: currentUserId)
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in unreadMessages.docs) {
      await doc.reference.update({'isRead': true});
    }
  }

  // Stream recent chats
  Stream<QuerySnapshot> getRecentChatsStream(String currentUserId) {
    return _firestore
        .collection('chat_rooms')
        .where('users', arrayContains: currentUserId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots();
  }
}
