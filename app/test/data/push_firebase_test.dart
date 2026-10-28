import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/push_firebase.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('signed out with no connection, the next account on this device gets a new token', () async {
    final prefs = await SharedPreferences.getInstance();
    final messaging = _Messaging();
    final db = _Firestore();
    final push = FirebasePushService(prefs: prefs, firestore: db, messaging: messaging);
    await push.refresh('mei');
    expect(db.tokens('mei'), {push.deviceId: 'token-1'});

    db.offline = true;
    messaging.offline = true;
    await push.unregister('mei');
    expect(db.tokens('mei'), {push.deviceId: 'token-1'}, reason: 'still on her account');

    db.offline = false;
    messaging.offline = false;
    await push.refresh('jun');
    // Hers stops working, so the backend drops it the next time it sends.
    expect(messaging.live, 'token-2');
    expect(db.tokens('jun'), {push.deviceId: 'token-2'});
  });

  test('the same account signing in again keeps its token', () async {
    final prefs = await SharedPreferences.getInstance();
    final messaging = _Messaging();
    final db = _Firestore();
    final push = FirebasePushService(prefs: prefs, firestore: db, messaging: messaging);
    await push.refresh('mei');
    await push.refresh('mei');
    expect(messaging.live, 'token-1');
  });

  test('signed out normally, the next account does not replace a token again', () async {
    final prefs = await SharedPreferences.getInstance();
    final messaging = _Messaging();
    final db = _Firestore();
    final push = FirebasePushService(prefs: prefs, firestore: db, messaging: messaging);
    await push.refresh('mei');
    await push.unregister('mei');
    expect(db.tokens('mei'), isEmpty);
    await push.refresh('jun');
    expect(messaging.live, 'token-2', reason: 'the one signing out deleted token-1');
    expect(messaging.deleted, 1);
  });
}

/// FCM: a token until it is deleted, then a new one.
class _Messaging extends Fake implements FirebaseMessaging {
  var _n = 1;
  var deleted = 0;
  var offline = false;

  String get live => 'token-$_n';

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
    _n++;
  }

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}

/// users/{uid}.fcm, and no connection when [offline].
class _Firestore extends Fake implements FirebaseFirestore {
  final _fcm = <String, Map<String, String>>{};
  var offline = false;

  Map<String, String> tokens(String uid) => _fcm[uid] ?? {};

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
    if (db.offline) throw Exception('unavailable');
    db._fcm.putIfAbsent(uid, () => {}).addAll((data['fcm'] as Map).cast<String, String>());
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    if (db.offline) throw Exception('unavailable');
    for (final key in data.keys) {
      db._fcm[uid]?.remove((key as String).substring('fcm.'.length));
    }
  }
}
