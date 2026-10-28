import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/telemetry.dart';
import '../domain/limits.dart';
import '../domain/models.dart';
import 'providers.dart';
import 'notifications.dart';
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
    final push = ref.read(pushServiceProvider);
    (uid != null ? push.refresh(uid) : push.signedOut()).ignore();
  }, fireImmediately: true);

  // Known before joining, which decides at once whether to ask for it.
  ref.listen(pushPermissionProvider, (_, _) {});

  // The app icon's number: what is unread in the 通知列表 (#89), here as
  // it changes; pushes bring it while the app is closed.
  ref.listen(unreadTotalProvider, (_, count) {
    if (count != null) ref.read(pushServiceProvider).setBadge(count).ignore();
  }, fireImmediately: true);

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

  // The home-screen icon, as nextAppIcon has it: a lapsed subscription's
  // goes, and a church's own comes on, at the same go, so one never waits
  // out the other. A moment after the church's page is up, or the church
  // joined, so the system's note on the change comes over the page, not
  // over the splash. Refused, it is tried again next time.
  Timer? soon;
  ref.onDispose(() => soon?.cancel());
  void settleIcon() {
    soon?.cancel();
    soon = Timer(const Duration(milliseconds: 600), () async {
      final stage = ref.read(appStageProvider);
      final church = ref.read(myChurchIconProvider);
      try {
        final change = nextAppIcon(
          current: await ref.read(currentAppIconProvider.future),
          supporter: ref.read(supporterProvider),
          churchKnown: !ref.read(isWebProvider) && stage != AppStage.loading && stage != AppStage.signedOut,
          church: church,
          placedBefore: church != null && ref.read(churchIconPlacedProvider(church.iconId)),
        );
        if (change == null) return;
        await ref.read(currentAppIconProvider.notifier).set(change.to);
        if (change.placed case final placed?) {
          ref.read(churchIconPlacedProvider(placed.iconId).notifier).mark();
          ref.read(churchIconChangedProvider.notifier).tell(placed);
        }
      } catch (_) {
        return;
      }
    });
  }

  ref.listen(supporterProvider, (_, _) => settleIcon());
  ref.listen(appStageProvider, (_, _) => settleIcon(), fireImmediately: true);
  ref.listen(myChurchIconProvider, (_, _) => settleIcon());
});

/// How long signing out waits for this device's token to come off the
/// account.
const signOutPushWait = Duration(seconds: 3);

/// Signs out: this device stops getting pushes, and the picked church is
/// forgotten. With no connection, taking this device's token off the
/// account waits for one, so signing out goes on after [signOutPushWait];
/// the token is then deleted at the next sign-in or launch
/// (FirebasePushService).
Future<void> signOut(WidgetRef ref) async {
  final uid = ref.read(uidProvider);
  if (uid != null) await ref.read(pushServiceProvider).unregister(uid).timeout(signOutPushWait, onTimeout: () {});
  await ref.read(selectedChurchProvider.notifier).forget();
  await ref.read(backendProvider).auth.signOut();
}
