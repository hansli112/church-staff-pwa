import 'dart:async';
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

  /// Two-phase session restore:
  ///
  /// Phase 1 (~10 ms) — read the locally cached [User] from SharedPreferences.
  ///   If a cached user exists AND Firebase Auth still shows a logged-in
  ///   session, set [isRestoring] to false immediately so the UI can render
  ///   MainScaffold without waiting for Firestore.
  ///
  /// Phase 2 (background, ~300–1000 ms) — fetch the fresh Firestore profile in
  ///   [_refreshUserInBackground] to pick up role/zone changes.  If the
  ///   background fetch returns null the session is treated as expired and the
  ///   user is signed out.
  ///
  /// Fallback — if there is no cache, fall through to the original full
  ///   [getCurrentUser] path (Firebase Auth stream + Firestore) so the first
  ///   load after a fresh install still works correctly.
  Future<void> _restoreSession() async {
    try {
      final cached = await _repository.getCachedUser();

      if (cached != null) {
        // Optimistic path: we have a cached profile.
        // Set the user immediately so the UI can proceed to MainScaffold.
        _currentUser = cached;
        _isRestoring = false;
        notifyListeners();

        // Kick off background refresh without blocking the UI.
        unawaited(_refreshUserInBackground());
        return;
      }

      // No cache — cold start or first login after install.
      // Wait for the full Firestore fetch before dismissing the loading shell.
      _currentUser = await _repository.getCurrentUser();
    } catch (e, st) {
      log('讀取登入狀態失敗', error: e, stackTrace: st);
      _error = '讀取登入狀態失敗:${mapErrorToUserMessage(e)}';
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  /// Fetches a fresh user profile from Firestore in the background.
  ///
  /// - If the fetch succeeds: update [currentUser] with the fresh data so any
  ///   role or zone changes are reflected immediately.
  /// - If the fetch returns null: the Firebase Auth session has been revoked or
  ///   the Firestore document was deleted — treat as logout.
  /// - If the fetch throws: keep the cached user in place so the current
  ///   session is not disrupted; the next user-initiated action that hits
  ///   Firestore will surface the real error.
  ///
  /// An [expectedId] guard is captured before the await so that a
  /// logout + login-B that occurs while the network call is in flight does
  /// not overwrite B's session with A's stale data.
  Future<void> _refreshUserInBackground() async {
    // Snapshot the identity we are refreshing for.  If the session changes
    // while we are waiting for Firestore we must discard the result.
    final expectedId = _currentUser?.id;

    try {
      final fresh = await _repository.getCurrentUser();

      // Session was replaced (logout / account switch) while the fetch was
      // in flight — discard this stale result entirely.
      if (_currentUser?.id != expectedId) return;

      if (fresh == null) {
        // Session expired or account removed.
        _currentUser = null;
        notifyListeners();
        return;
      }

      _currentUser = fresh;
      // Write through to local cache only now that the guard has passed,
      // so stale A data can never overwrite an already-switched B session.
      await _repository.writeCachedUser(fresh);
      notifyListeners();
    } catch (e, st) {
      log('背景更新使用者資料失敗', error: e, stackTrace: st);
      // Retain cached user — do not surface an error or sign the user out here,
      // as connectivity blips should not disrupt an active session.
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
