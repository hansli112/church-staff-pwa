import 'dart:async';

import 'package:martha/state/push.dart';

/// Push on a phone whose permission starts at [state] and becomes
/// [answer] once asked.
class FakePush implements PushService {
  FakePush({
    this.state = PushPermission.notAsked,
    this.answer = PushPermission.notAsked,
    this.registers = true,
    this.hasSettings = true,
    this.prompt,
    this.forgetting,
  });

  /// The permission now; turned on in the phone's settings, a test sets it.
  PushPermission state;

  /// What the permission prompt comes back with.
  final PushPermission answer;

  /// False: allowed, but the device gets no token.
  final bool registers;

  /// False: a phone without a notification settings page to open.
  final bool hasSettings;

  /// Set: the prompt stays up until it completes, as the phone's does while
  /// the app goes to the background and back.
  final Completer<void>? prompt;

  /// Set: forgetting this device at sign-out waits until it completes, as
  /// it does with no connection.
  final Completer<void>? forgetting;
  final notices = StreamController<PushNotice>.broadcast();

  /// How many times the permission prompt and the phone's settings opened.
  int asked = 0;
  int settingsOpened = 0;

  @override
  Future<PushPermission> permission() async => state;

  @override
  Future<PushPermission> enable() async {
    asked++;
    if (answer != PushPermission.notAsked) state = answer;
    await prompt?.future;
    // Allowed on the phone, then no token to register.
    if (!registers) throw Exception('apns-token-not-set');
    return answer;
  }

  @override
  bool get canOpenSettings => true;

  @override
  Future<void> openSettings() async {
    if (!hasSettings) throw Exception('no_settings');
    settingsOpened++;
  }

  @override
  Future<void> refresh(String uid) async {}

  @override
  Future<void> unregister(String uid) async => forgetting?.future;

  @override
  Stream<String> get openedLinks => const Stream.empty();

  @override
  Stream<PushNotice> get foreground => notices.stream;

  /// The number on the app icon, once set.
  int? badge;

  @override
  Future<void> setBadge(int count) async => badge = count;
}
