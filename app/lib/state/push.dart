import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

enum PushPermission { notAsked, granted, denied, unsupported }

/// Push notifications on this device: permission and the FCM token stored
/// at users/{uid}.fcm.{deviceId}. The Firebase implementation lives in
/// data/firebase/push_firebase.dart; tests and the demo use [NoPush].
abstract interface class PushService {
  Future<PushPermission> permission();

  /// Asks for permission if needed and registers this device's token.
  Future<PushPermission> enable();

  /// Once turned off, the phone does not ask again: only its settings page
  /// for this app turns notifications back on. A browser has none.
  bool get canOpenSettings;

  Future<void> openSettings();

  /// Registers the token again if permission was granted earlier, e.g. at
  /// sign-in. Never prompts.
  Future<void> refresh(String uid);

  /// Removes this device's token, at sign-out.
  Future<void> unregister(String uid);

  /// Nobody is signed in: a token left on an account that signed out with
  /// no connection is deleted, so this device stops getting its pushes.
  Future<void> signedOut();

  /// App routes from notifications the user tapped, including the one that
  /// launched the app.
  Stream<String> get openedLinks;

  /// Notifications that arrive while the app is open in front. The system
  /// does not show these, so the app does.
  Stream<PushNotice> get foreground;

  /// Puts [count] on the app icon, what is unread in the 通知列表 (#89);
  /// 0 takes it off. Where the icon shows no number, nothing. Never fails.
  Future<void> setBadge(int count);
}

/// A notification received while the app is open.
class PushNotice {
  const PushNotice({required this.title, required this.body, this.link});

  final String title;
  final String body;

  /// App route to open, as in [PushService.openedLinks].
  final String? link;
}

class NoPush implements PushService {
  const NoPush();

  @override
  Future<PushPermission> permission() async => PushPermission.unsupported;

  @override
  Future<PushPermission> enable() async => PushPermission.unsupported;

  @override
  bool get canOpenSettings => false;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> refresh(String uid) async {}

  @override
  Future<void> unregister(String uid) async {}

  @override
  Future<void> signedOut() async {}

  @override
  Stream<String> get openedLinks => const Stream.empty();

  @override
  Stream<PushNotice> get foreground => const Stream.empty();

  @override
  Future<void> setBadge(int count) async {}
}

/// Overridden in main() with the Firebase implementation.
final pushServiceProvider = Provider<PushService>((ref) => const NoPush());

final pushPermissionProvider = FutureProvider<PushPermission>((ref) {
  ref.watch(uidProvider);
  return ref.watch(pushServiceProvider).permission();
});

final pushLinksProvider = StreamProvider<String>((ref) => ref.watch(pushServiceProvider).openedLinks);

final pushNoticesProvider = StreamProvider<PushNotice>((ref) => ref.watch(pushServiceProvider).foreground);
