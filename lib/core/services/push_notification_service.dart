import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  StreamSubscription<String>? _tokenRefreshSub;

  bool _initialized = false;
  bool _notificationPermissionRequested = false;
  String? _currentUserId;
  String? _lastRegisteredToken;

  Future<void> initialize() async {
    if (!kIsWeb || _initialized) return;
    _initialized = true;

    try {
      _foregroundMessageSub = FirebaseMessaging.onMessage.listen((message) {
        log(
          'FCM foreground message: ${message.messageId} '
          '${message.notification?.title ?? ''}',
        );
      });

      _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) {
        final uid = _currentUserId;
        if (uid == null) return;
        unawaited(_saveToken(uid, token));
      });
    } catch (e, st) {
      log('FCM initialize failed: $e', stackTrace: st);
    }
  }

  Future<void> syncTokenForUser(String? userId) async {
    try {
      if (!kIsWeb || !_initialized) return;
      if (_currentUserId == userId) return;

      final previousUserId = _currentUserId;
      final previousToken = _lastRegisteredToken;
      _currentUserId = userId;

      if (previousUserId != null &&
          previousToken != null &&
          previousUserId != userId) {
        await _removeToken(previousUserId, previousToken);
      }

      if (userId == null) return;
      final settings = await _messaging.getNotificationSettings();
      final permissionGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!permissionGranted) return;

      const vapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');
      if (vapidKey.isEmpty) {
        log(
          'Missing FCM_WEB_VAPID_KEY. Run with '
          '--dart-define=FCM_WEB_VAPID_KEY=<PUBLIC_VAPID_KEY>.',
        );
        return;
      }

      final token = await _messaging.getToken(vapidKey: vapidKey);
      if (token == null || token.isEmpty) return;

      await _saveToken(userId, token);
    } catch (e, st) {
      log('FCM token sync failed: $e', stackTrace: st);
      return;
    }
  }

  Future<bool> isNotificationEnabledForUser(String? userId) async {
    if (!kIsWeb || !_initialized || userId == null) return false;

    final settings = await _messaging.getNotificationSettings();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return false;

    const vapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');
    if (vapidKey.isEmpty) return false;

    final token = await _messaging.getToken(vapidKey: vapidKey);
    if (token == null || token.isEmpty) return false;

    _lastRegisteredToken = token;
    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data();
    if (data == null) return false;

    final fcm = data['fcm'];
    if (fcm is! Map<String, dynamic>) return false;
    final tokens = fcm['webTokens'];
    if (tokens is! List) return false;

    return tokens.whereType<String>().contains(token);
  }

  Future<bool> setNotificationEnabled({
    required String userId,
    required bool enabled,
  }) async {
    if (!kIsWeb || !_initialized) return false;
    _currentUserId = userId;

    const vapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');
    if (vapidKey.isEmpty) {
      log(
        'Missing FCM_WEB_VAPID_KEY. Run with '
        '--dart-define=FCM_WEB_VAPID_KEY=<PUBLIC_VAPID_KEY>.',
      );
      return false;
    }

    if (enabled) {
      final granted = await _ensureNotificationPermission();
      if (!granted) return false;

      final token = await _messaging.getToken(vapidKey: vapidKey);
      if (token == null || token.isEmpty) return false;
      await _saveToken(userId, token);
      return true;
    }

    final token =
        _lastRegisteredToken ?? await _messaging.getToken(vapidKey: vapidKey);
    if (token != null && token.isNotEmpty) {
      await _removeToken(userId, token);
    }
    await _messaging.deleteToken();
    _lastRegisteredToken = null;
    return false;
  }

  Future<void> _saveToken(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'fcm': {
          'webTokens': FieldValue.arrayUnion([token]),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      _lastRegisteredToken = token;
    } catch (e, st) {
      log('Save FCM token failed: $e', stackTrace: st);
    }
  }

  Future<void> _removeToken(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'fcm': {
          'webTokens': FieldValue.arrayRemove([token]),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e, st) {
      log('Remove FCM token failed: $e', stackTrace: st);
    }
  }

  Future<bool> _ensureNotificationPermission() async {
    if (_notificationPermissionRequested) {
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }

    _notificationPermissionRequested = true;
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    log('FCM permission: ${settings.authorizationStatus}');

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<void> dispose() async {
    await _foregroundMessageSub?.cancel();
    await _tokenRefreshSub?.cancel();
  }
}
