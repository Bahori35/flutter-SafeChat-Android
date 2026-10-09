import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, video, doc, audio, call }

class MessageModel {
  final String id;
  final String senderId;
  final String? senderName;
  final String receiverId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final bool isDelivered;
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
    this.isDelivered = false,
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
      'isDelivered': isDelivered,
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
      isDelivered: map['isDelivered'] == 1 || map['isDelivered'] == true || map['isRead'] == 1 || map['isRead'] == true,
      isRead: map['isRead'] == 1 || map['isRead'] == true,
      mediaUrl: map['mediaUrl'],
    );
  }

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? receiverId,
    String? content,
    MessageType? type,
    DateTime? timestamp,
    bool? isDelivered,
    bool? isRead,
    String? mediaUrl,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
      mediaUrl: mediaUrl ?? this.mediaUrl,
    );
  }
}

