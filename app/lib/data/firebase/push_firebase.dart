import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/push.dart';

/// FCM on this device. Each device keeps its own token at
/// users/{uid}.fcm.{deviceId}, readable only by the owner and the backend
/// (firestore.rules). iOS goes through APNs; the web needs a VAPID key and
/// web/firebase-messaging-sw.js.
class FirebasePushService implements PushService {
  FirebasePushService({required this.prefs, FirebaseFirestore? firestore, FirebaseMessaging? messaging})
    : _db = firestore ?? FirebaseFirestore.instance,
      _messaging = messaging ?? FirebaseMessaging.instance;

  final SharedPreferences prefs;
  final FirebaseFirestore _db;
  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _refresh;

  static const _vapidKey = String.fromEnvironment('FCM_VAPID_KEY');

  /// A stable random ID for this install, so a refreshed token replaces the
  /// old one instead of piling up.
  String get deviceId {
    const key = 'push_device_id';
    final existing = prefs.getString(key);
    if (existing != null) return existing;
    final rng = Random.secure();
    final id = List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
    prefs.setString(key, id);
    return id;
  }

  static PushPermission _map(AuthorizationStatus s) => switch (s) {
    AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notAsked,
  };

  String? _uid;

  @override
  Future<PushPermission> permission() async {
    if (kIsWeb && _vapidKey.isEmpty) return PushPermission.unsupported;
    try {
      return _map((await _messaging.getNotificationSettings()).authorizationStatus);
    } catch (_) {
      return PushPermission.unsupported;
    }
  }

  @override
  Future<PushPermission> enable() async {
    if (kIsWeb && _vapidKey.isEmpty) return PushPermission.unsupported;
    final settings = await _messaging.requestPermission();
    final status = _map(settings.authorizationStatus);
    final uid = _uid;
    if (status == PushPermission.granted && uid != null) await _register(uid);
    return status;
  }

  @override
  Future<void> refresh(String uid) async {
    _uid = uid;
    if (await permission() != PushPermission.granted) return;
    await _register(uid);
  }

  Future<void> _register(String uid) async {
    final token = await _messaging.getToken(vapidKey: kIsWeb ? _vapidKey : null);
    if (token != null) await _save(uid, token);
    await _refresh?.cancel();
    _refresh = _messaging.onTokenRefresh.listen((t) => _save(uid, t));
  }

  Future<void> _save(String uid, String token) => _db.doc('users/$uid').set({
    'fcm': {deviceId: token},
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  @override
  Stream<String> get openedLinks async* {
    final initial = await _messaging.getInitialMessage();
    final first = initial?.data['link'];
    if (first is String) yield first;
    await for (final m in FirebaseMessaging.onMessageOpenedApp) {
      final link = m.data['link'];
      if (link is String) yield link;
    }
  }

  @override
  Future<void> unregister(String uid) async {
    await _refresh?.cancel();
    _refresh = null;
    _uid = null;
    try {
      await _db.doc('users/$uid').update({'fcm.$deviceId': FieldValue.delete()});
      await _messaging.deleteToken();
    } catch (_) {
      // Signing out must not fail because of push.
    }
  }
}
