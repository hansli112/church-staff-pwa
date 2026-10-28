import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/push_firebase.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _Messaging messaging;
  late _Firestore db;
  late FirebasePushService push;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    messaging = _Messaging();
    db = _Firestore();
    push = FirebasePushService(prefs: await SharedPreferences.getInstance(), firestore: db, messaging: messaging);
    await push.refresh('mei');
    expect(db.tokens('mei'), {push.deviceId: 'token-1'});
  });

  /// Signs mei out with no connection: taking her token off waits for one,
  /// and FCM cannot be reached to delete it. Sign-out goes on without it.
  Future<void> signOutOffline() async {
    db.offline = true;
    messaging.offline = true;
    unawaited(push.unregister('mei'));
    await pumpEventQueue();
    db.offline = false;
    messaging.offline = false;
  }

  test('signed out with no connection, the next account on this device gets a new token', () async {
    await signOutOffline();
    expect(db.tokens('mei'), {push.deviceId: 'token-1'}, reason: 'still on her account');

    await push.refresh('jun');
    // Hers stops working, so the backend drops it the next time it sends.
    expect(messaging.live, 'token-2');
    expect(db.tokens('jun'), {push.deviceId: 'token-2'});
  });

  test('her sign-out going through later leaves the next account its token', () async {
    await signOutOffline();
    await push.refresh('jun');
    db.reconnect();
    await pumpEventQueue();
    expect(db.tokens('mei'), isEmpty);
    expect(messaging.live, 'token-2');
    expect(db.tokens('jun'), {push.deviceId: 'token-2'});
  });

  test('signed out with no connection and nobody signs in: the next launch deletes her token', () async {
    await signOutOffline();
    await push.signedOut();
    expect(messaging.live, 'token-2');
    await push.signedOut();
    expect(messaging.deleted, 1, reason: 'once is enough');
  });

  test('the same account signing in again keeps its token', () async {
    await push.refresh('mei');
    expect(messaging.live, 'token-1');
  });

  test('signed out normally, nothing is deleted again', () async {
    await push.unregister('mei');
    expect(db.tokens('mei'), isEmpty);
    await push.signedOut();
    await push.refresh('jun');
    expect(messaging.live, 'token-2', reason: 'signing out deleted token-1');
    expect(messaging.deleted, 1);
  });
}

/// FCM: a token until it is deleted, then a new one.
class _Messaging extends Fake implements FirebaseMessaging {
  var _tokenNumber = 1;
  var deleted = 0;
  var offline = false;

  String get live => 'token-$_tokenNumber';

  @override
  Future<NotificationSettings> getNotificationSettings() async => const NotificationSettings(
    alert: AppleNotificationSetting.enabled,
    announcement: AppleNotificationSetting.disabled,
    authorizationStatus: AuthorizationStatus.authorized,
    badge: AppleNotificationSetting.enabled,
    carPlay: AppleNotificationSetting.disabled,
    lockScreen: AppleNotificationSetting.enabled,
    notificationCenter: AppleNotificationSetting.enabled,
    showPreviews: AppleShowPreviewSetting.always,
    timeSensitive: AppleNotificationSetting.disabled,
    criticalAlert: AppleNotificationSetting.disabled,
    sound: AppleNotificationSetting.enabled,
    providesAppNotificationSettings: AppleNotificationSetting.disabled,
  );

  @override
  Future<String?> getToken({String? vapidKey, String? serviceWorkerScriptPath}) async => live;

  @override
  Future<void> deleteToken() async {
    if (offline) throw Exception('unavailable');
    deleted++;
    _tokenNumber++;
  }

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}

/// users/{uid}.fcm on the server. With no connection, a write waits for
/// one, as Firestore's do, until [reconnect].
class _Firestore extends Fake implements FirebaseFirestore {
  final _fcm = <String, Map<String, String>>{};
  var offline = false;
  var _connection = Completer<void>();

  Map<String, String> tokens(String uid) => _fcm[uid] ?? {};

  void reconnect() {
    _connection.complete();
    _connection = Completer();
  }

  Future<void> _sent() async {
    if (offline) await _connection.future;
  }

  @override
  DocumentReference<Map<String, dynamic>> doc(String path) => _User(this, path.split('/').last);
}

// ignore: subtype_of_sealed_class
class _User extends Fake implements DocumentReference<Map<String, dynamic>> {
  _User(this.db, this.uid);

  final _Firestore db;
  final String uid;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    await db._sent();
    db._fcm.putIfAbsent(uid, () => {}).addAll((data['fcm'] as Map).cast<String, String>());
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    await db._sent();
    for (final key in data.keys) {
      db._fcm[uid]?.remove((key as String).substring('fcm.'.length));
    }
  }
}
