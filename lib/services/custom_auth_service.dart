import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  bool _isInitializing = true;
  bool get isInitializing => _isInitializing;

  CustomAuthService() {
    _loadSavedUser();
  }

  // Auto-login from local storage (SharedPreferences)
  Future<void> _loadSavedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString('saved_user');
      final savedToken = prefs.getString('saved_token');

      if (savedUserJson != null && savedToken != null) {
        final Map<String, dynamic> userMap = jsonDecode(savedUserJson);
        _currentUser = UserModel.fromMap(userMap, userMap['uid'] ?? '0');
        _token = savedToken;
      }
    } catch (e) {
      debugPrint('[AUTH] Auto-login error: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  // Save session to local storage
  Future<void> _saveSession(UserModel user, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_user', jsonEncode(user.toMap()));
      await prefs.setString('saved_token', token);
    } catch (e) {
      debugPrint('[AUTH] Save session error: $e');
    }
  }

  // Clear saved session on logout
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user');
      await prefs.remove('saved_token');
    } catch (e) {
      debugPrint('[AUTH] Clear session error: $e');
    }
  }

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
          await _saveSession(_currentUser!, _token!);
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
          await _saveSession(_currentUser!, _token!);
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
  Future<void> signOut() async {
    await _clearSession();
    _currentUser = null;
    _token = null;
    notifyListeners();
  }
}
