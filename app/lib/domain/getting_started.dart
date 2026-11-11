import 'package:flutter/foundation.dart';

import 'models.dart';

/// 開始使用: what someone holding a 身分 does first, from what the church
/// already has, in the order to do it. A 身分 is gone once each step but
/// the optional ones is done, so a church long in use shows nothing.
enum StartStep {
  /// 服事設定: which days, which duties.
  services,

  /// The church's logo (an admin's, optional): on the invite page, the
  /// home page's title, and the link and icon the web app shares.
  logo,

  /// 邀請同工.
  invite,

  /// Someone else in the group; for an admin, in any open service.
  addStaff,

  /// 小組 (an admin's, optional): a church may have none.
  smallGroups,

  /// The first roster with someone on it (管理員, 行政).
  arrange,

  /// 安排服事 of the service, until a day of it has someone on a duty they arrange.
  planWeeks,

  /// When the 小組 meets, for 回報人數.
  meets
  ;

  /// Left for the church to choose: never the next step, and no reason to
  /// keep 開始使用 up.
  bool get optional => this == smallGroups || this == logo;
}

/// Where a step is.
enum StartState {
  /// To do.
  todo,

  /// Done on this side, waiting on others: invites out, nobody joined yet.
  waiting,

  /// Not yet: it needs someone else to have joined.
  locked,

  done,
}

/// One step, about [group] when it is one group's: what it opens.
typedef GettingStartedStep = ({StartStep step, ChurchGroup? group, StartState state});

/// The steps of one 身分, done ones too, in order.
@immutable
class GettingStarted {
  const GettingStarted(this.identity, this.steps);

  final Identity identity;
  final List<GettingStartedStep> steps;

  /// The step to do now: the first to do, an optional one aside.
  GettingStartedStep? get next => _nextFrom(0);

  /// The step to go on to from [step]'s page: the next one to do after it.
  GettingStartedStep? after(GettingStartedStep step) {
    final i = steps.indexWhere((s) => s.step == step.step && s.group == step.group);
    return i < 0 ? null : _nextFrom(i + 1);
  }

  GettingStartedStep? _nextFrom(int from) =>
      steps.skip(from).where((s) => s.state == StartState.todo && !s.step.optional).firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is GettingStarted && other.identity == identity && listEquals(other.steps, steps);

  @override
  int get hashCode => Object.hash(identity, Object.hashAll(steps));

  @override
  String toString() => 'GettingStarted($identity, $steps)';
}

/// What [me] still has to start, a list for each 身分 with something left:
/// for an admin only the admin's, which covers the rest. [members] is
/// everyone, [pending] how many moved from self-host have not signed in
/// yet (they can be put in a service, but are still to be invited),
/// [invited] whether an invite still works, [servicesSeen] whether they
/// opened the services from 開始使用 on this device, [hasLogo] whether the
/// church has one, [rosters] saved ones: from today on, and those of the
/// past weeks (a church between seasons is not new again).
List<GettingStarted> gettingStarted({
  required Member me,
  required List<Member> members,
  required int pending,
  required ServiceSettings services,
  required MinistrySettings ministries,
  required List<SmallGroupDetails> smallGroups,
  required Iterable<Roster> rosters,
  required bool attendanceOn,
  bool invited = false,
  bool servicesSeen = false,
  bool hasLogo = false,
}) {
  bool someoneElseIn(ChurchGroup group) =>
      members.any((m) => m.uid != me.uid && m.isIn(group, ministries: ministries.ministries));
  bool arranged(bool Function(Roster day, Duty duty) counts) =>
      rosters.any((r) => r.duties.any((d) => d.people.isNotEmpty && counts(r, d)));
  final anyArranged = arranged((_, _) => true);
  final joined = members.any((m) => m.uid != me.uid);
  final someoneToPutIn = joined || pending > 0;
  bool open(String service) => services.byId(service)?.enabled ?? false;
  StartState doneIf(bool done) => done ? StartState.done : StartState.todo;
  GettingStartedStep step(StartStep step, bool done, [ChurchGroup? group]) =>
      (step: step, group: group, state: doneIf(done));

  List<GettingStartedStep> forService(String id) => [
    step(StartStep.addStaff, someoneElseIn(ServiceGroup(id)), ServiceGroup(id)),
    step(StartStep.planWeeks, arranged((r, _) => !r.isEvent && r.type == id), ServiceGroup(id)),
  ];

  List<GettingStartedStep> forAdmin() {
    final opened = [for (final s in services.enabled) ServiceGroup(s.id)];
    final staffed = anyArranged || opened.any(someoneElseIn);
    return [
      step(StartStep.services, servicesSeen || anyArranged),
      step(StartStep.logo, hasLogo),
      (
        step: StartStep.invite,
        group: null,
        state: joined
            ? StartState.done
            : invited
            ? StartState.waiting
            : StartState.todo,
      ),
      (
        step: StartStep.addStaff,
        group: opened.where((g) => !someoneElseIn(g)).firstOrNull ?? opened.firstOrNull,
        state: staffed
            ? StartState.done
            : someoneToPutIn
            ? StartState.todo
            : StartState.locked,
      ),
      step(StartStep.smallGroups, smallGroups.isNotEmpty, opened.firstOrNull),
      step(StartStep.arrange, anyArranged),
    ];
  }

  List<GettingStartedStep> steps(Identity i) => switch (i) {
    AdminIdentity() || PastorIdentity(services: null) => forAdmin(),
    OfficeIdentity() => [step(StartStep.arrange, anyArranged)],
    PastorIdentity(services: final ids?) => [
      for (final id in ids)
        if (open(id)) ...forService(id),
    ],
    ServiceLead(service: final id) => open(id) ? forService(id) : const [],
    MinistryLead(ministry: final id) => switch (ministries.byId(id)) {
      null => const [],
      final ministry => [
        step(StartStep.addStaff, someoneElseIn(MinistryGroup(id)), MinistryGroup(id)),
        if (ministry.duties.where((d) => open(d.service)).firstOrNull case final first?)
          step(
            StartStep.planWeeks,
            arranged((r, d) => ministry.dutiesIn(r.isEvent ? null : r.type).contains(d.role)),
            ServiceGroup(first.service),
          ),
      ],
    },
    SmallGroupLead(smallGroup: final id) => switch (smallGroups.byId(id)) {
      null => const [],
      final group => [
        step(StartStep.addStaff, someoneElseIn(SmallGroup(id)), SmallGroup(id)),
        if (attendanceOn) step(StartStep.meets, group.weekday != null, SmallGroup(id)),
      ],
    },
  };

  final held = me.isAdmin ? me.identities.where((i) => i.makesAdmin).take(1) : me.identities;
  return [
    for (final i in held)
      if (steps(i) case final all when all.any((s) => s.state != StartState.done && !s.step.optional))
        GettingStarted(i, all),
  ];
}
