import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

enum PushToggleFailureReason {
  notWeb,
  notInitialized,
  missingVapidKey,
  permissionDenied,
  tokenUnavailable,
  saveTokenFailed,
  savePreferenceFailed,
}

class PushToggleResult {
  const PushToggleResult({
    required this.enabled,
    this.failureReason,
  });

  final bool enabled;
  final PushToggleFailureReason? failureReason;
}

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

      _currentUserId = userId;
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

    final preference = await _getWeeklyRosterReminderPreference(userId);
    if (preference == false) return false;

    final settings = await _messaging.getNotificationSettings();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return false;

    const vapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');
    if (vapidKey.isEmpty) return false;

    final token = await _messaging.getToken(vapidKey: vapidKey);
    if (token == null || token.isEmpty) return false;

    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data();
    if (data == null) return false;

    final fcm = data['fcm'];
    if (fcm is! Map<String, dynamic>) return false;
    final tokens = fcm['webTokens'];
    if (tokens is! List) return false;

    final hasToken = tokens.whereType<String>().contains(token);
    if (preference == null) {
      // Backward compatibility: old users only tracked token existence.
      return hasToken;
    }
    return preference && hasToken;
  }

  Future<PushToggleResult> setNotificationEnabled({
    required String userId,
    required bool enabled,
  }) async {
    if (!kIsWeb) {
      return const PushToggleResult(
        enabled: false,
        failureReason: PushToggleFailureReason.notWeb,
      );
    }
    if (!_initialized) {
      return const PushToggleResult(
        enabled: false,
        failureReason: PushToggleFailureReason.notInitialized,
      );
    }
    _currentUserId = userId;

    const vapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');
    if (vapidKey.isEmpty) {
      log(
        'Missing FCM_WEB_VAPID_KEY. Run with '
        '--dart-define=FCM_WEB_VAPID_KEY=<PUBLIC_VAPID_KEY>.',
      );
      return const PushToggleResult(
        enabled: false,
        failureReason: PushToggleFailureReason.missingVapidKey,
      );
    }

    if (enabled) {
      final granted = await _ensureNotificationPermission();
      if (!granted) {
        await _setWeeklyRosterReminderPreference(userId, enabled: false);
        return const PushToggleResult(
          enabled: false,
          failureReason: PushToggleFailureReason.permissionDenied,
        );
      }

      final token = await _messaging.getToken(vapidKey: vapidKey);
      if (token == null || token.isEmpty) {
        await _setWeeklyRosterReminderPreference(userId, enabled: false);
        return const PushToggleResult(
          enabled: false,
          failureReason: PushToggleFailureReason.tokenUnavailable,
        );
      }
      final saveTokenSuccess = await _saveToken(userId, token);
      if (!saveTokenSuccess) {
        return const PushToggleResult(
          enabled: false,
          failureReason: PushToggleFailureReason.saveTokenFailed,
        );
      }
      final savePreferenceSuccess = await _setWeeklyRosterReminderPreference(
        userId,
        enabled: true,
      );
      if (!savePreferenceSuccess) {
        return const PushToggleResult(
          enabled: false,
          failureReason: PushToggleFailureReason.savePreferenceFailed,
        );
      }
      return const PushToggleResult(enabled: true);
    }

    final savePreferenceSuccess = await _setWeeklyRosterReminderPreference(
      userId,
      enabled: false,
    );
    if (!savePreferenceSuccess) {
      return const PushToggleResult(
        enabled: false,
        failureReason: PushToggleFailureReason.savePreferenceFailed,
      );
    }
    return const PushToggleResult(enabled: false);
  }

  Future<bool> _saveToken(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'fcm': {
          'webTokens': FieldValue.arrayUnion([token]),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      return true;
    } catch (e, st) {
      log('Save FCM token failed: $e', stackTrace: st);
      return false;
    }
  }

  Future<bool> _setWeeklyRosterReminderPreference(
    String userId, {
    required bool enabled,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'notificationPrefs': {
          'weeklyRosterReminder': enabled,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      return true;
    } catch (e, st) {
      log('Save notification preference failed: $e', stackTrace: st);
      return false;
    }
  }

  Future<bool?> _getWeeklyRosterReminderPreference(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();
      if (data == null) return null;
      final prefs = data['notificationPrefs'];
      if (prefs is! Map<String, dynamic>) return null;
      final raw = prefs['weeklyRosterReminder'];
      if (raw is bool) return raw;
      return null;
    } catch (e, st) {
      log('Read notification preference failed: $e', stackTrace: st);
      return null;
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
