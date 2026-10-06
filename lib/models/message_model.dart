import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, audio, call }

class MessageModel {
  final String id;
  final String senderId;
  final String? senderName;
  final String receiverId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final bool isRead;
  final String? mediaUrl;

  MessageModel({
    required this.id,
    required this.senderId,
    this.senderName,
    required this.receiverId,
    required this.content,
    this.type = MessageType.text,
    required this.timestamp,
    this.isRead = false,
    this.mediaUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'content': content,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'mediaUrl': mediaUrl,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedTime = DateTime.now();
    if (map['timestamp'] != null) {
      if (map['timestamp'] is String) {
        parsedTime = DateTime.tryParse(map['timestamp']) ?? DateTime.now();
      } else if (map['timestamp'] is Timestamp) {
        parsedTime = (map['timestamp'] as Timestamp).toDate();
      }
    }

    return MessageModel(
      id: docId,
      senderId: map['senderId']?.toString() ?? '',
      senderName: map['senderName'],
      receiverId: map['receiverId']?.toString() ?? '',
      content: map['content'] ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: parsedTime,
      isRead: map['isRead'] ?? false,
      mediaUrl: map['mediaUrl'],
    );
  }
}

