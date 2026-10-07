import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/telemetry.dart';
import '../domain/limits.dart';
import '../domain/models.dart';
import 'providers.dart';
import 'push.dart';

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

  ref.listen(currentChurchIdProvider, (_, cid) => ref.read(telemetryProvider).setChurch(cid), fireImmediately: true);
});

/// Signs out: this device stops getting pushes, and the picked church is
/// forgotten.
Future<void> signOut(WidgetRef ref) async {
  final uid = ref.read(uidProvider);
  if (uid != null) await ref.read(pushServiceProvider).unregister(uid);
  await ref.read(prefsProvider).remove('selected_church');
  await ref.read(backendProvider).auth.signOut();
}
