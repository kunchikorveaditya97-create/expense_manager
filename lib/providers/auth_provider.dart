// lib/providers/auth_provider.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum AuthStatus {
  authenticated,
  unauthenticated,
}

class AppAuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<User?>? _userSub;

  bool _isLoading = false;
  String? _errorMessage;

  AppAuthProvider() {
    _init();
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  User? get currentUser => _auth.currentUser;

  AuthStatus get status {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      return AuthStatus.unauthenticated;
    }
    return AuthStatus.authenticated;
  }

  String get currentUserId {
    return _auth.currentUser?.uid ?? '';
  }

  String get currentUserEmail {
    return _auth.currentUser?.email ?? '';
  }

  void _init() {
    _userSub = _auth.authStateChanges().listen((_) {
      notifyListeners();
    });
  }

  Future<bool> signInWithEmail(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signUpWithEmail(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _auth.signOut();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }
}