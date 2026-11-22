part of 'models.dart';

/// What a member may do, from their 身分 and groups: the app's copy of
/// functions/src/powers.ts and firestore.rules, checked against both by
/// testdata/church_rules.json.
extension MemberPowers on Member {
  /// In [group]: admins hold every one, 行政 both (as the rules read them).
  bool inGroup(Group group) => isAdmin || groups.contains(group);

  /// Whether the 服事表 tab shows this member every service, not only
  /// their 牧區: admins and 行政.
  bool get seesAllServices => inGroup(Group.rosterEditors);

  /// Whether this member may edit all of a [serviceType] roster: admins,
  /// 行政 and its 負責人 or 牧者 (testdata/church_rules.json,
  /// rosterEditing).
  bool canEditRosters(String serviceType) => inGroup(Group.rosterEditors) || leadTypes.contains(serviceType);

  /// [canEditRosters], of a service among [serviceIds], those the church
  /// has had (settings/services `ids`: one taken off the list keeps its
  /// rosters editable): the backend and the rules refuse any other.
  bool editsRostersOf(String serviceType, Iterable<String> serviceIds) =>
      serviceIds.contains(serviceType) && canEditRosters(serviceType);

  /// Whether this member may edit all of an event's roster: admins and 行政.
  bool get canEditEventRosters => inGroup(Group.rosterEditors);

  /// Whether this member arranges any roster, and so sees who cannot serve
  /// when (不能服事的日子, #91; firestore.rules arrangesRosters): admins,
  /// 行政, and the 負責人 and 牧者 of a service or a 事工.
  bool get arrangesRosters => inGroup(Group.rosterEditors) || leadTypes.isNotEmpty || leadMinistries.isNotEmpty;

  /// The duties this member arranges on a day of [serviceType] (null: an
  /// event's) without editing all of it, as a 負責人 of the 事工 in
  /// [ministries] that link them; through the backend (editLedDuties).
  Set<String> ledDuties(List<Ministry> ministries, String? serviceType) => {
    for (final m in ministries)
      if (leadMinistries.contains(m.id)) ...m.dutiesIn(serviceType),
  };

  /// Whether this member leads [group]: a service as its 負責人 or 牧者, a
  /// 事工, or a 小組 as its 小組長.
  bool leadsGroup(ChurchGroup group) => switch (group) {
    ServiceGroup(:final id) => leadTypes.contains(id),
    MinistryGroup(:final id) => leadMinistries.contains(id),
    SmallGroup(:final id) => leadSmallGroups.contains(id),
    GatheringGroup() => false,
  };

  /// Whether this member manages [group]'s 同工: as an admin, its 負責人,
  /// or, for a 小組, its service's.
  bool managesGroup(ChurchGroup group) =>
      isAdmin ||
      leadsGroup(group) ||
      switch (group) {
        SmallGroup(:final service?) => leadTypes.contains(service),
        _ => false,
      };

  /// Whether this member may open, change or close a 小組 of service
  /// [before] (null: none yet) as one of [after] (null: closed)
  /// (testdata/church_rules.json, smallGroupEditing): admins any; a
  /// service's 負責人 and 牧者 those in it.
  bool mayEditSmallGroup(String? before, String? after) =>
      isAdmin ||
      ((before != null || after != null) && [before, after].every((s) => s == null || leadTypes.contains(s)));

  /// Whether this member may set when 小組 [group] meets, and nothing else
  /// of it (testdata/church_rules.json, smallGroupScheduling): who may
  /// change it, and its 小組長.
  bool schedulesSmallGroup(SmallGroup group) =>
      leadsGroup(group) || (group.service != null && mayEditSmallGroup(group.service, group.service));

  /// Whether this member sets when [group] meets (聚會時間): a 小組's as
  /// [schedulesSmallGroup], not 行政; any other's who sets its 人數
  /// ([writesAttendance]).
  bool schedules(ChurchGroup group) => switch (group) {
    SmallGroup() => schedulesSmallGroup(group),
    _ => writesAttendance(group),
  };

  /// Whether this member sees every group's 人數 and puts them together
  /// (人數總覽, #93): admins and 行政.
  bool get overseesAttendance => inGroup(Group.rosterEditors);

  /// Whether this member fills in the 人數 of [group], and sets when it
  /// meets and who else fills them in (testdata/church_rules.json,
  /// attendanceAccess, `manages`): admins and 行政 any, a 其他聚會's too; a
  /// service's 負責人 and 牧者 its own and its 小組'; a 小組長 their 小組's.
  bool writesAttendance(ChurchGroup group) => group is! MinistryGroup && (overseesAttendance || managesGroup(group));

  /// Whether this member fills in the 人數 of [group], whose [fillers]
  /// (負責回報) they may be one of, and sees them.
  bool fillsAttendance(ChurchGroup group, List<String> fillers) =>
      writesAttendance(group) || (group is! MinistryGroup && fillers.contains(uid));

  /// Whether 人數總覽 lists anything for them (#95): every group for
  /// admins and 行政; a service's and its 小組' for its 負責人 and 牧者.
  bool get seesAttendanceOverview => overseesAttendance || leadTypes.isNotEmpty;

  /// Whether this member sees the 人數 of [group]: who fills them in.
  bool readsAttendance(ChurchGroup group, [List<String> fillers = const []]) => fillsAttendance(group, fillers);

  /// The group keys whose 人數 this member is reminded of, at 21:00 and on
  /// 首頁 (testdata/church_rules.json, attendanceReminded): a service's as
  /// its 負責人, not its 牧者, who only sees them; a 小組's as its 小組長.
  /// Those of the groups that asked them to fill theirs in (fillers) too:
  /// [AttendanceData.mine].
  List<String> get remindedAttendance => [
    ...{
      for (final i in identities)
        ...switch (i) {
          ServiceLead(:final service) => [ServiceGroup(service).key],
          SmallGroupLead(:final smallGroup) => [SmallGroup(smallGroup).key],
          _ => const <String>[],
        },
    },
  ];

  /// Whether this member is reminded of group [key]'s 人數, whose
  /// [fillers] (負責回報) they may be one of.
  bool remindedOf(String key, List<String> fillers) =>
      remindedAttendance.contains(key) || (!key.startsWith('ministry:') && fillers.contains(uid));

  /// [leadsGroup] by an event's group key; the church's ('') nobody leads.
  bool _leadsKey(String key) => switch (ChurchGroup.parse(key)) {
    final g? => leadsGroup(g),
    null => false,
  };

  /// Whether this member may add [target] to [group] or take them out
  /// (testdata/church_rules.json, groupMembership): an admin anyone; the
  /// group's 負責人 (a 小組's service's too) only a plain 同工, since 身分
  /// are the admin's to give.
  bool mayMove(Member target, ChurchGroup group) => isAdmin || (managesGroup(group) && target.identities.isEmpty);

  /// Whether this member may add a plain 同工 to [group], someone new by
  /// name too (addByName): [mayMove] for one holding no 身分.
  bool addsStaffTo(ChurchGroup group) => isAdmin || managesGroup(group);

  /// Whether this member may put anyone on the list of [duty] in
  /// [serviceType], or take them off it (testdata/church_rules.json,
  /// dutyListEditing, #94): admins and 行政 any; a service's 負責人 and
  /// 牧者 its duties; a 事工's 負責人 those the 事工 in [ministries] they lead link
  /// there. Being on a list gives nothing, so anyone may be put on it.
  bool editsDutyList(List<Ministry> ministries, String serviceType, String duty) =>
      canEditRosters(serviceType) || ledDuties(ministries, serviceType).contains(duty);

  /// What this member arranges on a day of [serviceType]: all of it, or
  /// only the duties the 事工 in [ministries] they lead link.
  Arranges arranges(List<Ministry> ministries, String serviceType) =>
      canEditRosters(serviceType) ? const Arranges.all() : Arranges.only(ledDuties(ministries, serviceType));

  /// As [arranges], on the roster of an event of [group] (null: the
  /// church's): all of it for admins, 行政 and the group's 負責人.
  Arranges arrangesEvent(List<Ministry> ministries, String? group) =>
      canEditEventRoster(group) ? const Arranges.all() : Arranges.only(ledDuties(ministries, null));

  /// Whether this member arranges all of an event's roster of [group]
  /// (null: the church's; testdata/church_rules.json, rosterEditing):
  /// admins, 行政 and that group's 負責人.
  bool canEditEventRoster(String? group) => canEditEventRosters || (group != null && _leadsKey(group));

  /// Whether this member may change an event of group [before] (null: none
  /// yet) to [after] (null: deleted), '' being the church's
  /// (testdata/church_rules.json, eventWriting): admins and 行政 any; a
  /// group's 負責人 that group's events, never the church's.
  bool mayWriteEvent(String? before, String? after) {
    if (inGroup(Group.calendarEditors)) return true;
    return (before != null || after != null) &&
        (before == null || _leadsKey(before)) &&
        (after == null || _leadsKey(after));
  }

  /// Whether this member may change or delete [event] as it is, keeping
  /// it its group's: whether tapping it opens it to edit.
  bool editsEvent(CalendarEvent event) => mayWriteEvent(event.group ?? '', event.group ?? '');

  /// Whether this member changes the services' settings (settings/services):
  /// their duties, 常用特別活動 and when they meet. Admins only.
  bool get editsServiceSettings => isAdmin;

  /// Whether this member may make events: admins, 行政 and any 負責人.
  bool get makesEvents => inGroup(Group.calendarEditors) || leads;

  /// Whether this member sees the church's member list: admins, 行政 and
  /// whoever leads something.
  bool get readsMembers => inGroup(Group.rosterEditors) || leads;

  /// What picking people for [duty] on [roster] may change besides who is
  /// on it that day, the church's [services] and [ministries] as they are.
  DutyRights rightsOnDuty(
    Roster roster,
    String duty, {
    ServiceSettings? services,
    List<Ministry> ministries = const [],
  }) {
    if (roster.isEvent) return const DutyRights();
    final type = roster.type;
    final arrangesAll = arranges(ministries, type).all;
    // A duty only this day has: no list.
    final editsList = (services?.byId(type)?.duties.contains(duty) ?? false) && editsDutyList(ministries, type, duty);
    return DutyRights(
      // Putting someone on the list moves the staff order too: only whoever
      // arranges all of the day. A 事工's 負責人 only takes off, and puts
      // on from the duty's page (#94).
      putsOnList: arrangesAll && editsList,
      takesOffList: editsList,
      // The staff order is the whole service's: not a 事工 leader's.
      reorders: arrangesAll,
      addsStaff: addsStaffTo(ServiceGroup(type)),
      dropsFutureGuests: true,
    );
  }
}

/// What picking people for a duty on a day may change besides who is on
/// it: [MemberPowers.rightsOnDuty]. An event's roster is in no service:
/// no list, no staff order of its own, no one to add to it.
@immutable
class DutyRights {
  const DutyRights({
    this.putsOnList = false,
    this.takesOffList = false,
    this.reorders = false,
    this.addsStaff = false,
    this.dropsFutureGuests = false,
  });

  /// Puts anyone on the duty's list, picking them.
  final bool putsOnList;

  /// Takes someone off the duty's list.
  final bool takesOffList;

  /// Drags the duty's staff order.
  final bool reorders;

  /// Adds a 同工 by a name typed (新增同工).
  final bool addsStaff;

  /// Takes a name arranged this once off the days ahead too (之後都不排).
  final bool dropsFutureGuests;
}
