import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  AuthService() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser != null) {
      await fetchUserData(firebaseUser.uid);
      await setUserOnlineStatus(true);
    } else {
      _currentUser = null;
      notifyListeners();
    }
  }

  Future<void> fetchUserData(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        _currentUser = UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
    }
  }

  Future<String?> registerUser({
    required String username,
    required String password,
    required String displayName,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final cleanUsername = username.trim().toLowerCase();
      
      // Check if username is already taken
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: cleanUsername)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        _isLoading = false;
        notifyListeners();
        return 'Bu kullanıcı adı zaten alınmış.';
      }

      // Map username to an internal email for Firebase Auth
      final internalEmail = '$cleanUsername@app.internal';

      UserCredential userCred = await _auth.createUserWithEmailAndPassword(
        email: internalEmail,
        password: password,
      );

      final uid = userCred.user!.uid;
      UserModel newUser = UserModel(
        uid: uid,
        username: cleanUsername,
        email: internalEmail,
        displayName: displayName.trim().isEmpty ? username : displayName.trim(),
        photoUrl: 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(displayName.trim().isEmpty ? username : displayName)}&background=075E54&color=fff',
        isOnline: true,
        lastSeen: DateTime.now(),
      );

      await _firestore.collection('users').doc(uid).set(newUser.toMap());
      _currentUser = newUser;
      
      _isLoading = false;
      notifyListeners();
      return null; // Success
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      if (e.code == 'weak-password') {
        return 'Şifre en az 6 karakter olmalıdır.';
      }
      return e.message ?? 'Kayıt başarısız oldu.';
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Bir hata meydana geldi: $e';
    }
  }

  Future<String?> loginUser({
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final cleanUsername = username.trim().toLowerCase();
      final internalEmail = '$cleanUsername@app.internal';

      UserCredential userCred = await _auth.signInWithEmailAndPassword(
        email: internalEmail,
        password: password,
      );

      await fetchUserData(userCred.user!.uid);
      await setUserOnlineStatus(true);

      _isLoading = false;
      notifyListeners();
      return null; // Success
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return 'Kullanıcı adı veya şifre hatalı.';
      }
      return e.message ?? 'Giriş yapılamadı.';
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Giriş hatası: $e';
    }
  }

  Future<void> setUserOnlineStatus(bool isOnline) async {
    if (_auth.currentUser != null) {
      await _firestore.collection('users').doc(_auth.currentUser!.uid).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> signOut() async {
    await setUserOnlineStatus(false);
    await _auth.signOut();
    _currentUser = null;
    notifyListeners();
  }
}
