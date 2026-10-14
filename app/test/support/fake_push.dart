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
  });

  /// The permission now; turned on in the phone's settings, a test sets it.
  PushPermission state;

  /// What the permission prompt comes back with.
  final PushPermission answer;

  /// False: allowed, but the device gets no token.
  final bool registers;

  /// False: a phone without a notification settings page to open.
  final bool hasSettings;
  final notices = StreamController<PushNotice>.broadcast();

  /// How many times the permission prompt and the phone's settings opened.
  int asked = 0;
  int settingsOpened = 0;

  @override
  Future<PushPermission> permission() async => state;

  @override
  Future<PushPermission> enable() async {
    asked++;
    if (!registers) throw Exception('apns-token-not-set');
    if (answer != PushPermission.notAsked) state = answer;
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
  Future<void> unregister(String uid) async {}

  @override
  Stream<String> get openedLinks => const Stream.empty();

  @override
  Stream<PushNotice> get foreground => notices.stream;
}
