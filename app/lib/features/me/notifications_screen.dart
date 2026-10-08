import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/push.dart';
import '../../state/session.dart';
import '../church/add_to_home.dart';

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
    // Safari gets no notifications: only the page opened from the home screen.
    final needsHomeScreen = ref.watch(addToHomeProvider) == AddToHome.iphone;
    final off = permission == PushPermission.denied || needsHomeScreen;

    // Registering can fail even when allowed (no APNs token yet); the next
    // launch tries again, so say so instead of looking stuck.
    Future<PushPermission?> enable() async {
      try {
        return await ref.read(pushServiceProvider).enable();
      } catch (e, stack) {
        ref.read(telemetryProvider).recordError(e, stack);
        if (context.mounted) showToast(context, l10n.notifRegisterFailed);
        return null;
      } finally {
        ref.invalidate(pushPermissionProvider);
      }
    }

    Future<void> set(NotificationKind kind, bool on) async {
      // Once allowed, each launch registers the device again.
      if (on && permission == PushPermission.notAsked) await enable();
      final next = on ? ({...muted}..remove(kind)) : {...muted, kind};
      try {
        await ref.churchData.setNotificationPrefs(me.uid, next);
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
          if (needsHomeScreen)
            ListSection(
              footer: l10n.notifNeedsHomeScreen,
              children: [
                ListRow(
                  title: l10n.notifHowToAddToHome,
                  leading: const Icon(Icons.add_to_home_screen),
                  onTap: () => context.push('/add-to-home'),
                ),
              ],
            )
          else if (permission == PushPermission.denied)
            ListSection(footer: l10n.notifPermissionOff, children: const [])
          else if (permission == PushPermission.notAsked)
            ListSection(
              children: [
                ListRow(
                  title: l10n.notifEnable,
                  leading: const Icon(Icons.notifications_active_outlined),
                  onTap: () async {
                    final result = await enable();
                    // Dismissed, or tucked into the address bar by the browser.
                    if (result == PushPermission.notAsked && context.mounted) showToast(context, l10n.notifNotAllowed);
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
                  value: !off && !muted.contains(kind),
                  onChanged: off ? null : (v) => set(kind, v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
