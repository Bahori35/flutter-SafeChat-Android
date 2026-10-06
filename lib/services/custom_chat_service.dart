import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/message_model.dart';
import 'custom_auth_service.dart';

class CustomChatService {
  static const String baseUrl = CustomAuthService.baseUrl;

  // Get all registered users from Python / MariaDB server
  Future<List<UserModel>> getUsers(String currentUserId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users?currentUserId=$currentUserId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) {
          return UserModel(
            uid: json['id'].toString(),
            username: json['username'] ?? '',
            email: '${json['username']}@custom.server',
            displayName: json['displayName'] ?? json['username'] ?? 'User',
            photoUrl: json['photoUrl'] ?? '',
            status: json['status'] ?? 'Hey there! I am using this app.',
            isOnline: json['isOnline'] == 1 || json['isOnline'] == true,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error fetching users from custom server: $e');
    }
    return [];
  }

  // Get chat history between two users
  Future<List<MessageModel>> getMessages(String user1, String user2) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/$user1/$user2'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) {
          return MessageModel(
            id: json['id'].toString(),
            senderId: json['senderId'].toString(),
            receiverId: json['receiverId'].toString(),
            content: json['content'] ?? '',
            type: MessageType.text,
            timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
            isRead: json['isRead'] == 1 || json['isRead'] == true,
            mediaUrl: json['mediaUrl'],
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error fetching messages: $e');
    }
    return [];
  }
}
