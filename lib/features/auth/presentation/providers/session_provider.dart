import 'dart:developer';

import 'package:flutter/material.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../../../core/utils/error_messages.dart';

class SessionProvider extends ChangeNotifier {
  final AuthRepository _repository;

  User? _currentUser;
  bool _isLoading = false;
  bool _isRestoring = true;
  String? _error;

  SessionProvider(this._repository) {
    _restoreSession();
  }

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isRestoring => _isRestoring;
  String? get error => _error;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  Future<void> _restoreSession() async {
    try {
      _currentUser = await _repository.getCurrentUser();
    } catch (e, st) {
      log('讀取登入狀態失敗', error: e, stackTrace: st);
      _error = '讀取登入狀態失敗:${mapErrorToUserMessage(e)}';
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _repository.login(username, password);
      if (user != null) {
        _currentUser = user;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = '帳號或密碼錯誤';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e, st) {
      log('登入失敗', error: e, stackTrace: st);
      _error = '登入失敗:${mapErrorToUserMessage(e)}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await _repository.logout();
    _currentUser = null;
    _isRestoring = false;

    _isLoading = false;
    notifyListeners();
  }

  /// Called by [UserAdminProvider] when the admin updates their own profile,
  /// so that the session reflects the latest data immediately.
  void refreshCurrentUser(User user) {
    if (_currentUser?.id == user.id) {
      _currentUser = user;
      notifyListeners();
    }
  }
}
