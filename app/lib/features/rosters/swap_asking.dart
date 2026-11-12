/// 找人代／交換 (#92): what a member does with one of their own duties, and
/// the page of a request they were asked.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart' show WarmUp;
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/swap.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import 'format.dart';
import '../../state/session.dart';

/// Whether I may ask for a cover or a swap of my [duty] on [roster]: a
/// service's day, today or later, with me on it.
bool asksForMyDuty(Roster roster, String duty, String? me, Day today) =>
    me != null && !roster.isEvent && !roster.day.isBefore(today) && isOnDuty(roster, duty, me);

/// My request still open for [duty] on [roster], if any.
SwapRequest? myOpenAsk(WidgetRef ref, Roster roster, String duty) =>
    (ref.read(myOpenSwapRequestsProvider).value ?? const <SwapRequest>[])
        .where((r) => r.rosterId == roster.id && r.duty == duty)
        .firstOrNull;

/// How my open request [r] stands: no one has it yet.
String myOpenAskLabel(L10n l10n, SwapRequest r) =>
    r.kind == SwapKind.cover ? l10n.swapPendingCover : l10n.swapPendingSwap(r.toName ?? '');

/// 請人代 for my [duty] on [roster], once I say so: asks, and says how
/// many were asked.
Future<void> askForCover(BuildContext context, WidgetRef ref, Roster roster, String duty) async {
  final l10n = L10n.of(context);
  final ok = await askChoice(
    context,
    title: l10n.swapAskCoverConfirm(DateFormat.MMMd().format(roster.day.midnight), duty),
    message: l10n.swapAskCoverSub,
    yes: l10n.swapAskCoverSend,
    no: l10n.cancel,
  );
  if (ok != true || !context.mounted) return;
  await _asking(context, () async {
    final telemetry = ref.read(telemetryProvider);
    final asked = await ref.churchData.askCover(roster, duty);
    telemetry.logEvent('swap_ask', {'kind': 'cover'});
    Haptics.success();
    if (context.mounted) showToast(context, L10n.of(context).swapAskedCover(asked));
  });
}

/// 收回 my open request [r].
Future<void> withdrawAsk(BuildContext context, WidgetRef ref, SwapRequest r) => _asking(context, () async {
  await ref.churchData.withdrawSwap(r.id);
  if (context.mounted) showToast(context, L10n.of(context).swapWithdrawn);
});

/// Runs [ask], saying why it failed.
Future<void> _asking(BuildContext context, Future<void> Function() ask) async {
  final l10n = L10n.of(context);
  try {
    await ask();
  } catch (e) {
    if (context.mounted) showToast(context, errorText(l10n, e));
  }
}

/// 找人代／交換 for my [duty] on [roster]: 請人代 or 和別週交換, or, with a
/// request of mine still open, how it stands and 收回.
Future<void> showMyDutyMenu(BuildContext context, WidgetRef ref, Roster roster, String duty) async {
  final l10n = L10n.of(context);
  final today = ref.read(todayProvider);
  final service = ref.read(servicesProvider).value?.byId(roster.type)?.name ?? '';
  final open = myOpenAsk(ref, roster, duty);
  // Asking waits on the backend; it starts while I choose.
  if (open == null) ref.read(backendProvider).warmUp(WarmUp.swapAsk);
  final choice = await showAppSheet<String>(
    context,
    builder: (context) => SafeArea(
      child: ListSection(
        header: '${dayLabel(l10n, roster.day, today)} · $service $duty',
        children: open != null
            ? [
                ListRow(
                  title: myOpenAskLabel(l10n, open),
                  chevron: false,
                  trailing: RowButton(label: l10n.swapWithdraw, onPressed: () => Navigator.pop(context, 'withdraw')),
                ),
              ]
            : [
                ListRow(
                  leading: const Icon(Symbols.front_hand_rounded),
                  title: l10n.swapAskCover,
                  subtitle: l10n.swapAskCoverSub,
                  onTap: () => Navigator.pop(context, 'cover'),
                ),
                ListRow(
                  leading: const Icon(Symbols.swap_vert_rounded),
                  title: l10n.swapAskSwap,
                  subtitle: l10n.swapAskSwapSub,
                  onTap: () => Navigator.pop(context, 'swap'),
                ),
              ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'withdraw':
      await withdrawAsk(context, ref, open!);
    case 'cover':
      await askForCover(context, ref, roster, duty);
    case 'swap':
      await _asking(context, () => _askSwap(context, ref, roster, duty));
  }
}

/// 和別週交換: whom, among those on [duty] on the service's later days,
/// then asked.
Future<void> _askSwap(BuildContext context, WidgetRef ref, Roster roster, String duty) async {
  final l10n = L10n.of(context);
  final today = ref.read(todayProvider);
  final me = ref.read(uidProvider)!;
  // One without an account could never answer.
  final noAccount = ref.read(noAccountProvider);
  final days = [
    for (final r in ref.read(savedRostersProvider).value ?? const <Roster>[])
      if (!r.isEvent && r.type == roster.type && r.day.isAfter(today) && r.id != roster.id && !isOnDuty(r, duty, me)) r,
  ]..sort((a, b) => a.day.compareTo(b.day));
  final people = [
    for (final r in days)
      if (r.duties.where((d) => d.role == duty).firstOrNull case final d?)
        for (final name in d.people)
          if (d.uids[name] case final uid? when uid != me && !noAccount.contains(uid) && !isOnDuty(roster, duty, uid))
            (day: r, name: name, uid: uid),
  ];
  final picked = await showAppSheet<({Roster day, String name, String uid})>(
    context,
    expand: people.length > 6,
    builder: (context) => SafeArea(
      child: people.isEmpty
          ? SizedBox(height: 200, child: EmptyState(message: l10n.swapNoDays))
          : ListView(
              shrinkWrap: true,
              children: [
                ListSection(
                  header: l10n.swapPickTitle(duty),
                  children: [
                    for (final p in people)
                      ListRow(
                        title: p.name,
                        value: dayLabel(l10n, p.day.day, today),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
              ],
            ),
    ),
  );
  if (picked == null || !context.mounted) return;
  await ref.churchData.askSwap(roster, duty, picked.day, picked.uid);
  ref.read(telemetryProvider).logEvent('swap_ask', {'kind': 'swap'});
  Haptics.success();
  if (context.mounted) showToast(context, l10n.swapAskedSwap(picked.name));
}

/// 我來／接受 ([yes]) or 不方便 for [r], asked of me. Taken, it goes to the
/// day I now serve on, with 復原.
Future<void> answerAsk(BuildContext context, WidgetRef ref, SwapRequest r, {required bool yes}) async {
  final l10n = L10n.of(context);
  final data = ref.churchData;
  final telemetry = ref.read(telemetryProvider);
  final router = GoRouter.of(context);
  final toasts = Navigator.of(context, rootNavigator: true).context;
  try {
    await data.answerSwap(r.id, yes: yes);
    telemetry.logEvent('swap_answer', {'kind': r.kind.name, 'result': yes ? 'yes' : 'no'});
    if (!yes) {
      if (context.mounted) showToast(context, l10n.swapDeclined);
      return;
    }
    Haptics.success();
    // To the day I now serve on: theirs, either way.
    router.go('/rosters/${r.serviceId}/${r.day.key}');
    if (toasts.mounted) {
      showToast(
        toasts,
        r.kind == SwapKind.cover ? l10n.swapTook : l10n.swapTraded,
        onUndo: () => data.undoSwap(r.id),
      );
    }
  } catch (e) {
    if (context.mounted) showToast(context, errorText(l10n, e));
  }
}

/// What still waits on me of [asks] (swapRequestsToMeProvider): not over,
/// and not one I said 不方便 to.
List<SwapRequest> waitingOnMe(List<SwapRequest> asks, String? me, Day today) => [
  for (final r in asks)
    if (me != null && !r.passed.contains(me) && !r.day.isBefore(today)) r,
];

/// A request I was asked (or asked myself), from its push or the 通知列表:
/// what it asks, and 我來／接受 or 不方便 while it is open.
class SwapRequestScreen extends ConsumerStatefulWidget {
  const SwapRequestScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<SwapRequestScreen> createState() => _SwapRequestScreenState();
}

class _SwapRequestScreenState extends ConsumerState<SwapRequestScreen> {
  bool _busy = false;

  Future<void> _answer(SwapRequest r, {required bool yes}) async {
    setState(() => _busy = true);
    try {
      await answerAsk(context, ref, r, yes: yes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final today = ref.watch(todayProvider);
    final me = ref.watch(uidProvider);
    final request = ref.watch(swapRequestProvider(widget.id));
    final r = request.value;
    final service = r == null ? '' : ref.watch(servicesProvider).value?.byId(r.serviceId)?.name ?? '';
    Widget body;
    if (request.hasError && r == null) {
      body = ErrorRetry(
        message: errorText(l10n, request.error!),
        onRetry: () => ref.invalidate(swapRequestProvider(widget.id)),
      );
    } else if (r == null) {
      body = request.isLoading ? const SizedBox.shrink() : EmptyState(message: l10n.errSwapClosed);
    } else {
      final cover = r.kind == SwapKind.cover;
      final answering = r.isOpen && me != null && r.canAnswer(me) && !r.passed.contains(me);
      final status = switch (r.status) {
        SwapStatus.open when me != null && r.passed.contains(me) => l10n.swapStatusDeclined,
        SwapStatus.open => null,
        SwapStatus.taken => r.taker == me ? l10n.swapStatusMine : l10n.swapStatusTaken(r.takerName ?? ''),
        SwapStatus.declined => l10n.swapStatusDeclined,
        SwapStatus.withdrawn => l10n.swapStatusWithdrawn(r.fromName),
        SwapStatus.voided => l10n.swapStatusVoided,
      };
      body = ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, 0),
            child: Text(
              cover ? l10n.swapCoverAsks(r.fromName) : l10n.swapSwapAsks(r.fromName),
              style: AppText.title2,
            ),
          ),
          ListSection(
            header: '$service ${r.duty}',
            children: cover
                ? [ListRow(title: dayLabel(l10n, r.day, today), chevron: false)]
                : [
                    ListRow(title: l10n.swapYouGet, value: dayLabel(l10n, r.day, today), chevron: false),
                    ListRow(
                      title: l10n.swapTheyGet(r.fromName),
                      value: dayLabel(l10n, r.toDay!, today),
                      chevron: false,
                    ),
                  ],
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: Text(status, style: AppText.body.copyWith(color: c.secondaryLabel)),
            ),
          if (answering)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(
                    label: cover ? l10n.swapTake : l10n.swapAccept,
                    busy: _busy,
                    onPressed: _busy ? null : () => _answer(r, yes: true),
                  ),
                  const SizedBox(height: Space.s),
                  SecondaryButton(
                    label: l10n.swapDecline,
                    expand: true,
                    onPressed: _busy ? null : () => _answer(r, yes: false),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.swapRequestTitle)),
      body: body,
    );
  }
}

/// On a day's page, first: my duties there, each with 我不行, or how my
/// request stands with 收回; then what others ask me for that day, a cover
/// with 我來 (#92). Nothing on an event's roster, or a day gone.
class DayAsks extends ConsumerStatefulWidget {
  const DayAsks({super.key, required this.roster});

  final Roster roster;

  @override
  ConsumerState<DayAsks> createState() => _DayAsksState();
}

class _DayAsksState extends ConsumerState<DayAsks> {
  /// Rows with a call on its way: one tap does it once.
  final _busy = <String>{};
  final _warm = <WarmUp>{};

  Future<void> _run(String key, Future<void> Function() call) async {
    setState(() => _busy.add(key));
    try {
      await call();
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  void _warmUp(WarmUp what) {
    if (_warm.add(what)) ref.read(backendProvider).warmUp(what);
  }

  /// The row's action, said at its end; grey while it runs.
  Widget _action(String label, String key) {
    final c = AppColors.of(context);
    return Text(label, style: AppText.body.copyWith(color: _busy.contains(key) ? c.tertiaryLabel : c.accent));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final roster = widget.roster;
    final me = ref.watch(uidProvider);
    final today = ref.watch(todayProvider);
    final mine = [
      for (final d in roster.duties)
        if (asksForMyDuty(roster, d.role, me, today)) d.role,
    ];
    final open = {
      for (final r in ref.watch(myOpenSwapRequestsProvider).value ?? const <SwapRequest>[])
        if (r.rosterId == roster.id) r.duty: r,
    };
    final asked = roster.isEvent
        ? const <SwapRequest>[]
        : [
            for (final r in waitingOnMe(ref.watch(swapRequestsToMeProvider).value ?? const [], me, today))
              if (r.rosterId == roster.id) r,
          ];
    // Asking and answering wait on the backend; they start while I look.
    if (mine.any((d) => !open.containsKey(d))) _warmUp(WarmUp.swapAsk);
    if (asked.isNotEmpty) _warmUp(WarmUp.swapAnswer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mine.isNotEmpty)
          ListSection(
            header: l10n.myDutyHere,
            children: [
              for (final duty in mine)
                if (open[duty] case final r?)
                  ListRow(
                    title: duty,
                    subtitle: myOpenAskLabel(l10n, r),
                    chevron: false,
                    trailing: _action(l10n.swapWithdraw, duty),
                    onTap: _busy.contains(duty) ? null : () => _run(duty, () => withdrawAsk(context, ref, r)),
                  )
                else
                  ListRow(
                    title: duty,
                    chevron: false,
                    trailing: _action(l10n.swapAskCover, duty),
                    onTap: _busy.contains(duty)
                        ? null
                        : () => _run(duty, () => askForCover(context, ref, roster, duty)),
                  ),
            ],
          ),
        if (asked.isNotEmpty)
          ListSection(
            header: l10n.swapWaitingForYou,
            children: [
              for (final r in asked)
                if (r.kind == SwapKind.cover)
                  ListRow(
                    title: r.duty,
                    subtitle: l10n.swapCoverAsks(r.fromName),
                    chevron: false,
                    trailing: _action(l10n.swapTake, r.id),
                    onTap: _busy.contains(r.id) ? null : () => _run(r.id, () => answerAsk(context, ref, r, yes: true)),
                  )
                else
                  ListRow(
                    title: r.duty,
                    subtitle: l10n.swapSwapAsks(r.fromName),
                    onTap: () => context.push('/rosters/request/${r.id}'),
                  ),
            ],
          ),
      ],
    );
  }
}
