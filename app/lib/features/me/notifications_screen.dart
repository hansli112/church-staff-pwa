import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/push.dart';
import '../church/add_to_home.dart';
import 'turn_on_notifications.dart';
import '../common/errors.dart';
import '../common/site_pages.dart';
import '../common/saving_indicator.dart';
import 'unread_page.dart';

/// Which notifications I get from this church, and when I am reminded of my
/// duties. Stored on my member doc (`notificationPrefs`, the one field I may
/// write there). Until the phone allows notifications the switches are off,
/// and turning one on asks for it; allowed, only that one is on.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Turned on while the phone asks, and until it is saved: shown on, the
  /// rest waiting.
  NotificationKind? _asking;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider).value;
    final permission = ref.watch(pushPermissionProvider).value;
    if (me == null) return unreadPage(context, ref, [meProvider]);
    final muted = me.mutedNotifications;
    // Safari gets no notifications: only the page opened from the home screen.
    final needsHomeScreen = ref.watch(addToHomeProvider) == AddToHome.ios;
    // The phone will not ask: the switches are greyed out.
    final blocked = permission == PushPermission.denied || needsHomeScreen;
    final shownOff = blocked || permission == PushPermission.notAsked;
    final churchId = ref.watch(currentChurchIdProvider);

    final timing = me.reminderTiming;
    // While the timing choice shows below, the switch does not repeat it.
    final timingShown = !shownOff && !muted.contains(NotificationKind.reminder);
    final reminderSub = timingShown
        ? null
        : switch (timing) {
            ReminderTiming.weekly => l10n.notifReminderWeeklySub,
            ReminderTiming.dayBefore => l10n.notifReminderDayBeforeSub(me.reminderDays),
            ReminderTiming.both => l10n.notifReminderBothSub(me.reminderDays),
          };
    final kinds = [
      (NotificationKind.reminder, l10n.notifReminder, reminderSub),
      (
        NotificationKind.rosterChange,
        l10n.notifRosterChange,
        l10n.notifRosterChangeSub,
      ),
      (NotificationKind.swap, l10n.notifSwap, l10n.notifSwapSub),
      // 回報人數 (#85): for whoever is asked, while the church has it on.
      if (ref.watch(churchProvider.select((c) => c.value?.attendanceSince != null)) && me.remindedAttendance.isNotEmpty)
        (
          NotificationKind.attendance,
          l10n.notifAttendance,
          l10n.notifAttendanceSub,
        ),
    ];

    // Only an admin's; under their own heading, so the first list is the
    // same for everyone (2026-11-19).
    final adminKinds = [
      if (me.isAdmin) ...[
        (NotificationKind.memberJoined, l10n.notifMemberJoined, l10n.notifMemberJoinedSub),
        (NotificationKind.memberLeft, l10n.notifMemberLeft, l10n.notifMemberLeftSub),
        (NotificationKind.joinRequest, l10n.notifJoinRequest, l10n.notifJoinRequestSub),
      ],
    ];

    Future<void> set(NotificationKind kind, bool on) async {
      // Saved even if this page is left while the phone asks.
      final data = ref.churchData;
      var next = on ? ({...muted}..remove(kind)) : {...muted, kind};
      final asking = on && permission == PushPermission.notAsked;
      if (asking) setState(() => _asking = kind);
      try {
        if (asking) {
          // Once allowed, each launch registers the device again. Asking that
          // failed (registering, mostly) still keeps the choice.
          final result = await enableNotifications(context, nudge: true);
          if (result != null && result != PushPermission.granted) return;
          // The others showed off, so they stay off: only the one tapped.
          next = {
            ...muted,
            for (final (k, _, _) in [...kinds, ...adminKinds]) k,
          }..remove(kind);
        }
        await data.setNotificationPrefs(me.uid, next);
      } catch (e) {
        if (context.mounted) showToast(context, saveErrorText(l10n, e));
      } finally {
        if (asking && mounted) setState(() => _asking = null);
      }
    }

    // Null, from turning off the one left on, changes nothing: the switch
    // above turns reminders off.
    Future<bool> setTiming(ReminderTiming? next) async {
      if (next == null || next == timing) return true;
      try {
        await ref.churchData.setReminderTiming(me.uid, next);
        return true;
      } catch (e) {
        if (context.mounted) showToast(context, saveErrorText(l10n, e));
        return false;
      }
    }

    // A number typed is the one chosen: that row turns on too.
    Future<bool> setDays(int days) async {
      final data = ref.churchData;
      try {
        await data.setReminderDays(me.uid, days);
      } catch (e) {
        if (context.mounted) showToast(context, saveErrorText(l10n, e));
        return false;
      }
      return setTiming(timing.turned(daysBefore: true));
    }

    Future<void> pickHour() async {
      final data = ref.churchData;
      final hour = await showAppSheet<int>(
        context,
        builder: (context) => _HourSheet(hour: me.reminderHour),
      );
      if (hour == null || hour == me.reminderHour) return;
      try {
        await data.setReminderHour(me.uid, hour);
      } catch (e) {
        if (context.mounted) showToast(context, saveErrorText(l10n, e));
      }
    }

    Widget row((NotificationKind, String, String?) k) => SwitchRow(
      title: k.$2,
      subtitle: k.$3,
      value: _asking != null ? _asking == k.$1 : !shownOff && !muted.contains(k.$1),
      onChanged: blocked || _asking != null ? null : (v) => set(k.$1, v),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications), actions: savingActions(const [GuideButton(Guide.notifications)])),
      body: ListView(
        children: [
          if (needsHomeScreen)
            ListSection(
              children: [
                ListRow(
                  title: l10n.notifNeedsHomeScreen,
                  leading: const Icon(Symbols.add_to_home_screen_rounded),
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
                    leading: const Icon(Symbols.settings_rounded),
                    onTap: () => openNotificationSettings(context, ref),
                  ),
              ],
            ),
          ListSection(
            header: l10n.notifThisChurch,
            children: [for (final k in kinds) row(k)],
          ),
          if (adminKinds.isNotEmpty)
            ListSection(header: l10n.roleAdmin, children: [for (final k in adminKinds) row(k)]),
          if (timingShown)
            ListSection(
              header: l10n.notifReminderTime,
              footer: l10n.notifReminderTimeFooter(ReminderDays.first, ReminderDays.last),
              children: [
                ListRow(
                  title: l10n.notifReminderWeekly,
                  selected: timing.onMonday,
                  onTap: () => setTiming(timing.turned(onMonday: !timing.onMonday)),
                ),
                _DaysBeforeRow(
                  days: me.reminderDays,
                  selected: timing.daysBefore,
                  onTap: () => setTiming(timing.turned(daysBefore: !timing.daysBefore)),
                  onDays: setDays,
                ),
              ],
            ),
          if (timingShown)
            ListSection(
              children: [
                ListRow(title: l10n.notifReminderHour, value: hourLabel(l10n, me.reminderHour), onTap: pickHour),
              ],
            ),
        ],
      ),
    );
  }
}

/// [hour] (0–23) as a reminder's time is said: 早上 8 點, 中午 12 點, 晚上 7 點.
String hourLabel(L10n l10n, int hour) => switch (hour) {
  < 12 => l10n.hourMorning(hour),
  12 => l10n.hourNoon,
  < 18 => l10n.hourAfternoon(hour - 12),
  _ => l10n.hourEvening(hour - 12),
};

/// 服事前 [N] 天: a choice row, as [ListRow] with [ListRow.selected], with
/// the number typed in it. Saved when typing is done; a number not from
/// [ReminderDays.first] to [ReminderDays.last], or none, goes back to
/// [days].
class _DaysBeforeRow extends StatefulWidget {
  const _DaysBeforeRow({required this.days, required this.selected, required this.onTap, required this.onDays});

  final int days;
  final bool selected;
  final VoidCallback onTap;

  /// Saves a new number; false when it could not be.
  final Future<bool> Function(int days) onDays;

  @override
  State<_DaysBeforeRow> createState() => _DaysBeforeRowState();
}

class _DaysBeforeRowState extends State<_DaysBeforeRow> {
  late final _text = TextEditingController(text: '${widget.days}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _done();
    });
  }

  @override
  void didUpdateWidget(_DaysBeforeRow old) {
    super.didUpdateWidget(old);
    if (widget.days != old.days && !_focus.hasFocus) _text.text = '${widget.days}';
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    final days = ReminderDays.parse(_text.text);
    if (days == null || days == widget.days) {
      _text.text = '${widget.days}';
      return;
    }
    if (!await widget.onDays(days) && mounted && !_focus.hasFocus) _text.text = '${widget.days}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final lead = l10n.notifReminderDaysLead;
    final row = InkWell(
      onTap: widget.onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: Space.minTap(Theme.of(context).platform)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
          child: Row(
            children: [
              if (lead.isNotEmpty) ...[
                Text(lead, style: AppText.body.copyWith(color: c.label)),
                const SizedBox(width: Space.s),
              ],
              SizedBox(
                width: 48,
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                  style: AppText.body.copyWith(color: c.label),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: Space.xs, vertical: 6),
                  ),
                  onTapOutside: (_) => _focus.unfocus(),
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(l10n.notifReminderDaysTrail(widget.days), style: AppText.body.copyWith(color: c.label)),
              ),
              if (widget.selected)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: Space.s),
                  child: Icon(Symbols.check_rounded, color: c.accent, size: 22, semanticLabel: l10n.selected),
                ),
            ],
          ),
        ),
      ),
    );
    return Semantics(selected: widget.selected, child: row);
  }
}

/// The hours reminders may come at ([ReminderHours]), [hour] ticked; the
/// one tapped closes it.
class _HourSheet extends StatelessWidget {
  const _HourSheet({required this.hour});

  final int hour;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetBar(title: l10n.notifReminderHour, actions: const []),
          Flexible(
            child: SingleChildScrollView(
              child: ListSection(
                children: [
                  for (var h = ReminderHours.first; h <= ReminderHours.last; h++)
                    ListRow(
                      title: hourLabel(l10n, h),
                      selected: h == hour,
                      onTap: () => Navigator.pop(context, h),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
