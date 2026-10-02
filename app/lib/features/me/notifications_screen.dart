import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/push.dart';

/// Which notifications I get from this church. Stored on my member doc
/// (`notificationPrefs`, the one field I may write there). The system
/// permission is asked for here, the first time it is needed.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider).value;
    final permission = ref.watch(pushPermissionProvider).value;
    if (me == null) return Scaffold(appBar: AppBar());
    final muted = me.mutedNotifications;

    Future<void> set(NotificationKind kind, bool on) async {
      if (on) {
        await ref.read(pushServiceProvider).enable();
        ref.invalidate(pushPermissionProvider);
      }
      final next = on ? ({...muted}..remove(kind)) : {...muted, kind};
      try {
        await ref.read(churchDataProvider)!.setNotificationPrefs(me.uid, next);
      } catch (_) {
        if (context.mounted) showToast(context, l10n.saveFailed);
      }
    }

    final kinds = [
      (NotificationKind.reminder, l10n.notifReminder, l10n.notifReminderSub),
      (
        NotificationKind.rosterChange,
        l10n.notifRosterChange,
        l10n.notifRosterChangeSub,
      ),
      if (me.isAdmin)
        (
          NotificationKind.memberLeft,
          l10n.notifMemberLeft,
          l10n.notifMemberLeftSub,
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      body: ListView(
        children: [
          if (permission == PushPermission.denied) ListSection(footer: l10n.notifPermissionOff, children: const []),
          if (permission == PushPermission.notAsked)
            ListSection(
              children: [
                ListRow(
                  title: l10n.notifEnable,
                  leading: const Icon(Icons.notifications_active_outlined),
                  onTap: () async {
                    await ref.read(pushServiceProvider).enable();
                    ref.invalidate(pushPermissionProvider);
                  },
                ),
              ],
            ),
          ListSection(
            header: l10n.notifThisChurch,
            children: [
              for (final (kind, title, sub) in kinds)
                SwitchRow(
                  title: title,
                  subtitle: sub,
                  value: permission != PushPermission.denied && !muted.contains(kind),
                  onChanged: permission == PushPermission.denied ? null : (v) => set(kind, v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
