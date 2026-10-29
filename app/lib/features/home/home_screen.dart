import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/perf.dart';
import '../../core/design/tokens.dart';
import '../../domain/getting_started.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/calendar.dart';
import '../../state/providers.dart';
import '../church/add_to_home.dart';
import '../church/church_logo.dart';
import '../church/claims.dart';
import '../calendar/event_sheet.dart';
import '../me/attendance.dart';
import '../me/groups_screen.dart';
import '../me/turn_on_notifications.dart';
import '../common/calendar_read_notice.dart';
import '../common/labels.dart';
import 'church_link_card.dart';
import 'notification_list_screen.dart';
import '../rosters/format.dart';
import '../rosters/day_block.dart';
import '../rosters/event_roster_screen.dart';
import '../rosters/rosters_screen.dart';

/// 開始使用 put away on this device (不再顯示), by 身分, per account and
/// church: one given later shows its own.
class _HiddenStarts extends Notifier<Set<String>> {
  String get _key => 'getting_started_hidden_${ref.read(uidProvider)}_${ref.read(currentChurchIdProvider)}';

  @override
  Set<String> build() {
    ref.watch(uidProvider);
    ref.watch(currentChurchIdProvider);
    return (ref.read(prefsProvider).getStringList(_key) ?? const []).toSet();
  }

  void hide(Identity i) {
    state = {...state, _keyOf(i)};
    ref.read(prefsProvider).setStringList(_key, state.toList());
  }
}

String _keyOf(Identity i) => jsonEncode(i.toJson());

final _hiddenStartsProvider = NotifierProvider<_HiddenStarts, Set<String>>(_HiddenStarts.new);

/// What my 身分 still have to start (gettingStarted), less those put away;
/// nothing until everything it is worked out from has loaded. A step left
/// for want of a roster with someone on it looks at the past weeks too
/// (read only then), so a church between seasons is not new again.
final _gettingStartedProvider = Provider.autoDispose<List<GettingStarted>>((ref) {
  final me = ref.watch(meProvider).value;
  if (me == null || me.identities.isEmpty) return const [];
  final members = ref.watch(membersProvider).value;
  final pending = ref.watch(pendingMembersProvider).value;
  final services = ref.watch(servicesProvider).value;
  final ministries = ref.watch(ministriesProvider).value;
  final smallGroups = ref.watch(smallGroupsProvider).value;
  final rosters = ref.watch(savedRostersProvider).value;
  final church = ref.watch(churchProvider).value;
  if (members == null ||
      pending == null ||
      services == null ||
      ministries == null ||
      smallGroups == null ||
      rosters == null ||
      church == null) {
    return const [];
  }
  List<GettingStarted> left(Iterable<Roster> rosters) => gettingStarted(
    me: me,
    members: members,
    pending: pending.length,
    services: services,
    ministries: ministries,
    smallGroups: smallGroups,
    rosters: rosters,
    attendanceOn: church.attendanceSince != null,
  );
  var starts = left(rosters);
  if (starts.any((g) => g.steps.any((s) => s.step.wantsArranging))) {
    final past = ref.watch(recentRostersProvider);
    // A failed read leaves the steps as today on has them.
    if (past.isLoading) return const [];
    starts = left([...rosters, ...?past.value]);
  }
  final hidden = ref.watch(_hiddenStartsProvider);
  return [
    for (final g in starts)
      if (!hidden.contains(_keyOf(g.identity))) g,
  ];
});

/// For admins: how many members are in no 牧區 yet, so their 服事表 tab
/// is empty.
final _waitingForZoneProvider = Provider.autoDispose<int>((ref) {
  if (!(ref.watch(meProvider).value?.isAdmin ?? false)) return 0;
  final members = ref.watch(membersProvider).value ?? const [];
  final enabled = ref.watch(servicesProvider).value?.enabled ?? const [];
  return members.where((m) => m.waitsForZone(enabled)).length;
});

/// 開始使用 for one 身分: what is left to do first, each step opening
/// its page, which may be three levels down under 設定. A 管理員's is
/// plain 開始使用; another names the 身分, with what it may do below.
class _GettingStarted extends ConsumerWidget {
  const _GettingStarted(this.start);

  final GettingStarted start;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final services = ref.watch(servicesProvider).value;
    final ministries = ref.watch(ministriesProvider).value;
    final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
    final identity = start.identity;
    final admin = identity.makesAdmin;
    // Not churchGroupsProvider: watched here, it would rebuild during a
    // church switch's build (onboarding_test).
    String name(ChurchGroup? group) => switch (group) {
      ServiceGroup(:final id) => services?.byId(id)?.name ?? id,
      MinistryGroup(:final id) => ministries?.byId(id)?.name ?? id,
      SmallGroup(:final id) => smallGroupName(smallGroups, id),
      null => '',
    };
    ListRow row(GettingStartedStep s) {
      final group = s.group;
      return switch (s.step) {
        StartStep.services => ListRow(
          title: l10n.gettingStartedServices,
          subtitle: l10n.gettingStartedServicesBody,
          leading: const Icon(Symbols.tune_rounded),
          onTap: () => context.push('/me/services'),
        ),
        StartStep.invite => ListRow(
          title: l10n.inviteMembers,
          subtitle: l10n.gettingStartedInviteBody,
          leading: const Icon(Symbols.person_add_alt_rounded),
          onTap: () => context.push('/me/invites'),
        ),
        StartStep.arrange => ListRow(
          title: l10n.gettingStartedArrange,
          subtitle: l10n.gettingStartedArrangeBody,
          leading: const Icon(Symbols.edit_calendar_rounded),
          onTap: () => context.go('/rosters'),
        ),
        StartStep.addStaff => ListRow(
          title: l10n.gettingStartedAddStaff(name(group)),
          leading: const Icon(Symbols.group_add_rounded),
          onTap: () => context.push(groupPage(group!)),
        ),
        StartStep.planWeeks => ListRow(
          title: l10n.gettingStartedPlan(name(group)),
          subtitle: l10n.gettingStartedArrangeBody,
          leading: const Icon(Symbols.edit_calendar_rounded),
          onTap: () => context.push('/rosters/plan/${group!.id}'),
        ),
        StartStep.meets => ListRow(
          title: l10n.gettingStartedMeets(name(group)),
          leading: const Icon(Symbols.schedule_rounded),
          onTap: () => context.push(groupPage(group!)),
        ),
      };
    }

    return ListSection(
      header: admin
          ? l10n.gettingStarted
          : l10n.gettingStartedAs(
              identityLabel(l10n, identity, services: services, ministries: ministries, smallGroups: smallGroups),
            ),
      footer: admin
          ? null
          : identityCan(l10n, identity, services: services, ministries: ministries, smallGroups: smallGroups),
      children: [
        for (final s in start.steps) row(s),
        ListRow(
          title: l10n.gettingStartedHide,
          leading: const Icon(Symbols.close_rounded),
          chevron: false,
          onTap: () => ref.read(_hiddenStartsProvider.notifier).hide(identity),
        ),
      ],
    );
  }
}

/// 首頁: the days I serve next. That is what most people open the app for.
/// Above them, 加入主畫面 on a phone's browser, 開啟通知 elsewhere until
/// they are on, the church link when the admin has set one, 開始使用 for
/// a 身分 with something still to start, and for admins the members still
/// in no 牧區.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final church = ref.watch(churchProvider).value;
    final mine = ref.watch(myServicesProvider);
    final services = ref.watch(servicesProvider).value;
    final today = ref.watch(todayProvider);
    final link = ref.watch(shownChurchLinkProvider);
    // A sourced link with nothing for today says so; it never falls back.
    final sourceMissing =
        link == null &&
        ref.watch(churchLinkProvider).value?.source != null &&
        !ref.watch(linkContentProvider).isLoading;
    final calendarReady = ref.watch(calendarSettingsProvider).value?.ready ?? false;
    final activityMonths = calendarReady
        ? [monthKey(DateTime.utc(today.year, today.month)), monthKey(DateTime.utc(today.year, today.month + 1))]
        : const <String>[];
    final activityStates = [for (final month in activityMonths) ref.watch(calendarEventsProvider(month))];
    final activityReadStatus = {
      for (final month in activityMonths) month: ref.watch(calendarReadStatusProvider(month)),
    };
    final now = ref.watch(churchTimeZoneProvider).clock(ref.watch(clockProvider)());
    final activities = {
      for (final state in activityStates)
        if (!state.hasError)
          for (final event in state.value ?? const <CalendarEvent>[]) event.id ?? event: event,
    }.values.where((event) => event.end.isAfter(now)).toList()..sort((a, b) => a.start.compareTo(b.start));
    final activityError = activityStates.any((state) => state.hasError);
    final activityLoading = activityStates.any((state) => state.isLoading);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: Space.m,
        title: church == null ? null : ChurchTitle(church: church),
        actions: [if (church != null) const NotificationBell()],
      ),
      body: mine.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (_, _) => ErrorRetry(
          message: l10n.loadFailed,
          onRetry: () => ref.invalidate(savedRostersProvider),
        ),
        data: (list) {
          perfMark('home-visible');
          final claims = ref.watch(pendingClaimsProvider).value ?? const [];
          final gettingStarted = ref.watch(_gettingStartedProvider);
          final waiting = ref.watch(_waitingForZoneProvider);
          final addToHome = AddToHomeCard.shown(ref);
          final notifications = TurnOnNotificationsCard.shown(ref);
          final attendance = AttendanceDueCard.shown(ref);
          if (list.isEmpty &&
              !attendance &&
              link == null &&
              !sourceMissing &&
              claims.isEmpty &&
              gettingStarted.isEmpty &&
              waiting == 0 &&
              !addToHome &&
              !notifications &&
              activities.isEmpty &&
              !activityError &&
              !activityLoading) {
            return EmptyState(
              icon: Symbols.event_available_rounded,
              message: l10n.noUpcomingServices,
              actionLabel: l10n.viewRosters,
              onAction: () => context.go('/rosters'),
            );
          }
          return ListView(
            children: [
              const PendingClaimsCard(),
              if (addToHome) const AddToHomeCard(),
              if (notifications) const TurnOnNotificationsCard(),
              // 填寫人數 (#85): what a lead is asked, first among their own things.
              if (attendance) const AttendanceDueCard(),
              for (final start in gettingStarted) _GettingStarted(start),
              if (waiting > 0)
                ListSection(
                  children: [
                    ListRow(
                      title: l10n.waitingForZone(waiting),
                      leading: const Icon(Symbols.manage_accounts_rounded),
                      onTap: () => context.push('/me/members'),
                    ),
                  ],
                ),
              if (link != null) ChurchLinkCard(title: link.title, body: link.body, url: link.url),
              if (sourceMissing) ChurchLinkSourceStatus(key: ValueKey(ref.watch(churchDataProvider)?.churchId)),
              if (list.isEmpty)
                EmptyState(
                  icon: Symbols.event_available_rounded,
                  message: l10n.noUpcomingServices,
                  actionLabel: l10n.viewRosters,
                  onAction: () => context.go('/rosters'),
                )
              else
                ListSection(
                  header: l10n.myServicesTitle,
                  children: [
                    for (final s in list.take(20))
                      ListRow(
                        leading: dayBlock(s.roster.day, today),
                        title: s.roster.forEvent?.title ?? services?.byId(s.roster.type)?.name ?? '',
                        subtitle: [
                          // An event over several days says both; the block shows the first.
                          s.roster.isEvent && s.roster.lastDay != s.roster.day
                              ? eventDaysLabel(l10n, s.roster, today)
                              : dayBesideBlock(l10n, s.roster.day, today),
                          s.duties.join(l10n.listSeparator),
                        ].where((t) => t.isNotEmpty).join(' · '),
                        onTap: () {
                          if (s.roster.forEvent case final e?) {
                            context.push('/rosters/event/${e.eventId}');
                            return;
                          }
                          ref.read(selectedServiceProvider.notifier).select(s.roster.type);
                          context.push(
                            '/rosters/${s.roster.type}/${s.roster.day.key}',
                          );
                        },
                      ),
                  ],
                ),
              if (activities.isNotEmpty || activityError || activityLoading)
                ListSection(
                  header: l10n.homeUpcomingEvents,
                  children: [
                    for (final entry in activityReadStatus.entries)
                      if (entry.value.cached && activities.take(3).any((event) => event.months.contains(entry.key)))
                        CalendarReadNotice(status: entry.value, month: entry.key),
                    for (final event in activities.take(3))
                      ListRow(
                        // One already under way is on today.
                        leading: dayBlock(event.day.isBefore(today) ? today : event.day, today),
                        title: event.title,
                        subtitle: dayBesideBlock(l10n, event.day.isBefore(today) ? today : event.day, today),
                        // A new one opens once saved, with its roster.
                        onTap: event.id == null ? null : () => showEventDetail(context, event),
                      ),
                    if (activityError)
                      ErrorRetry(
                        message: l10n.loadFailed,
                        onRetry: () {
                          for (final month in activityMonths) {
                            ref.invalidate(calendarEventsProvider(month));
                          }
                        },
                      )
                    else if (activityLoading && activities.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(Space.m),
                        child: Center(child: CircularProgressIndicator.adaptive()),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
