import 'package:flutter/foundation.dart';

import 'models.dart';

/// 開始使用: what someone holding a 身分 does first, from what the church
/// already has. A step is gone once done, a 身分 once all of its are, so a
/// church long in use shows nothing.
enum StartStep {
  /// 服事設定: which days, which duties.
  services,

  /// 邀請同工.
  invite,

  /// The first roster with someone on it (管理員, 行政).
  arrange,

  /// Someone else in the group.
  addStaff,

  /// 排好幾週 of the service, until a day of it has someone on a duty they arrange.
  planWeeks,

  /// When the 小組 meets, for 回報人數.
  meets
  ;

  /// Whether a roster with someone on it is what makes it done.
  bool get wantsArranging => this == services || this == arrange || this == planWeeks;
}

/// One step, about [group] when it is one group's: what it opens.
typedef GettingStartedStep = ({StartStep step, ChurchGroup? group});

/// The steps left for one 身分.
@immutable
class GettingStarted {
  const GettingStarted(this.identity, this.steps);

  final Identity identity;
  final List<GettingStartedStep> steps;

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
/// yet, [rosters] saved ones: from today on, and those of the past weeks
/// when they are what makes a step done (a church between seasons).
List<GettingStarted> gettingStarted({
  required Member me,
  required List<Member> members,
  required int pending,
  required ServiceSettings services,
  required MinistrySettings ministries,
  required List<SmallGroupDetails> smallGroups,
  required Iterable<Roster> rosters,
  required bool attendanceOn,
}) {
  bool someoneElseIn(ChurchGroup group) => members.any((m) => m.uid != me.uid && m.isIn(group));
  bool arranged(bool Function(Roster day, Duty duty) counts) =>
      rosters.any((r) => r.duties.any((d) => d.people.isNotEmpty && counts(r, d)));
  final anyArranged = arranged((_, _) => true);
  bool open(String service) => services.byId(service)?.enabled ?? false;

  List<GettingStartedStep> forService(String id) => [
    if (!someoneElseIn(ServiceGroup(id))) (step: StartStep.addStaff, group: ServiceGroup(id)),
    if (!arranged((r, _) => !r.isEvent && r.type == id)) (step: StartStep.planWeeks, group: ServiceGroup(id)),
  ];

  List<GettingStartedStep> steps(Identity i) => switch (i) {
    AdminIdentity() || PastorIdentity(services: null) => [
      if (!anyArranged) (step: StartStep.services, group: null),
      if (pending == 0 && !members.any((m) => m.uid != me.uid)) (step: StartStep.invite, group: null),
      if (!anyArranged) (step: StartStep.arrange, group: null),
    ],
    OfficeIdentity() => [if (!anyArranged) (step: StartStep.arrange, group: null)],
    PastorIdentity(services: final ids?) => [
      for (final id in ids)
        if (open(id)) ...forService(id),
    ],
    ServiceLead(service: final id) => open(id) ? forService(id) : const [],
    MinistryLead(ministry: final id) => switch (ministries.byId(id)) {
      null => const [],
      final ministry => [
        if (!someoneElseIn(MinistryGroup(id))) (step: StartStep.addStaff, group: MinistryGroup(id)),
        if (ministry.duties.where((d) => open(d.service)).firstOrNull case final first?
            when !arranged((r, d) => ministry.dutiesIn(r.isEvent ? null : r.type).contains(d.role)))
          (step: StartStep.planWeeks, group: ServiceGroup(first.service)),
      ],
    },
    SmallGroupLead(smallGroup: final id) => switch (smallGroups.byId(id)) {
      null => const [],
      final group => [
        if (!someoneElseIn(SmallGroup(id))) (step: StartStep.addStaff, group: SmallGroup(id)),
        if (attendanceOn && group.weekday == null) (step: StartStep.meets, group: SmallGroup(id)),
      ],
    },
  };

  final held = me.isAdmin ? me.identities.where((i) => i.makesAdmin).take(1) : me.identities;
  return [
    for (final i in held)
      if (steps(i) case final left when left.isNotEmpty) GettingStarted(i, left),
  ];
}
