import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';

class CustomAuthService extends ChangeNotifier {
  // Server Public IP Address
  static const String baseUrl = 'http://46.197.188.20:3000/api';

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  String? _token;
  String? get token => _token;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // 1. REGISTER API
  Future<String?> registerUser({
    required String username,
    required String password,
    required String displayName,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username.trim().toLowerCase(),
          'password': password,
          'displayName': displayName.trim().isEmpty ? username : displayName.trim(),
        }),
      ).timeout(const Duration(seconds: 10));

      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        data = null;
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data != null && data['user'] != null) {
          _token = data['token'];
          _currentUser = UserModel(
            uid: data['user']['id'].toString(),
            username: data['user']['username'],
            email: '${data['user']['username']}@custom.server',
            displayName: data['user']['displayName'],
            photoUrl: data['user']['photoUrl'] ?? '',
            isOnline: true,
          );
          _isLoading = false;
          notifyListeners();
          return null; // Success
        }
      }

      _isLoading = false;
      notifyListeners();
      if (data != null && (data['detail'] != null || data['error'] != null)) {
        return data['detail'] ?? data['error'];
      }
      return 'Sunucu Hatası (${response.statusCode}): Lütfen sunucunuzun açık ve port yönlendirmenin doğru olduğunu kontrol edin.';
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Sunucuya bağlanılamadı. Lütfen sunucunun (start_server.bat) açık olduğunu ve port 3000 yönlendirmesini kontrol edin.';
    }
  }

  // 2. LOGIN API
  Future<String?> loginUser({
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username.trim().toLowerCase(),
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        data = null;
      }

      if (response.statusCode == 200) {
        if (data != null && data['user'] != null) {
          _token = data['token'];
          _currentUser = UserModel(
            uid: data['user']['id'].toString(),
            username: data['user']['username'],
            email: '${data['user']['username']}@custom.server',
            displayName: data['user']['displayName'],
            photoUrl: data['user']['photoUrl'] ?? '',
            status: data['user']['status'] ?? 'Hey there! I am using this app.',
            isOnline: true,
          );
          _isLoading = false;
          notifyListeners();
          return null; // Success
        }
      }

      _isLoading = false;
      notifyListeners();
      if (data != null && (data['detail'] != null || data['error'] != null)) {
        return data['detail'] ?? data['error'];
      }
      return 'Giriş Hatası (${response.statusCode}): Kullanıcı adı veya şifre hatalı.';
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Sunucuya bağlanılamadı. Lütfen sunucunun (start_server.bat) açık olduğunu kontrol edin.';
    }
  }

  // 3. LOGOUT API
  void signOut() {
    _currentUser = null;
    _token = null;
    notifyListeners();
  }
}
