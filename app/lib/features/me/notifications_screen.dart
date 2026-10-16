import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/push.dart';
import '../church/add_to_home.dart';
import 'turn_on_notifications.dart';

/// Which notifications I get from this church, and when I am reminded of my
/// duties. Stored on my member doc (`notificationPrefs`, the one field I may
/// write there). Until the phone allows notifications the switches are off,
/// and turning one on asks for it.
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
    final needsHomeScreen = ref.watch(addToHomeProvider) == AddToHome.ios;
    // The phone will not ask: the switches are greyed out.
    final blocked = permission == PushPermission.denied || needsHomeScreen;
    final shownOff = blocked || permission == PushPermission.notAsked;
    final churchId = ref.watch(currentChurchIdProvider);

    Future<void> set(NotificationKind kind, bool on) async {
      // Saved even if this page is left while the phone asks.
      final data = ref.churchData;
      if (on && permission == PushPermission.notAsked) {
        // Once allowed, each launch registers the device again. Asking that
        // failed (registering, mostly) still keeps the choice.
        final result = await enableNotifications(context, nudge: true);
        if (result != null && result != PushPermission.granted) return;
      }
      final next = on ? ({...muted}..remove(kind)) : {...muted, kind};
      try {
        await data.setNotificationPrefs(me.uid, next);
      } catch (_) {
        if (context.mounted) showToast(context, l10n.saveFailed);
      }
    }

    Future<void> setTiming(ReminderTiming timing) async {
      try {
        await ref.churchData.setReminderTiming(me.uid, timing);
      } catch (_) {
        if (context.mounted) showToast(context, l10n.saveFailed);
      }
    }

    final timings = [
      (ReminderTiming.weekly, l10n.notifReminderWeekly, l10n.notifReminderWeeklySub),
      (ReminderTiming.dayBefore, l10n.notifReminderDayBefore, l10n.notifReminderDayBeforeSub),
      (ReminderTiming.both, l10n.notifReminderBoth, l10n.notifReminderBothSub),
    ];
    // While the timing choice shows below, the switch does not repeat it.
    final timingShown = !shownOff && !muted.contains(NotificationKind.reminder);
    final reminderSub = timingShown ? null : timings.firstWhere((t) => t.$1 == me.reminderTiming).$3;
    final kinds = [
      (NotificationKind.reminder, l10n.notifReminder, reminderSub),
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
              children: [
                ListRow(
                  title: l10n.notifNeedsHomeScreen,
                  leading: const Icon(Icons.add_to_home_screen),
                  onTap: churchId == null ? null : () => openAddToHome(context, ref, churchId),
                ),
              ],
            )
          else if (permission == PushPermission.denied)
            ListSection(
              footer: l10n.notifPermissionOff,
              children: [
                if (ref.watch(pushServiceProvider).canOpenSettings)
                  ListRow(
                    title: l10n.notifOpenSettings,
                    leading: const Icon(Icons.settings_outlined),
                    onTap: () => openNotificationSettings(context, ref),
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
                  value: !shownOff && !muted.contains(kind),
                  onChanged: blocked ? null : (v) => set(kind, v),
                ),
            ],
          ),
          if (timingShown)
            ListSection(
              header: l10n.notifReminderTime,
              footer: l10n.notifReminderTimeFooter,
              children: [
                for (final (timing, title, _) in timings)
                  ListRow(
                    title: title,
                    selected: me.reminderTiming == timing,
                    onTap: () => setTiming(timing),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
