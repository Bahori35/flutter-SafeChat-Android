import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String username;
  final String email;
  final String displayName;
  final String photoUrl;
  final String status;
  final bool isOnline;
  final DateTime? lastSeen;

  UserModel({
    required this.uid,
    required this.username,
    required this.email,
    required this.displayName,
    this.photoUrl = '',
    this.status = 'Hey there! I am using this app.',
    this.isOnline = false,
    this.lastSeen,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'username': username.toLowerCase().trim(),
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'status': status,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime? parsedLastSeen;
    if (map['lastSeen'] != null) {
      if (map['lastSeen'] is String) {
        parsedLastSeen = DateTime.tryParse(map['lastSeen']);
      } else if (map['lastSeen'] is Timestamp) {
        parsedLastSeen = (map['lastSeen'] as Timestamp).toDate();
      }
    }

    return UserModel(
      uid: docId,
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? map['username'] ?? 'User',
      photoUrl: map['photoUrl'] ?? '',
      status: map['status'] ?? 'Hey there! I am using this app.',
      isOnline: map['isOnline'] ?? false,
      lastSeen: parsedLastSeen,
    );
  }
}

