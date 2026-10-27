import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../deep_link.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/notifications.dart';
import '../../state/providers.dart';
import '../common/time_zones.dart';
import '../me/turn_on_notifications.dart';

/// The bell on 首頁: opens the 通知列表, with a dot while this church's has
/// something unread.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    // Worked out here, not in a provider of its own: one that is paused on
    // a tab out of sight and resumes as the tab comes back, mid-build,
    // cannot rebuild the providers watching it then.
    final cid = ref.watch(currentChurchIdProvider);
    final seen = ref.watch(profileProvider.select((p) => p.value?.notificationsSeen[cid]));
    final unread = ref.watch(
      myNotificationsProvider.select(
        (list) => unreadNotifications((list.value ?? const []).where((n) => n.churchId == cid), {?cid: ?seen}) > 0,
      ),
    );
    return IconButton(
      tooltip: unread ? l10n.notifUnreadLabel : l10n.notifications,
      onPressed: () => context.push('/home/notifications'),
      icon: Badge(
        isLabelVisible: unread,
        smallSize: 9,
        backgroundColor: AppColors.of(context).destructive,
        child: const Icon(Symbols.notifications_rounded),
      ),
    );
  }
}

/// 通知列表 (#89): what was sent to me in this church over the last 30 days,
/// newest first, the kinds I muted too. Opening it reads them all, here and
/// on the app icon; those unread when it opened keep a dot while it is open.
/// Each opens the page its push opens.
class NotificationListScreen extends ConsumerStatefulWidget {
  const NotificationListScreen({super.key});

  @override
  ConsumerState<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends ConsumerState<NotificationListScreen> {
  /// How far this church's list was seen before it opened.
  DateTime? _seenBefore;

  @override
  void initState() {
    super.initState();
    final cid = ref.read(currentChurchIdProvider);
    _seenBefore = ref.read(profileProvider).value?.notificationsSeen[cid];
    // Seen as they show, the ones arriving while it is open too.
    ref.listenManual(churchNotificationsProvider, (_, next) => _markSeen(next.value), fireImmediately: true);
  }

  void _markSeen(List<NotificationItem>? list) {
    final uid = ref.read(uidProvider);
    final cid = ref.read(currentChurchIdProvider);
    if (list == null || list.isEmpty || uid == null || cid == null) return;
    final newest = list.first.at;
    final seen = ref.read(profileProvider).value?.notificationsSeen[cid];
    if (unreadNotifications(list, {cid: ?seen}) == 0) return;
    // Queued offline like any write; a refusal leaves them unread, no more.
    ref.read(backendProvider).profiles.markNotificationsSeen(uid, cid, newest).catchError((Object _) {});
  }

  void _open(NotificationItem n) {
    final location = appLocation(n.link);
    if (location == null || location == '/home') {
      context.pop();
    } else {
      context.push(location);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final clock = ChurchClock.of(context, ref);
    final now = ref.watch(clockProvider)();
    final churchName = ref.watch(churchProvider).value?.name;
    final turnOn = TurnOnNotificationsCard.shown(ref);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notifications),
        actions: [
          IconButton(
            tooltip: l10n.notifSettings,
            icon: const Icon(Symbols.tune_rounded),
            onPressed: () => context.push('/me/notifications'),
          ),
        ],
      ),
      body: ref
          .watch(churchNotificationsProvider)
          .when(
            skipLoadingOnReload: true,
            loading: () => const SizedBox.shrink(),
            error: (_, _) => ErrorRetry(
              message: l10n.loadFailed,
              onRetry: () => ref.invalidate(myNotificationsProvider),
            ),
            data: (list) => ListView(
              children: [
                if (turnOn) const TurnOnNotificationsCard(),
                if (list.isEmpty)
                  EmptyState(icon: Symbols.notifications_rounded, message: l10n.notifListEmpty)
                else
                  ListSection(
                    children: [
                      for (final n in list)
                        _row(
                          l10n,
                          c,
                          n,
                          // Most pushes are headed with the church's name,
                          // which this list is already about.
                          headline: n.title.isEmpty || n.title == churchName ? n.body : n.title,
                          when: clock.ago(n.at, now),
                          unread: unreadNotifications([n], {n.churchId: ?_seenBefore}) > 0,
                        ),
                    ],
                  ),
              ],
            ),
          ),
    );
  }

  ListRow _row(
    L10n l10n,
    AppColors c,
    NotificationItem n, {
    required String headline,
    required String when,
    required bool unread,
  }) => ListRow(
    leading: Icon(_icons[n.kind] ?? Symbols.notifications_rounded),
    title: headline,
    subtitle: [if (headline != n.body) n.body, when].join('\n'),
    trailing: unread
        ? Semantics(
            label: l10n.notifUnread,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
            ),
          )
        : null,
    chevron: true,
    onTap: () => _open(n),
  );
}

const _icons = {
  NotificationKind.reminder: Symbols.event_upcoming_rounded,
  NotificationKind.rosterChange: Symbols.edit_calendar_rounded,
  NotificationKind.memberLeft: Symbols.person_remove_rounded,
  NotificationKind.attendance: Symbols.groups_rounded,
  NotificationKind.joinRequest: Symbols.person_add_rounded,
};
