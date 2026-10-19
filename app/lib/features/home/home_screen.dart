import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/perf.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/calendar.dart';
import '../../state/providers.dart';
import '../church/add_to_home.dart';
import '../church/church_logo.dart';
import '../church/claims.dart';
import '../calendar/event_sheet.dart';
import '../me/turn_on_notifications.dart';
import '../common/calendar_read_notice.dart';
import 'church_link_card.dart';
import '../rosters/format.dart';
import '../rosters/day_block.dart';
import '../rosters/event_roster_screen.dart';
import '../rosters/rosters_screen.dart';

/// Whether to show 開始使用: I am an admin and still the church's only
/// member (just made it, nobody invited yet).
final _gettingStartedProvider = Provider.autoDispose<bool>((ref) {
  if (!(ref.watch(meProvider).value?.isAdmin ?? false)) return false;
  final members = ref.watch(membersProvider).value;
  final pending = ref.watch(pendingMembersProvider).value;
  return members != null && members.length <= 1 && pending != null && pending.isEmpty;
});

/// For admins: how many members are in no 牧區 yet, so their 服事表 tab
/// is empty.
final _waitingForZoneProvider = Provider.autoDispose<int>((ref) {
  if (!(ref.watch(meProvider).value?.isAdmin ?? false)) return 0;
  final members = ref.watch(membersProvider).value ?? const [];
  final enabled = ref.watch(servicesProvider).value?.enabled ?? const [];
  return members.where((m) => m.waitsForZone(enabled)).length;
});

/// What to do first in a new church, where the screens for it are three
/// levels down under 我的. Shown while [_gettingStartedProvider] holds.
class _GettingStarted extends StatelessWidget {
  const _GettingStarted();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListSection(
      header: l10n.gettingStarted,
      children: [
        ListRow(
          title: l10n.inviteMembers,
          subtitle: l10n.gettingStartedInviteBody,
          leading: const Icon(Symbols.person_add_alt_rounded),
          onTap: () => context.push('/me/invites'),
        ),
        ListRow(
          title: l10n.gettingStartedServices,
          subtitle: l10n.gettingStartedServicesBody,
          leading: const Icon(Symbols.tune_rounded),
          onTap: () => context.push('/me/services'),
        ),
      ],
    );
  }
}

/// 首頁: the days I serve next. That is what most people open the app for.
/// Above them, 加入主畫面 on a phone's browser, 開啟通知 elsewhere until
/// they are on, the church link when the admin has set one, 開始使用 for
/// the admin of a church nobody else has joined yet, and for admins the
/// members still in no 牧區.
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
          if (list.isEmpty &&
              link == null &&
              !sourceMissing &&
              claims.isEmpty &&
              !gettingStarted &&
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
              if (gettingStarted) const _GettingStarted(),
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
