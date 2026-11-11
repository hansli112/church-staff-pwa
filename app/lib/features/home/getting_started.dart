import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/getting_started.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../common/labels.dart';
import '../me/groups_screen.dart';

String _deviceKey(Ref ref, String what) => '${what}_${ref.read(uidProvider)}_${ref.read(currentChurchIdProvider)}';

/// 開始使用 put away on this device (不再顯示), by 身分, per account and
/// church: one given later shows its own.
class _HiddenStarts extends Notifier<Set<String>> {
  String get _key => _deviceKey(ref, 'getting_started_hidden');

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

/// Whether the services were opened from 開始使用 on this device, per
/// account and church: what a church starts with may already be right, so
/// having looked is what sets them.
class _ServicesSeen extends Notifier<bool> {
  String get _key => _deviceKey(ref, 'getting_started_services_seen');

  @override
  bool build() {
    ref.watch(uidProvider);
    ref.watch(currentChurchIdProvider);
    return ref.read(prefsProvider).getBool(_key) ?? false;
  }

  void see() {
    if (state) return;
    state = true;
    ref.read(prefsProvider).setBool(_key, true);
  }
}

final _servicesSeenProvider = NotifierProvider<_ServicesSeen, bool>(_ServicesSeen.new);

/// The church's invites, for whether one is out; none for anyone but an
/// admin, who may not read them. Kept, unlike the invites page's: one
/// dropped while home is hidden would come back during a build.
final _invitesProvider = StreamProvider<List<Invite>>(
  (ref) => ref.watch(meProvider.select((m) => m.value?.isAdmin ?? false))
      ? openChurch(ref).invites()
      : Stream.value(const []),
);

/// What my 身分 still have to start (gettingStarted), those put away too;
/// null until everything it is worked out from has
/// loaded. While anything is left it looks at the past weeks' rosters too
/// (read only then), so a church between seasons is not new again.
List<GettingStarted>? _starts(Ref ref) {
  final me = ref.watch(meProvider).value;
  if (me == null) return null;
  if (me.identities.isEmpty) return const [];
  final members = ref.watch(membersProvider).value;
  final pending = ref.watch(pendingMembersProvider).value;
  final services = ref.watch(servicesProvider).value;
  final ministries = ref.watch(ministriesProvider).value;
  final smallGroups = ref.watch(smallGroupsProvider).value;
  final rosters = ref.watch(savedRostersProvider).value;
  final settings = ref.watch(churchProvider).value;
  if (members == null ||
      pending == null ||
      services == null ||
      ministries == null ||
      smallGroups == null ||
      rosters == null ||
      settings == null) {
    return null;
  }
  final invites = ref.watch(_invitesProvider).value;
  final now = ref.read(clockProvider)();
  final invited = invites?.any((i) => i.usableAt(now)) ?? false;
  final servicesSeen = ref.watch(_servicesSeenProvider);
  List<GettingStarted> left(Iterable<Roster> rosters) => gettingStarted(
    me: me,
    members: members,
    pending: pending,
    services: services,
    ministries: ministries,
    smallGroups: smallGroups,
    rosters: rosters,
    attendanceOn: settings.attendanceSince != null,
    invited: invited,
    servicesSeen: servicesSeen,
    hasLogo: settings.hasLogo,
  );
  var starts = left(rosters);
  if (starts.isNotEmpty) {
    final past = ref.watch(recentRostersProvider);
    // A failed read leaves the steps as today on has them.
    if (past.isLoading) return null;
    starts = left([...rosters, ...?past.value]);
  }
  return starts;
}

/// What my 身分 still have to start, less those put away; nothing until
/// it has all loaded. Worked out here, not from [_startsProvider]: a
/// provider between them would be refreshed while home is being rebuilt.
final gettingStartedProvider = Provider.autoDispose<List<GettingStarted>>((ref) {
  final starts = _starts(ref);
  if (starts == null) return const [];
  final hidden = ref.watch(_hiddenStartsProvider);
  return [
    for (final g in starts)
      if (!hidden.contains(_keyOf(g.identity))) g,
  ];
});

final _startsProvider = Provider.autoDispose<List<GettingStarted>?>(_starts);

/// Counts each 開始使用 step as it gets done, put away or not, and the
/// whole once nothing is left (GA4 `tutorial_step`, `tutorial_complete`):
/// only what changes while the church is open here, never what was done
/// before. Home watches it.
final countStartsProvider = Provider.autoDispose<void>((ref) {
  var church = ref.read(currentChurchIdProvider);
  ref.listen(_startsProvider, (before, now) {
    final was = church;
    church = ref.read(currentChurchIdProvider);
    if (before == null || now == null || church != was) return;
    final after = {for (final g in now) _keyOf(g.identity): g};
    final had = {for (final g in before) _keyOf(g.identity)};
    // A 身分 just given brings steps of its own and may take others' away:
    // nothing was done.
    if (after.keys.any((k) => !had.contains(k))) return;
    final telemetry = ref.read(telemetryProvider);
    for (final g in before) {
      // Gone: everything of it is done.
      final left = after[_keyOf(g.identity)];
      for (final s in g.steps) {
        if (s.state == StartState.done) continue;
        final done =
            left == null || left.steps.any((t) => t.step == s.step && t.group == s.group && t.state == StartState.done);
        if (done) telemetry.logEvent('tutorial_step', {'step': s.step.name});
      }
    }
    if (before.isNotEmpty && now.isEmpty) telemetry.logEvent('tutorial_complete');
  });
});

/// The page [s] opens, which may be three levels down under 設定; null for
/// the 服事表 tab.
String? _pageOf(GettingStartedStep s) => switch ((s.step, s.group)) {
  (StartStep.services, _) || (StartStep.addStaff || StartStep.smallGroups || StartStep.meets, null) => '/me/groups',
  (StartStep.invite, _) => '/me/invites',
  (StartStep.logo, _) => '/me/church',
  (StartStep.addStaff, final group?) => groupStaffPage(group),
  (StartStep.smallGroups || StartStep.meets, final group?) => groupPage(group),
  (StartStep.arrange, _) => null,
  (StartStep.planWeeks, final group) => '/rosters/plan/${group?.id}',
};

/// Opens [s]'s page, saying which step it is for, so the page can offer
/// the one after it; [replace] the page of the one before. Opening the
/// services is what sets them.
void openStartStep(BuildContext context, WidgetRef ref, GettingStartedStep s, {bool replace = false}) {
  if (s.step == StartStep.services) ref.read(_servicesSeenProvider.notifier).see();
  final page = _pageOf(s);
  if (page == null) return context.go('/rosters');
  final location = Uri(path: page, queryParameters: {'start': s.step.name}).toString();
  replace ? context.pushReplacement(location) : context.push(location);
}

/// The names of the groups a step is about, as 開始使用 says them.
String Function(ChurchGroup?) _groupNames(WidgetRef ref) {
  final services = ref.watch(servicesProvider).value;
  final ministries = ref.watch(ministriesProvider).value;
  final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
  // Not churchGroupsProvider: watched here, it would rebuild during a
  // church switch's build (onboarding_test).
  return (group) => switch (group) {
    ServiceGroup(:final id) => services?.byId(id)?.name ?? id,
    MinistryGroup(:final id) => ministries?.nameOf(id, services) ?? id,
    SmallGroup(:final id) => smallGroupName(smallGroups, id),
    null => '',
  };
}

String _title(L10n l10n, GettingStartedStep s, String Function(ChurchGroup?) name) => switch (s.step) {
  StartStep.services => l10n.gettingStartedServices,
  StartStep.logo => l10n.uploadLogo,
  StartStep.invite => l10n.inviteMembers,
  StartStep.addStaff when s.group == null => l10n.gettingStartedAddStaffAny,
  StartStep.addStaff => l10n.gettingStartedAddStaff(name(s.group)),
  StartStep.smallGroups => l10n.gettingStartedSmallGroups,
  StartStep.arrange => l10n.gettingStartedArrange,
  StartStep.planWeeks => l10n.gettingStartedPlan(name(s.group)),
  StartStep.meets => l10n.gettingStartedMeets(name(s.group)),
};

String? _subtitle(L10n l10n, GettingStartedStep s) => switch ((s.step, s.state)) {
  (_, StartState.done) => null,
  (_, StartState.locked) => l10n.gettingStartedAfterJoin,
  (StartStep.services, _) => l10n.gettingStartedServicesBody,
  (StartStep.invite, StartState.waiting) => l10n.gettingStartedInviteWaiting,
  (StartStep.invite, _) => l10n.gettingStartedInviteBody,
  (StartStep.smallGroups, _) => l10n.gettingStartedSmallGroupsBody,
  (StartStep.logo, _) => l10n.gettingStartedLogoBody,
  (StartStep.arrange || StartStep.planWeeks, _) => l10n.gettingStartedArrangeBody,
  _ => null,
};

/// 開始使用 for one 身分: its steps in order, numbered, the next one
/// filled in and the ones done checked. A 管理員's is plain 開始使用;
/// another names the 身分, with what it may do below.
class GettingStartedSection extends ConsumerWidget {
  const GettingStartedSection(this.start, {super.key});

  final GettingStarted start;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final services = ref.watch(servicesProvider).value;
    final ministries = ref.watch(ministriesProvider).value;
    final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
    final name = _groupNames(ref);
    final identity = start.identity;
    final admin = identity.makesAdmin;
    final next = start.next;
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
        for (final (i, s) in start.steps.indexed)
          ListRow(
            title: _title(l10n, s, name),
            subtitle: _subtitle(l10n, s),
            leading: _StepMark(i + 1, s.state, isNext: s == next),
            // Done, or nothing to do there yet.
            onTap: s.state == StartState.done || s.state == StartState.locked
                ? null
                : () => openStartStep(context, ref, s),
          ),
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

/// A step's number, filled in for the next one; a check once done.
class _StepMark extends StatelessWidget {
  const _StepMark(this.number, this.state, {required this.isNext});

  final int number;
  final StartState state;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (state == StartState.done) {
      return Icon(
        Symbols.check_circle_rounded,
        fill: 1,
        color: c.accent,
        semanticLabel: L10n.of(context).gettingStartedDone,
      );
    }
    final color = state == StartState.locked ? c.tertiaryLabel : c.secondaryLabel;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isNext ? c.accent : null,
        border: isNext ? null : Border.all(color: color, width: 1.5),
      ),
      child: Text(
        '$number',
        textScaler: TextScaler.noScaling,
        style: AppText.caption.copyWith(
          color: isNext ? c.onAccent : color,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

/// [child], a page opened from 開始使用 for [step], with the step after it
/// at the bottom once this one is done (or waits on others), so one goes on
/// without going back home.
class StartNext extends ConsumerWidget {
  const StartNext({super.key, required this.step, required this.page, required this.child});

  final StartStep step;

  /// Where this page is, telling apart the steps of one kind.
  final String page;
  final Widget child;

  /// The step after this page's, once this one needs nothing more here.
  GettingStartedStep? _after(List<GettingStarted> starts) {
    for (final start in starts) {
      for (final s in start.steps) {
        if (s.step != step || Uri(path: _pageOf(s)).path != page) continue;
        if (s.state != StartState.done && s.state != StartState.waiting) return null;
        return start.after(s);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final after = _after(ref.watch(gettingStartedProvider));
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final l10n = L10n.of(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: after == null || typing
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                child: PrimaryButton(
                  label: l10n.gettingStartedNext(_title(l10n, after, _groupNames(ref))),
                  onPressed: () => openStartStep(context, ref, after, replace: true),
                ),
              ),
            ),
    );
  }
}
