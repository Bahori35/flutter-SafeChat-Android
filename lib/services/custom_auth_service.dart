import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';

class CustomAuthService extends ChangeNotifier {
  // Replace with your local IP when testing on a physical phone (e.g. http://192.168.1.50:3000)
  // For Android Emulator use: http://10.0.2.2:3000
  static const String baseUrl = 'http://10.0.2.2:3000/api';

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
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
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
      } else {
        _isLoading = false;
        notifyListeners();
        return data['detail'] ?? data['error'] ?? 'Kayıt başarısız oldu.';
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Sunucuya bağlanılamadı: $e';
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
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
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
      } else {
        _isLoading = false;
        notifyListeners();
        return data['detail'] ?? data['error'] ?? 'Kullanıcı adı veya şifre hatalı.';
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Sunucuya bağlanılamadı: $e';
    }
  }

  // 3. LOGOUT API
  void signOut() {
    _currentUser = null;
    _token = null;
    notifyListeners();
  }
}
