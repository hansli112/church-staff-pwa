import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/perf.dart';
import '../../core/design/tokens.dart';
import '../../domain/getting_started.dart';
import '../../domain/models.dart';
import '../../domain/swap.dart';
import '../../l10n/app_localizations.dart';
import '../../state/calendar.dart';
import '../../state/providers.dart';
import '../church/add_to_home.dart';
import '../church/church_logo.dart';
import '../church/claims.dart';
import '../calendar/event_sheet.dart';
import '../me/attendance.dart';
import '../me/no_account_picker.dart';
import '../common/errors.dart';
import '../me/turn_on_notifications.dart';
import '../common/calendar_read_notice.dart';
import 'church_link_card.dart';
import 'getting_started.dart';
import 'notification_list_screen.dart';
import '../rosters/format.dart';
import '../rosters/day_block.dart';
import '../rosters/event_roster_screen.dart';
import '../rosters/rosters_screen.dart';
import '../rosters/swap_asking.dart';

/// For admins: how many members are a 同工 of no service yet, so their
/// 服事表 tab is empty.
final _waitingForZoneProvider = Provider.autoDispose<int>((ref) {
  if (!(ref.watch(meProvider).value?.isAdmin ?? false)) return 0;
  final members = ref.watch(membersProvider).value ?? const [];
  final enabled = ref.watch(servicesProvider).value?.enabled ?? const [];
  return members.where((m) => m.waitsForZone(enabled)).length;
});

/// 首頁: the days I serve next. That is what most people open the app for.
/// Above them, 加入主畫面 on a phone's browser, 開啟通知 elsewhere until
/// they are on, the church link when the admin has set one, 開始使用 for
/// a 身分 with something still to start, and for admins the members still
/// a 同工 of no service.
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
          final gettingStarted = ref.watch(gettingStartedProvider);
          ref.watch(countStartsProvider);
          // 開始使用 putting 同工 in a service says the same.
          final waiting =
              gettingStarted.any(
                (g) => g.steps.any((s) => s.step == StartStep.addStaff && s.state != StartState.done),
              )
              ? 0
              : ref.watch(_waitingForZoneProvider);
          // Just joined, in no service yet: nothing of theirs to show until
          // an admin puts them in one, so the page says that instead.
          final welcome = ref.watch(
            meProvider.select(
              (m) => m.value != null && !m.value!.isAdmin && m.value!.waitsForZone(services?.enabled ?? const []),
            ),
          );
          final addToHome = AddToHomeCard.shown(ref);
          final notifications = TurnOnNotificationsCard.shown(ref);
          final attendance = AttendanceDueCard.shown(ref);
          // 找人代／交換 asking me (#92): first among what is mine to do.
          final asks = waitingOnMe(
            ref.watch(swapRequestsToMeProvider).value ?? const [],
            ref.watch(uidProvider),
            today,
          );
          if (list.isEmpty &&
              !welcome &&
              asks.isEmpty &&
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
              if (welcome) WelcomeWaitCard(churchName: church?.name ?? ''),
              if (addToHome) const AddToHomeCard(),
              if (notifications) const TurnOnNotificationsCard(),
              // 填寫人數 (#85): what a lead is asked, first among their own things.
              if (asks.isNotEmpty)
                ListSection(
                  header: l10n.swapWaitingForYou,
                  children: [
                    for (final r in asks)
                      ListRow(
                        leading: dayBlock(r.day, today),
                        title: r.kind == SwapKind.cover
                            ? l10n.swapCoverAsks(r.fromName)
                            : l10n.swapSwapAsks(r.fromName),
                        subtitle: [
                          dayBesideBlock(l10n, r.day, today),
                          '${services?.byId(r.serviceId)?.name ?? ''} ${r.duty}'.trim(),
                        ].where((t) => t.isNotEmpty).join(' · '),
                        onTap: () => context.push('/rosters/request/${r.id}'),
                      ),
                  ],
                ),
              if (attendance) const AttendanceDueCard(),
              for (final start in gettingStarted) GettingStartedSection(start),
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
              if (list.isEmpty && welcome)
                const SizedBox.shrink()
              else if (list.isEmpty)
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
                    for (final (event, underway) in [
                      for (final event in activities.take(3)) (event, event.day.isBefore(today)),
                    ])
                      ListRow(
                        // One already under way is on today, without the time it
                        // started: that would read as today's.
                        leading: dayBlock(underway ? today : event.day, today),
                        title: event.title,
                        subtitle: [
                          dayBesideBlock(l10n, underway ? today : event.day, today),
                          if (!event.allDay && !underway) DateFormat.Hm().format(event.start),
                        ].join(' · '),
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

/// 「歡迎加入〈恩典堂〉」 for someone in no service yet: an admin puts them
/// in one, and they may ask for it. Under it, 服事表上已經有你了嗎？ to say
/// which of the 同工 without an account they are, or, said, that an admin
/// is to confirm it.
class WelcomeWaitCard extends ConsumerWidget {
  const WelcomeWaitCard({super.key, required this.churchName});

  final String churchName;

  Future<void> _ask(BuildContext context, WidgetRef ref, List<ClaimCandidate> candidates) async {
    final me = ref.read(meProvider).value;
    final picked = await showAppSheet<ClaimCandidate>(
      context,
      expand: candidates.length > 6,
      builder: (context) => NoAccountPicker<ClaimCandidate>(
        title: L10n.of(context).claimAskPick,
        name: me?.name ?? '',
        people: candidates,
        nameOf: (c) => c.name,
        details: (c) => candidateDetails(L10n.of(context), c),
        searched: (c) => [c.name],
      ),
    );
    if (picked == null || !context.mounted) return;
    final l10n = L10n.of(context);
    final details = candidateDetails(l10n, picked);
    final ok = await askChoice(
      context,
      title: l10n.claimAskTitle(picked.name),
      message: [if (details.isNotEmpty) details, l10n.claimAskBody(picked.name)].join('\n\n'),
      yes: l10n.claimAskSend,
      no: l10n.cancel,
    );
    if (ok != true || !context.mounted) return;
    await _send(context, ref, picked.pendingId);
  }

  Future<void> _send(BuildContext context, WidgetRef ref, String? pendingId) async {
    try {
      await ref.churchData.askClaim(pendingId);
      if (pendingId != null) Haptics.success();
    } catch (e) {
      if (context.mounted) showToast(context, errorText(L10n.of(context), e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final ask = ref.watch(myClaimAskProvider).value;
    final candidates = ask == null ? ref.watch(claimCandidatesProvider).value ?? const [] : const <ClaimCandidate>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.m),
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BalancedText(l10n.welcomeWaitTitle(churchName), textAlign: TextAlign.start, style: AppText.headline),
              const SizedBox(height: Space.s),
              BalancedText(
                ask == null ? l10n.welcomeWaitBody : l10n.claimAskWaiting(ask.pendingName),
                textAlign: TextAlign.start,
                style: AppText.subheadline.copyWith(color: c.secondaryLabel),
              ),
              if (ask != null) ...[
                const SizedBox(height: Space.m),
                SecondaryButton(label: l10n.cancel, expand: true, onPressed: () => _send(context, ref, null)),
              ] else if (candidates.isNotEmpty) ...[
                const SizedBox(height: Space.m),
                SecondaryButton(
                  label: l10n.claimAskEntry,
                  expand: true,
                  onPressed: () => _ask(context, ref, candidates),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
