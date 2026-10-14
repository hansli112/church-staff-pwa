import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/telemetry.dart';
import '../domain/limits.dart';
import '../domain/models.dart';
import 'providers.dart';
import 'push.dart';
import 'support.dart';

/// Overridden in main() for builds that report to Firebase.
final telemetryProvider = Provider<Telemetry>((ref) => const NoTelemetry());

/// Side effects of who is signed in and which church is open. Watched once
/// by the app root.
final sessionEffectsProvider = Provider<void>((ref) {
  // users/{uid} the first time someone signs in. Once per account: the user
  // changes again on every reload and token refresh.
  String? ensured;
  ref.listen(authUserProvider, (_, next) {
    final user = next.value;
    if (user == null || user.uid == ensured) return;
    // An email sign-up sets its name a moment after the account exists;
    // wait for it rather than saving the email prefix as the name.
    if (user.usesPassword && (user.displayName?.trim().isEmpty ?? true)) return;
    final uid = user.uid;
    ensured = uid;
    ref
        .read(backendProvider)
        .profiles
        .ensure(
          UserProfile(
            uid: user.uid,
            name: cutText(
              user.displayName?.trim().isNotEmpty == true ? user.displayName! : user.email.split('@').first,
              TextLimits.profileName,
            ),
            email: user.email,
          ),
        )
        // Failed (offline at first sign-in): try again on the next change.
        .catchError((Object _) {
          if (ensured == uid) ensured = null;
        });
  }, fireImmediately: true);

  ref.listen(uidProvider, (_, uid) {
    ref.read(telemetryProvider).setUser(uid);
    if (uid != null) ref.read(pushServiceProvider).refresh(uid).ignore();
  }, fireImmediately: true);

  // Known before joining, which decides at once whether to ask for it.
  ref.listen(pushPermissionProvider, (_, _) {});

  // Back from the phone's settings, maybe with notifications turned on.
  final lifecycle = AppLifecycleListener(
    onResume: () {
      final uid = ref.read(uidProvider);
      final wasOn = ref.read(pushPermissionProvider).value == PushPermission.granted;
      ref.invalidate(pushPermissionProvider);
      if (uid != null && !wasOn) ref.read(pushServiceProvider).refresh(uid).ignore();
    },
  );
  ref.onDispose(lifecycle.dispose);

  ref.listen(currentChurchIdProvider, (_, cid) => ref.read(telemetryProvider).setChurch(cid), fireImmediately: true);

  // A lapsed subscription takes its icon back.
  ref.listen(supporterProvider, (_, active) async {
    if (active) return;
    final icons = ref.read(appIconSwitcherProvider);
    if (await icons.current() != null) await icons.set(null);
  }, fireImmediately: true);
});

/// Signs out: this device stops getting pushes, and the picked church is
/// forgotten.
Future<void> signOut(WidgetRef ref) async {
  final uid = ref.read(uidProvider);
  if (uid != null) await ref.read(pushServiceProvider).unregister(uid);
  await ref.read(selectedChurchProvider.notifier).forget();
  await ref.read(backendProvider).auth.signOut();
}
