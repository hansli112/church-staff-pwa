import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import 'providers.dart';

/// My 通知列表 (#89), every church's, newest first: the last 30 days, also
/// before the backend's daily clean-up has taken the older ones out.
final myNotificationsProvider = StreamProvider<List<NotificationItem>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  final now = ref.watch(clockProvider);
  return ref
      .watch(backendProvider)
      .profiles
      .notifications(uid)
      .map(
        (list) => [
          for (final n in list)
            if (now().difference(n.at) < notificationDays) n,
        ],
      );
});

/// The current church's 通知列表, as far as I have seen it; null with no
/// church.
final churchNotificationListProvider = Provider<AsyncValue<NotificationList>?>((ref) {
  final cid = ref.watch(currentChurchIdProvider);
  if (cid == null) return null;
  final seen = ref.watch(profileProvider.select((p) => p.value?.notificationsSeen[cid]));
  return ref.watch(myNotificationsProvider).whenData((all) => NotificationList(cid, all, seen));
});

/// What is unread in all my churches: the number on the app icon; 0 signed
/// out. Null until the sign-in, the list and the profile have loaded.
final unreadTotalProvider = Provider<int?>((ref) {
  // Not 0 while the saved sign-in is still being restored: that would take
  // the number off the icon at every launch.
  if (ref.watch(authUserProvider.select((u) => u.isLoading && !u.hasValue))) return null;
  if (ref.watch(uidProvider) == null) return 0;
  final all = ref.watch(myNotificationsProvider).value;
  final profile = ref.watch(profileProvider).value;
  if (all == null || profile == null) return null;
  return unreadNotifications(all, profile.notificationsSeen);
});

/// How long a tapped notification is waited for in the list: launched by
/// the tap, the list may come from the cache first, without it.
const tappedNotificationWait = Duration(seconds: 30);

/// Notification [id] of church [churchId] was tapped: read, as if seen in
/// its 通知列表, when nothing older there is unread
/// ([NotificationList.seenOnTapping]). Never fails.
Future<void> markTappedSeen(Ref ref, String churchId, String id) async {
  final uid = ref.read(uidProvider);
  if (uid == null) return;
  final profiles = ref.read(backendProvider).profiles;
  try {
    final all = await _firstWith(profiles.notifications(uid), id);
    final seen = (await profiles.watch(uid).first)?.notificationsSeen[churchId];
    final upTo = NotificationList(churchId, all, seen).seenOnTapping(id);
    // The profile may be from the cache too: never back from what another
    // device, or the list, has seen since.
    if (upTo != null) await profiles.markNotificationsSeen(uid, churchId, upTo, onlyForward: true);
  } catch (_) {
    // Not there in time, or no connection: it stays unread, no more.
  }
}

/// The first of [lists] that has notification [id], or a TimeoutException
/// after [tappedNotificationWait]; either way it stops listening.
Future<List<NotificationItem>> _firstWith(Stream<List<NotificationItem>> lists, String id) {
  final found = Completer<List<NotificationItem>>();
  late final StreamSubscription<List<NotificationItem>> sub;
  void end(void Function() result) {
    if (found.isCompleted) return;
    unawaited(sub.cancel());
    result();
  }

  final wait = Timer(tappedNotificationWait, () => end(() => found.completeError(TimeoutException(null))));
  sub = lists.listen(
    (list) {
      if (list.any((n) => n.id == id)) end(() => found.complete(list));
    },
    onError: (Object e, StackTrace st) => end(() => found.completeError(e, st)),
  );
  return found.future.whenComplete(wait.cancel);
}
