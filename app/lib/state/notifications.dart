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
