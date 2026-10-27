/// Plain data types shared by the repositories, the state layer and the UI.
///
/// Nothing here imports Firebase: IDs are strings and times are [DateTime] or
/// [Day], so the data layer can move off Firestore without touching callers
/// (docs/design.md, 遷移預留).
library;

import 'package:flutter/foundation.dart';

import 'church_time.dart';
import 'day.dart';
import 'identities.dart';

export 'church_time.dart' show ChurchTimeZone;
export 'attendance.dart';
export 'identities.dart';

enum ChurchStatus { active, suspended, deleted }

@immutable
class Church {
  const Church({
    required this.id,
    required this.name,
    this.status = ChurchStatus.active,
    this.logoUrl,
    this.homeName,
    this.deletedAt,
    this.timeZone = ChurchTimeZone.fallback,
    this.attendanceSince,
    this.takesJoinRequests = true,
  });

  final String id;
  final String name;
  final ChurchStatus status;

  /// Download URL of the 512px logo, or null when the church has none.
  final String? logoUrl;

  /// 主畫面名稱: the shorter name under the home-screen icon, or null to use
  /// [name].
  final String? homeName;
  final DateTime? deletedAt;

  /// Its time zone: its today, its reminders' evening and every time shown
  /// go by it (#73).
  final ChurchTimeZone timeZone;

  /// 回報人數 (#85): on since this day, which no meeting before is asked
  /// for; null while off.
  final Day? attendanceSince;

  /// Whether someone with its church URL may ask to join (申請加入, #88);
  /// its admin can turn that off.
  final bool takesJoinRequests;

  /// Past this many characters some phones cut the home-screen name off;
  /// the most it may have is `TextLimits.homeName`.
  static const homeNameSafeLength = 6;

  /// How long a church its admin deleted can be restored (RESTORE_DAYS in
  /// functions/src/church.ts).
  static const restoreWindow = Duration(days: 30);

  bool get isActive => status == ChurchStatus.active;

  /// The last moment its admin can restore it; null unless deleted.
  DateTime? get restorableUntil => status == ChurchStatus.deleted ? deletedAt?.add(restoreWindow) : null;

  Church copyWith({
    String? name,
    ChurchStatus? status,
    String? logoUrl,
    String? Function()? homeName,
    ChurchTimeZone? timeZone,
    Day? Function()? attendanceSince,
    bool? takesJoinRequests,
  }) => Church(
    id: id,
    name: name ?? this.name,
    status: status ?? this.status,
    logoUrl: logoUrl ?? this.logoUrl,
    homeName: homeName == null ? this.homeName : homeName(),
    deletedAt: deletedAt,
    timeZone: timeZone ?? this.timeZone,
    attendanceSince: attendanceSince == null ? this.attendanceSince : attendanceSince(),
    takesJoinRequests: takesJoinRequests ?? this.takesJoinRequests,
  );
}

/// Who someone is in a church. Only [admin] carries permissions; the rest
/// are labels.
enum Role { admin, leader, staff, member }

/// Edit permissions, orthogonal to [Role]. An admin holds all of them.
enum Group {
  rosterEditors('roster-editors'),
  calendarEditors('calendar-editors')
  ;

  const Group(this.id);

  /// The string stored in Firestore and checked by firestore.rules.
  final String id;

  static Group? byId(String id) {
    for (final group in values) {
      if (group.id == id) return group;
    }
    return null;
  }
}

/// The duties a member can serve in one service.
///
/// A roster editor may only edit the services they hold a zone in.
@immutable
class Zone {
  const Zone({required this.serviceType, this.duties = const [], this.smallGroups = const []});

  final String serviceType;
  final List<String> duties;

  /// Plain member data within this 牧區, unrelated to permission [Group].
  final List<String> smallGroups;

  Zone copyWith({List<String>? duties, List<String>? smallGroups}) => Zone(
    serviceType: serviceType,
    duties: duties ?? this.duties,
    smallGroups: smallGroups ?? this.smallGroups,
  );

  @override
  bool operator ==(Object other) =>
      other is Zone &&
      other.serviceType == serviceType &&
      listEquals(other.duties, duties) &&
      listEquals(other.smallGroups, smallGroups);

  @override
  int get hashCode => Object.hash(serviceType, Object.hashAll(duties), Object.hashAll(smallGroups));
}

/// Kinds of push notification a member can turn off per church.
enum NotificationKind { reminder, rosterChange, memberLeft, attendance, joinRequest }

/// When a member is reminded of their duties: Monday evening of the week's
/// duties (Monday to Sunday), the evening before each, or both. Matches
/// ReminderTiming in functions/src/notifications.ts.
enum ReminderTiming { weekly, dayBefore, both }

@immutable
class Member {
  const Member({
    required this.uid,
    required this.name,
    this.email = '',
    this.role = Role.staff,
    this.groups = const {},
    this.zones = const [],
    List<Identity> identities = const [],
    this.ministries = const {},
    this.smallGroups = const {},
    this.mutedNotifications = const {},
    this.reminderTiming = ReminderTiming.weekly,
    this.joinedAt,
  }) : _identities = identities;

  final String uid;
  final String name;
  final String email;
  final Role role;
  final Set<Group> groups;
  final List<Zone> zones;
  final List<Identity> _identities;

  /// The 事工 this member is a 同工 of (#82).
  final Set<String> ministries;

  /// The 小組 this member is one of (#85).
  final Set<String> smallGroups;
  final Set<NotificationKind> mutedNotifications;
  final ReminderTiming reminderTiming;
  final DateTime? joinedAt;

  /// 管理員, or a whole church's 牧者: role admin, as the rules read it.
  bool get isAdmin => role == Role.admin;

  /// Their 身分 (#82). A member doc from before them has none stored: an
  /// admin is then 管理員, and the old permission groups 行政
  /// (scripts/migrate-leads.ts moves them for good).
  List<Identity> get identities => _identities.isNotEmpty
      ? _identities
      : [
          if (isAdmin) const AdminIdentity(),
          if (!isAdmin && groups.isNotEmpty) const OfficeIdentity(),
        ];

  /// The services they lead, as 負責人 or 牧者; stored as `leadTypes` for
  /// the security rules.
  List<String> get leadTypes => [
    ...{
      for (final i in identities)
        ...switch (i) {
          ServiceLead(:final service) => [service],
          PastorIdentity(:final services?) => services,
          _ => const <String>[],
        },
    },
  ];

  /// The 事工 they lead; stored as `leadMinistries`.
  List<String> get leadMinistries => [
    ...{
      for (final i in identities)
        if (i case MinistryLead(:final ministry)) ministry,
    },
  ];

  /// The 小組 they lead as 小組長 (#85); stored as `leadSmallGroups`.
  List<String> get leadSmallGroups => [
    ...{
      for (final i in identities)
        if (i case SmallGroupLead(:final smallGroup)) smallGroup,
    },
  ];

  /// Whether they lead anything, so pick people and add 同工.
  bool get leads => leadTypes.isNotEmpty || leadMinistries.isNotEmpty || leadSmallGroups.isNotEmpty;

  /// This member holding [next] as their 身分, with what the rules and
  /// older apps read set to match: 管理員 and a whole church's 牧者 are
  /// role admin, 行政 the two permission groups.
  Member withIdentities(List<Identity> next) {
    final admin = next.any((i) => i is AdminIdentity || (i is PastorIdentity && i.wholeChurch));
    return Member(
      uid: uid,
      name: name,
      email: email,
      role: admin ? Role.admin : (role == Role.admin ? Role.staff : role),
      groups: next.contains(const OfficeIdentity()) ? const {Group.rosterEditors, Group.calendarEditors} : const {},
      zones: zones,
      identities: [
        ...{...next},
      ],
      ministries: ministries,
      smallGroups: smallGroups,
      mutedNotifications: mutedNotifications,
      reminderTiming: reminderTiming,
      joinedAt: joinedAt,
    );
  }

  /// In [group]: admins hold every one, 行政 both (as the rules read them).
  bool inGroup(Group group) => isAdmin || groups.contains(group);

  /// The service types this member holds a zone in, in zone order. Stored
  /// as `zoneTypes` because the security rules cannot look inside [zones].
  List<String> get zoneTypes => [
    for (final type in {for (final zone in zones) zone.serviceType}) type,
  ];

  /// Whether the 服事表 tab shows this member every service, not only
  /// their 牧區: admins and 行政.
  bool get seesAllServices => inGroup(Group.rosterEditors);

  /// The services of [services] the 服事表 tab shows this member: the 牧區
  /// they belong to and the services they lead, or all of them for admins
  /// and 行政. Only tidies the tab; every member may still read every
  /// roster.
  List<Service> rosterServices(List<Service> services, {List<Ministry> ministries = const []}) {
    if (seesAllServices) return services;
    final mine = {
      ...zoneTypes,
      ...leadTypes,
      for (final s in services)
        if (ledDuties(ministries, s.id).isNotEmpty) s.id,
    };
    return [
      for (final s in services)
        if (mine.contains(s.id)) s,
    ];
  }

  /// Whether the 服事表 tab, showing [services], is empty for this member
  /// until an admin puts them in a 牧區: they are in none of them.
  bool waitsForZone(List<Service> services) => services.isNotEmpty && rosterServices(services).isEmpty;

  /// Whether [other] has the same of what an admin sets on a member: name,
  /// role, groups and 牧區. The member's own notification settings are not
  /// part of it.
  bool sameAdminFields(Member other) =>
      uid == other.uid &&
      name == other.name &&
      role == other.role &&
      setEquals(groups, other.groups) &&
      listEquals(zones, other.zones) &&
      listEquals(identities, other.identities) &&
      setEquals(ministries, other.ministries) &&
      setEquals(smallGroups, other.smallGroups);

  /// Whether this member may edit all of a [serviceType] roster: admins,
  /// 行政 and its 負責人 or 牧者 (testdata/church_rules.json,
  /// rosterEditing).
  bool canEditRosters(String serviceType) => inGroup(Group.rosterEditors) || leadTypes.contains(serviceType);

  /// Whether this member may edit all of an event's roster: admins and 行政.
  bool get canEditEventRosters => inGroup(Group.rosterEditors);

  /// The duties this member arranges on a day of [serviceType] (null: an
  /// event's) without editing all of it, as a 負責人 of the 事工 in
  /// [ministries] that link them; through the backend (editLedDuties).
  Set<String> ledDuties(List<Ministry> ministries, String? serviceType) => {
    for (final m in ministries)
      if (leadMinistries.contains(m.id)) ...m.dutiesIn(serviceType),
  };

  /// Whether this member is a 同工 of [group]: in its 牧區, one of the
  /// 事工's, or of the 小組.
  bool isIn(ChurchGroup group) => switch (group) {
    ServiceGroup(:final id) => zoneTypes.contains(id),
    MinistryGroup(:final id) => ministries.contains(id),
    SmallGroup(:final id) => smallGroups.contains(id),
  };

  /// Whether this member leads [group]: a service as its 負責人 or 牧者, a
  /// 事工, or a 小組 as its 小組長.
  bool leadsGroup(ChurchGroup group) => switch (group) {
    ServiceGroup(:final id) => leadTypes.contains(id),
    MinistryGroup(:final id) => leadMinistries.contains(id),
    SmallGroup(:final id) => leadSmallGroups.contains(id),
  };

  /// Whether this member manages [group]'s 同工: as an admin, its 負責人,
  /// or, for a 小組 in service [service], that service's.
  bool managesGroup(ChurchGroup group, {String? service}) =>
      isAdmin || leadsGroup(group) || (group is SmallGroup && service != null && leadTypes.contains(service));

  /// Whether this member may open, change or close a 小組 of service
  /// [before] (null: none yet) as one of [after] (null: closed)
  /// (testdata/church_rules.json, smallGroupEditing): admins any; a
  /// service's 負責人 and 牧者 those in it.
  bool mayEditSmallGroup(String? before, String? after) =>
      isAdmin ||
      ((before != null || after != null) && [before, after].every((s) => s == null || leadTypes.contains(s)));

  /// Whether this member fills in the 人數 of group [key]
  /// (testdata/church_rules.json, attendanceAccess): admins any; a
  /// service's 負責人 and 牧者 its own and its 小組' ([smallGroupService],
  /// the 小組's service); a 小組長 their 小組's.
  bool writesAttendance(String key, {String? smallGroupService}) =>
      isAdmin ||
      switch (ChurchGroup.parse(key)) {
        ServiceGroup(:final id) => leadTypes.contains(id),
        SmallGroup(:final id) =>
          leadSmallGroups.contains(id) || (smallGroupService != null && leadTypes.contains(smallGroupService)),
        _ => false,
      };

  /// Whether this member sees the 人數 of group [key]: who fills them in,
  /// and 行政 a service's.
  bool readsAttendance(String key, {String? smallGroupService}) =>
      writesAttendance(key, smallGroupService: smallGroupService) ||
      (ChurchGroup.parse(key) is ServiceGroup && inGroup(Group.rosterEditors));

  /// The group keys whose 人數 this member is reminded of, at 21:00 and on
  /// 首頁 (testdata/church_rules.json, attendanceReminded): a service's as
  /// its 負責人, not its 牧者, who only sees them; a 小組's as its 小組長.
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

  /// [leadsGroup] by an event's group key; the church's ('') nobody leads.
  bool _leadsKey(String key) => switch (ChurchGroup.parse(key)) {
    final g? => leadsGroup(g),
    null => false,
  };

  /// Whether this member may add [target] to [group] or take them out
  /// (testdata/church_rules.json, groupMembership): an admin anyone; the
  /// group's 負責人 (for a 小組 in [service], that service's too) only a
  /// plain 同工, since 身分 are the admin's to give.
  bool mayMove(Member target, ChurchGroup group, {String? service}) =>
      isAdmin ||
      (managesGroup(group, service: service) && !target.isAdmin && target.groups.isEmpty && target._identities.isEmpty);

  /// This member added to [group] ([member] true; a service with [duties]
  /// and [smallGroups]) or taken out, as setGroupMember writes it.
  Member inGroupAs(
    ChurchGroup group, {
    required bool member,
    List<String> duties = const [],
    List<String> smallGroups = const [],
  }) => switch (group) {
    ServiceGroup(:final id) => copyWith(
      zones: [
        for (final z in zones)
          if (z.serviceType != id) z,
        if (member)
          zones.where((z) => z.serviceType == id).firstOrNull ??
              Zone(serviceType: id, duties: duties, smallGroups: smallGroups),
      ],
    ),
    MinistryGroup(:final id) => copyWith(ministries: member ? {...ministries, id} : ({...ministries}..remove(id))),
    SmallGroup(:final id) => copyWith(smallGroups: member ? {...smallGroups, id} : ({...smallGroups}..remove(id))),
  };

  /// This member as 小組長 of 小組 [id] or not, as editSmallGroup writes it;
  /// themself when already so.
  Member withSmallGroupLead(String id, {required bool lead}) => leadSmallGroups.contains(id) == lead
      ? this
      : copyWith(
          identities: [
            for (final i in identities)
              if (i != SmallGroupLead(id)) i,
            if (lead) SmallGroupLead(id),
          ],
        );

  /// What this member arranges on a day of [serviceType]: null for all
  /// of it; otherwise only these duties, those the 事工 in [ministries] they
  /// lead link (none: nothing).
  Set<String>? arranges(List<Ministry> ministries, String serviceType) =>
      canEditRosters(serviceType) ? null : ledDuties(ministries, serviceType);

  /// As [arranges], on the roster of an event of [group] (null: the
  /// church's): all of it for admins, 行政 and the group's 負責人.
  Set<String>? arrangesEvent(List<Ministry> ministries, String? group) =>
      canEditEventRoster(group) ? null : ledDuties(ministries, null);

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

  /// Whether this member may make events: admins, 行政 and any 負責人.
  bool get makesEvents => inGroup(Group.calendarEditors) || leads;

  /// Whether this member sees the church's member list: admins, 行政 and
  /// whoever leads something.
  bool get readsMembers => inGroup(Group.rosterEditors) || leads;

  /// Whether this member is set up to serve [duty] in [serviceType].
  bool serves(String serviceType, String duty) => zones.any(
    (zone) => zone.serviceType == serviceType && zone.duties.contains(duty),
  );

  /// This member with [duty] added to their zone for [serviceType].
  Member withDuty(String serviceType, String duty) {
    if (serves(serviceType, duty)) return this;
    var found = false;
    final next = [
      for (final zone in zones)
        if (zone.serviceType == serviceType)
          () {
            found = true;
            return zone.copyWith(duties: [...zone.duties, duty]);
          }()
        else
          zone,
    ];
    if (!found) next.add(Zone(serviceType: serviceType, duties: [duty]));
    return copyWith(zones: next);
  }

  /// Without [duty] in [serviceType]; still in that 牧區.
  Member withoutDuty(String serviceType, String duty) {
    if (!serves(serviceType, duty)) return this;
    return copyWith(
      zones: [
        for (final zone in zones)
          zone.serviceType == serviceType
              ? zone.copyWith(
                  duties: [
                    for (final d in zone.duties)
                      if (d != duty) d,
                  ],
                )
              : zone,
      ],
    );
  }

  Member copyWith({
    String? name,
    Role? role,
    Set<Group>? groups,
    List<Zone>? zones,
    List<Identity>? identities,
    Set<String>? ministries,
    Set<String>? smallGroups,
    Set<NotificationKind>? mutedNotifications,
    ReminderTiming? reminderTiming,
  }) => Member(
    uid: uid,
    name: name ?? this.name,
    email: email,
    role: role ?? this.role,
    groups: groups ?? this.groups,
    zones: zones ?? this.zones,
    identities: identities ?? _identities,
    ministries: ministries ?? this.ministries,
    smallGroups: smallGroups ?? this.smallGroups,
    mutedNotifications: mutedNotifications ?? this.mutedNotifications,
    reminderTiming: reminderTiming ?? this.reminderTiming,
    joinedAt: joinedAt,
  );
}

/// A colored label on one day's roster: 聖餐, 浸禮, 特會…
@immutable
class EventTag {
  const EventTag({required this.name, required this.color});

  final String name;

  /// One of [EventColors]; stored as its index so dark mode can pick its own
  /// shade.
  final int color;

  @override
  bool operator ==(Object other) => other is EventTag && other.name == name && other.color == color;

  @override
  int get hashCode => Object.hash(name, color);
}

/// Whether [after] is [before] with duty [from] renamed [to] in place and
/// nothing else changed: what functions/src/serviceSettings.ts takes
/// (testdata/church_rules.json, dutyRename).
bool validDutyRename({
  required List<String> before,
  required List<String> after,
  required String from,
  required String to,
}) =>
    from != to &&
    before.contains(from) &&
    !before.contains(to) &&
    listEquals(after, [for (final d in before) d == from ? to : d]);

/// One kind of gathering, e.g. 主日崇拜 on Sundays.
@immutable
class Service {
  const Service({
    required this.id,
    required this.name,
    required this.weekday,
    this.enabled = true,
    this.duties = const [],
    this.events = const [],
  });

  /// Stable ID. Never reused, never deleted (settings/services `ids`).
  final String id;
  final String name;

  /// 1 = Monday … 7 = Sunday.
  final int weekday;

  /// A disabled service keeps its old rosters but gets no new ones.
  final bool enabled;

  /// The roster template: duties a new roster starts with, in order.
  final List<String> duties;

  /// Common special-event tags offered when editing this service's rosters.
  final List<EventTag> events;

  Service copyWith({
    String? name,
    int? weekday,
    bool? enabled,
    List<String>? duties,
    List<EventTag>? events,
  }) => Service(
    id: id,
    name: name ?? this.name,
    weekday: weekday ?? this.weekday,
    enabled: enabled ?? this.enabled,
    duties: duties ?? this.duties,
    events: events ?? this.events,
  );

  @override
  bool operator ==(Object other) =>
      other is Service &&
      other.id == id &&
      other.name == name &&
      other.weekday == weekday &&
      other.enabled == enabled &&
      listEquals(other.duties, duties) &&
      listEquals(other.events, events);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    weekday,
    enabled,
    Object.hashAll(duties),
    Object.hashAll(events),
  );
}

@immutable
class ServiceSettings {
  const ServiceSettings({required this.services, this.ids = const []});

  final List<Service> services;

  /// Every service ID ever configured. Only grows.
  final List<String> ids;

  List<Service> get enabled => [
    for (final service in services)
      if (service.enabled) service,
  ];

  Service? byId(String id) {
    for (final service in services) {
      if (service.id == id) return service;
    }
    return null;
  }

  /// [services] with [ids] grown to include every new ID.
  ServiceSettings withServices(List<Service> services) => ServiceSettings(
    services: services,
    ids: {...ids, for (final s in services) s.id}.toList(),
  );
}

/// One duty on one day: who serves it.
@immutable
class Duty {
  const Duty({
    required this.role,
    this.people = const [],
    this.uids = const {},
  });

  final String role;

  /// Names as shown, in staff order. Names stay even after the person
  /// deletes their account.
  final List<String> people;

  /// Name → uid for the people who are members, so "my services" and
  /// reminders can find them. Free-text names have no entry.
  final Map<String, String> uids;

  Duty copyWith({
    String? role,
    List<String>? people,
    Map<String, String>? uids,
  }) => Duty(
    role: role ?? this.role,
    people: people ?? this.people,
    uids: uids ?? this.uids,
  );

  @override
  bool operator ==(Object other) =>
      other is Duty && other.role == role && listEquals(other.people, people) && mapEquals(other.uids, uids);

  @override
  int get hashCode => Object.hash(
    role,
    Object.hashAll(people),
    Object.hashAll(uids.entries.map((e) => '${e.key}=${e.value}')),
  );
}

/// The calendar event a 活動的服事表 belongs to, as the roster keeps it:
/// the title and days are copied from the calendar, which has the say.
@immutable
class RosterEvent {
  const RosterEvent({
    required this.eventId,
    required this.title,
    required this.lastDay,
    this.cancelled = false,
    this.calendarId,
    this.recurringEventId,
    this.originalStart,
    this.group,
  });

  final String eventId;
  final String title;

  /// Whose the event is (#84, CalendarEvent.group): null the church's.
  /// Copied by the backend; the app never changes it.
  final String? group;

  /// Where the event is, for the backend to find it again (eventSync.ts):
  /// the calendar, and for a day of a recurring event its series and the
  /// start it had there, as Google gives them.
  final String? calendarId;
  final String? recurringEventId;
  final String? originalStart;

  /// The event's last day; [Roster.day] is its first.
  final Day lastDay;

  /// The event was deleted: the roster is kept a while but neither shown
  /// nor reminded of. Only the backend sets it.
  final bool cancelled;

  RosterEvent copyWith({bool? cancelled}) => RosterEvent(
    eventId: eventId,
    title: title,
    lastDay: lastDay,
    cancelled: cancelled ?? this.cancelled,
    calendarId: calendarId,
    recurringEventId: recurringEventId,
    originalStart: originalStart,
    group: group,
  );

  @override
  bool operator ==(Object other) =>
      other is RosterEvent &&
      other.group == group &&
      other.eventId == eventId &&
      other.title == title &&
      other.lastDay == lastDay &&
      other.cancelled == cancelled &&
      other.calendarId == calendarId &&
      other.recurringEventId == recurringEventId &&
      other.originalStart == originalStart;

  @override
  int get hashCode =>
      Object.hash(eventId, title, lastDay, cancelled, calendarId, recurringEventId, originalStart, group);
}

/// One service on one day, or one calendar event ([forEvent]).
@immutable
class Roster {
  const Roster({
    required this.type,
    required this.day,
    this.duties = const [],
    this.events = const [],
    this.saved = true,
    this.forEvent,
  });

  /// Document ID: one roster per service per day.
  static String idFor(String type, Day day) => '${day.key}_$type';

  /// Document ID of an event's roster: no date in it, so it stays put
  /// when the event moves.
  static String idForEvent(String eventId) => 'ev_$eventId';

  String get id => forEvent == null ? idFor(type, day) : idForEvent(forEvent!.eventId);

  /// The service ID; empty for an event's roster.
  final String type;

  /// The day; an event's first day.
  final Day day;
  final List<Duty> duties;

  /// Special-event tags (聖餐, 浸禮…); never on an event's roster.
  final List<EventTag> events;

  /// False for a roster that only exists on screen, built from the service
  /// template because nobody has edited that day yet.
  final bool saved;

  /// The calendar event this roster belongs to, for a 活動的服事表.
  final RosterEvent? forEvent;

  bool get isEvent => forEvent != null;

  /// The last day it is on: an event's last, a service's only.
  Day get lastDay => forEvent?.lastDay ?? day;

  Roster copyWith({
    List<Duty>? duties,
    List<EventTag>? events,
    Day? day,
    bool? saved,
    RosterEvent? forEvent,
  }) => Roster(
    type: type,
    day: day ?? this.day,
    duties: duties ?? this.duties,
    events: events ?? this.events,
    saved: saved ?? this.saved,
    forEvent: forEvent ?? this.forEvent,
  );

  /// Duties explicitly bound to [uid]. Unbound names are guests, never a
  /// runtime identity guess, even when a member has exactly the same name.
  /// A binding counts only while its name is still listed
  /// (testdata/church_rules.json, rosterIdentity).
  List<String> dutiesOf({required String uid}) => [
    for (final duty in duties)
      if (uid.isNotEmpty && duty.uids.entries.any((e) => e.value == uid && duty.people.contains(e.key))) duty.role,
  ];

  @override
  bool operator ==(Object other) =>
      other is Roster &&
      other.type == type &&
      other.day == day &&
      other.saved == saved &&
      other.forEvent == forEvent &&
      listEquals(other.duties, duties) &&
      listEquals(other.events, events);

  @override
  int get hashCode => Object.hash(
    type,
    day,
    saved,
    forEvent,
    Object.hashAll(duties),
    Object.hashAll(events),
  );
}

/// Whether a 事工's 負責人 who leads [roles] on a day may change it from
/// [before] to [after] (testdata/church_rules.json, ledDuties, as
/// functions/src/ledDuties.ts): only those duties change; a day not made
/// yet may be made with people only on them; never deleted.
bool mayChangeLedDuties(Set<String> roles, Roster? before, Roster? after) {
  if (roles.isEmpty || after == null) return false;
  if (before == null) {
    return after.duties.any((d) => roles.contains(d.role)) &&
        after.duties.every((d) => roles.contains(d.role) || d.people.isEmpty) &&
        after.events.isEmpty;
  }
  List<Duty> others(Roster r) => [
    for (final d in r.duties)
      if (!roles.contains(d.role)) d,
  ];
  return before.copyWith(duties: const [], saved: true) == after.copyWith(duties: const [], saved: true) &&
      listEquals(others(before), others(after));
}

/// The global profile at users/{uid}.
@immutable
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    this.email = '',
    this.locale,
    this.appLocale,
    this.photoAiConsent = false,
    this.notificationsSeen = const {},
  });

  final String uid;
  final String name;
  final String email;

  /// BCP-47 tag such as `zh-Hant`, or null to follow the device.
  final String? locale;

  /// The language the app last showed, chosen or the device's: what the
  /// server writes this person's pushes in. Kept by
  /// [ProfileRepository.setAppLocale], not by saving the profile.
  final String? appLocale;

  /// Agreed that photo recognition sends the photos and the church's
  /// member list to Google's Gemini (App Store 5.1.2(i)): asked once per
  /// account. Kept by [ProfileRepository.agreeToPhotoAi].
  final bool photoAiConsent;

  /// How far each church's 通知列表 is seen, by church ID: the newest
  /// notification shown (#89). Kept by
  /// [ProfileRepository.markNotificationsSeen], not by saving the profile.
  final Map<String, DateTime> notificationsSeen;

  UserProfile copyWith({String? appLocale, bool? photoAiConsent, Map<String, DateTime>? notificationsSeen}) =>
      UserProfile(
        uid: uid,
        name: name,
        email: email,
        locale: locale,
        appLocale: appLocale ?? this.appLocale,
        photoAiConsent: photoAiConsent ?? this.photoAiConsent,
        notificationsSeen: notificationsSeen ?? this.notificationsSeen,
      );
}

/// A membership found by the collection-group query: which churches I am in.
@immutable
class Membership {
  const Membership({required this.churchId, required this.member});

  final String churchId;
  final Member member;
}

@immutable
class Invite {
  const Invite({
    required this.code,
    required this.churchId,
    required this.churchName,
    required this.expiresAt,
    this.revoked = false,
    this.createdAt,
    this.zoneTypes = const [],
  });

  final String code;
  final String churchId;
  final String churchName;
  final DateTime expiresAt;
  final bool revoked;
  final DateTime? createdAt;

  /// The 牧區 (service IDs) a member who joins with it belongs to.
  final List<String> zoneTypes;

  bool usableAt(DateTime now) => !revoked && now.isBefore(expiresAt);
}

/// A month of the calendar as the backend names it: `YYYY-MM`.
String monthKey(DateTime m) => '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}';

/// One event on the church's Google Calendar.
@immutable
class CalendarEvent {
  CalendarEvent({
    this.id,
    required this.title,
    required DateTime start,
    required DateTime end,
    this.allDay = false,
    this.location,
    this.description,
    this.recurringEventId,
    this.originalStart,
    this.group,
  }) : start = churchCivilTime(start),
       end = churchCivilTime(end);

  final String? id;
  final String title;

  /// Whose it is (#84): null the whole church's, else a group's
  /// ([ChurchGroup.key]). Made in Google Calendar, it is the church's.
  final String? group;

  /// For one day of a recurring event: its series, and the start it had
  /// there, as Google gives it. Read only.
  final String? recurringEventId;
  final String? originalStart;

  /// The church's wall time (its time zone's), held in a UTC [DateTime] whatever the
  /// phone's zone; the constructor takes the fields as given. All-day
  /// events: midnight of the first day; [end] is exclusive.
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? description;

  /// The church day the event starts on.
  Day get day => Day(start.year, start.month, start.day);

  /// The last church day the event covers. [end] is exclusive, so an event
  /// that ends at midnight does not reach into the next day.
  Day get lastDay {
    final last = end.isAfter(start) ? end.subtract(const Duration(microseconds: 1)) : start;
    return Day(last.year, last.month, last.day);
  }

  /// Whether the event is on [d].
  bool covers(Day d) => !d.isBefore(day) && !d.isAfter(lastDay);

  /// The event's days between [from] and [to], or null if it has none there.
  ({Day first, Day last})? daysWithin(Day from, Day to) {
    if (day.isAfter(to) || lastDay.isBefore(from)) return null;
    return (first: day.isBefore(from) ? from : day, last: lastDay.isAfter(to) ? to : lastDay);
  }

  /// The months the event shows in, as [monthKey]s: from its first day's
  /// to its last day's.
  List<String> get months {
    final last = lastDay;
    return [
      for (
        var m = DateTime(start.year, start.month);
        !m.isAfter(DateTime(last.year, last.month));
        m = DateTime(m.year, m.month + 1)
      )
        monthKey(m),
    ];
  }

  /// The same event to create again, as after it was deleted.
  CalendarEvent get anew => CalendarEvent(
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    location: location,
    description: description,
    group: group,
  );

  CalendarEvent copyWith({
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? location,
    String? description,
    String? Function()? group,
  }) => CalendarEvent(
    id: id,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    allDay: allDay ?? this.allDay,
    location: location ?? this.location,
    description: description ?? this.description,
    recurringEventId: recurringEventId,
    originalStart: originalStart,
    group: group == null ? this.group : group(),
  );
}

/// churches/{cid}/settings/calendar, written by the backend.
@immutable
class CalendarSettings {
  const CalendarSettings({
    this.connected = false,
    this.needsReconnect = false,
    this.calendarName,
    this.calendarId,
    this.revision,
  });

  /// Opaque revision of settings/calendar.updatedAt. Missing revisions never
  /// authorize reuse of a persistent calendar cache.
  final String? revision;

  final bool connected;
  final bool needsReconnect;

  /// Connected, and Google still honours the grant.
  bool get usable => connected && !needsReconnect;

  /// The picked calendar's Google id, which an event's roster records.
  final String? calendarId;

  /// Null until the admin picks a calendar.
  final String? calendarName;

  bool get ready => connected && !needsReconnect && calendarName != null;
}

/// 教會連結: the one link an admin puts at the top of everyone's home page,
/// e.g. the church website, giving page or a sign-up form.
@immutable
class ChurchLink {
  const ChurchLink({
    required this.title,
    this.body = '',
    required this.url,
    this.source,
    this.fetchMinute = defaultFetchMinute,
  });

  /// 04:30 on the church's clock.
  static const defaultFetchMinute = 4 * 60 + 30;

  final String title;
  final String body;

  /// Always `https`.
  final String url;

  /// A JSON URL fetched once a day for content that replaces [title],
  /// [body] and [url] while fresh. Set through the backend only.
  final String? source;

  /// When [source] is fetched: minutes after midnight in the church's time
  /// zone, in steps of 15.
  final int fetchMinute;

  /// Whether saving this over [saved] changes what is fetched or when, so
  /// the backend must set the source again. Without a source, the fetch
  /// time does not matter.
  bool changesSourceOf(ChurchLink? saved) =>
      source != saved?.source || (source != null && fetchMinute != saved?.fetchMinute);

  /// Whether [url] is an https URL with a host.
  static bool validUrl(String url) {
    final u = Uri.tryParse(url.trim());
    return u != null && u.scheme == 'https' && u.host.isNotEmpty;
  }

  @override
  bool operator ==(Object other) =>
      other is ChurchLink &&
      other.title == title &&
      other.body == body &&
      other.url == url &&
      other.source == source &&
      other.fetchMinute == fetchMinute;

  @override
  int get hashCode => Object.hash(title, body, url, source, fetchMinute);
}

/// Why fetching the content source failed.
enum LinkFetchError { timeout, tooLarge, badFormat, notToday, notHttps, http, network, unknown }

/// What the backend last fetched from the church link's content source
/// (settings/linkContent).
@immutable
class LinkContent {
  const LinkContent({
    required this.source,
    this.date,
    this.title = '',
    this.body = '',
    this.link,
    this.fetchedAt,
    this.error,
    this.errorStatus,
    this.errorAt,
  });

  /// The source this came from; content of an earlier source is ignored.
  final String source;

  /// The source's civil church date (`YYYY-MM-DD`); absent in error records.
  final String? date;
  final String title;
  final String body;
  final String? link;

  /// Last successful fetch.
  final DateTime? fetchedAt;

  /// The last attempt's failure, or null when it worked.
  final LinkFetchError? error;

  /// The HTTP status for [LinkFetchError.http].
  final int? errorStatus;
  final DateTime? errorAt;

  @override
  bool operator ==(Object other) =>
      other is LinkContent &&
      other.source == source &&
      other.date == date &&
      other.title == title &&
      other.body == body &&
      other.link == link &&
      other.fetchedAt == fetchedAt &&
      other.error == error &&
      other.errorStatus == errorStatus &&
      other.errorAt == errorAt;

  @override
  int get hashCode => Object.hash(source, date, title, body, link, fetchedAt, error, errorStatus, errorAt);
}

/// How the last webhook notice went.
enum WebhookDeliveryError { timeout, network, http }

@immutable
class WebhookDelivery {
  const WebhookDelivery({required this.ok, this.status, this.error, this.event, this.at});

  final bool ok;

  /// The receiver's HTTP status, when it answered.
  final int? status;
  final WebhookDeliveryError? error;

  /// `ping`, `calendar.created`, `roster.changed`, …
  final String? event;
  final DateTime? at;

  @override
  bool operator ==(Object other) =>
      other is WebhookDelivery &&
      other.ok == ok &&
      other.status == status &&
      other.error == error &&
      other.event == event &&
      other.at == at;

  @override
  int get hashCode => Object.hash(ok, status, error, event, at);
}

/// 外部通知: where the church's webhook goes and which changes it reports
/// (churches/{cid}/settings/webhook, written by the backend). The secret
/// is never here.
@immutable
class WebhookSettings {
  const WebhookSettings({required this.url, this.calendar = false, this.roster = false, this.lastDelivery});

  final String url;

  /// Calendar events created, changed or deleted.
  final bool calendar;

  /// Roster changes, a few minutes' worth in one notice.
  final bool roster;
  final WebhookDelivery? lastDelivery;

  @override
  bool operator ==(Object other) =>
      other is WebhookSettings &&
      other.url == url &&
      other.calendar == calendar &&
      other.roster == roster &&
      other.lastDelivery == lastDelivery;

  @override
  int get hashCode => Object.hash(url, calendar, roster, lastDelivery);
}

/// Someone moved over from the self-host version who has not signed in
/// yet. Their rosters point at [id] (their old uid) until they claim it by
/// signing in with [email], or an admin merges it into a member.
@immutable
class PendingMember {
  const PendingMember({
    required this.id,
    required this.name,
    this.email = '',
    this.role = Role.staff,
    this.groups = const {},
    this.zones = const [],
    this.mutedNotifications = const {},
  });

  final String id;
  final String name;
  final String email;
  final Role role;
  final Set<Group> groups;
  final List<Zone> zones;
  final Set<NotificationKind> mutedNotifications;

  @override
  bool operator ==(Object other) =>
      other is PendingMember &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.role == role &&
      setEquals(other.groups, groups) &&
      listEquals(other.zones, zones) &&
      setEquals(other.mutedNotifications, mutedNotifications);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    email,
    role,
    Object.hashAll(groups),
    Object.hashAll(zones),
    Object.hashAllUnordered(mutedNotifications),
  );
}

/// How long a notification stays in the 通知列表: NOTIFICATION_DAYS in
/// functions/src/notificationList.ts.
const notificationDays = Duration(days: 30);

/// One line of someone's 通知列表 (#89): a push the backend sent them,
/// also of a kind they muted, kept [notificationDays]. Written only by the
/// backend.
@immutable
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.churchId,
    required this.kind,
    required this.title,
    required this.body,
    required this.link,
    required this.at,
  });

  final String id;

  /// The church it is from: each church's list shows only its own.
  final String churchId;

  /// Null: a kind newer than this app.
  final NotificationKind? kind;
  final String title;
  final String body;

  /// The app route it opens in its church, as the push does.
  final String link;
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is NotificationItem &&
      other.id == id &&
      other.churchId == churchId &&
      other.kind == kind &&
      other.title == title &&
      other.body == body &&
      other.link == link &&
      other.at == at;

  @override
  int get hashCode => Object.hash(id, churchId, kind, title, body, link, at);
}

/// How many of [items] are unread: sent after their church's list was last
/// seen ([seen], by church ID; never seen: all of it), to the millisecond.
/// The number on the app icon counts every church's. Matches unreadCount in
/// functions/src/notificationList.ts (testdata/church_rules.json).
int unreadNotifications(Iterable<NotificationItem> items, Map<String, DateTime> seen) => items.where((n) {
  final s = seen[n.churchId];
  return s == null || n.at.millisecondsSinceEpoch > s.millisecondsSinceEpoch;
}).length;

/// How someone's request to join a church stands (申請加入, #88).
enum JoinRequestState { pending, rejected }

/// Someone without an invite asking to join (申請加入, #88), by uid: what
/// an admin sees to let them in or not. Written only by the backend.
@immutable
class JoinRequest {
  const JoinRequest({
    required this.uid,
    required this.name,
    this.email = '',
    this.note = '',
    required this.createdAt,
    this.rejectedAt,
  });

  final String uid;
  final String name;
  final String email;

  /// What they told the admin; may be empty.
  final String note;
  final DateTime createdAt;

  /// When an admin turned it down; null while waiting.
  final DateTime? rejectedAt;

  /// A request is gone after this many days, answered or not
  /// (JOIN_REQUEST_DAYS in functions/src/joinRequests.ts).
  static const days = 30;

  /// How a request asked [ageDays] days ago stands (testdata/church_rules.json,
  /// joinRequestState); null as if there were none.
  static JoinRequestState? standing(double ageDays, {required bool rejected}) {
    if (ageDays >= days) return null;
    return rejected ? JoinRequestState.rejected : JoinRequestState.pending;
  }

  /// How it stands at [now].
  JoinRequestState? stateAt(DateTime now) =>
      standing(now.difference(createdAt).inMilliseconds / Duration.millisecondsPerDay, rejected: rejectedAt != null);

  @override
  bool operator ==(Object other) =>
      other is JoinRequest &&
      other.uid == uid &&
      other.name == name &&
      other.email == email &&
      other.note == note &&
      other.createdAt == createdAt &&
      other.rejectedAt == rejectedAt;

  @override
  int get hashCode => Object.hash(uid, name, email, note, createdAt, rejectedAt);
}

/// One person in a move file, for 「這位是我」.
@immutable
class MovePerson {
  const MovePerson({required this.id, required this.name, this.email = ''});

  final String id;
  final String name;
  final String email;
}

/// What a move file would bring.
@immutable
class MovePreview {
  const MovePreview({
    required this.members,
    required this.rosters,
    this.services = const [],
    this.people = const [],
    this.skippedRosters = 0,
  });

  final int members;

  /// Roster days.
  final int rosters;
  final List<String> services;
  final List<MovePerson> people;

  /// Days in the file with no readable date or service.
  final int skippedRosters;
}

/// A pending member waiting for the signed-in person, found by their
/// verified email.
@immutable
class PendingClaim {
  const PendingClaim({required this.churchId, required this.churchName, required this.pendingId, required this.name});

  final String churchId;
  final String churchName;
  final String pendingId;

  /// Their name on that church's list.
  final String name;

  /// Remembered on the device when declined.
  String get key => '$churchId/$pendingId';
}
