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
  }) => Church(
    id: id,
    name: name ?? this.name,
    status: status ?? this.status,
    logoUrl: logoUrl ?? this.logoUrl,
    homeName: homeName == null ? this.homeName : homeName(),
    deletedAt: deletedAt,
    timeZone: timeZone ?? this.timeZone,
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
enum NotificationKind { reminder, rosterChange, memberLeft }

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
  final Set<NotificationKind> mutedNotifications;
  final ReminderTiming reminderTiming;
  final DateTime? joinedAt;

  /// 管理員, or a whole church's 牧者: role admin as stored, which the rules
  /// read, or as their 身分 say.
  bool get isAdmin =>
      role == Role.admin || _identities.any((i) => i is AdminIdentity || (i is PastorIdentity && i.wholeChurch));

  /// Their 身分 (#82). A member doc from before them has none stored: an
  /// admin is then 管理員, and roster-editors 行政, as the rules read it.
  List<Identity> get identities => _identities.isNotEmpty
      ? _identities
      : [
          if (isAdmin) const AdminIdentity(),
          if (!isAdmin && groups.contains(Group.rosterEditors)) const OfficeIdentity(),
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

  /// Whether they lead anything, so pick people and add 同工.
  bool get leads => leadTypes.isNotEmpty || leadMinistries.isNotEmpty;

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
      mutedNotifications: mutedNotifications,
      reminderTiming: reminderTiming,
      joinedAt: joinedAt,
    );
  }

  /// In [group]: admins hold every one, 行政 both.
  bool inGroup(Group group) => isAdmin || groups.contains(group) || _identities.contains(const OfficeIdentity());

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
      setEquals(ministries, other.ministries);

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

  /// Whether this member is a 同工 of [group]: in its 牧區, or one of the
  /// 事工's.
  bool isIn(ChurchGroup group) => switch (group) {
    ServiceGroup(:final id) => zoneTypes.contains(id),
    MinistryGroup(:final id) => ministries.contains(id),
  };

  /// This member added to [group] ([member] true; a service with [duties])
  /// or taken out, as setGroupMember writes it.
  Member inGroupAs(ChurchGroup group, {required bool member, List<String> duties = const []}) => switch (group) {
    ServiceGroup(:final id) => copyWith(
      zones: [
        for (final z in zones)
          if (z.serviceType != id) z,
        if (member) zones.where((z) => z.serviceType == id).firstOrNull ?? Zone(serviceType: id, duties: duties),
      ],
    ),
    MinistryGroup(:final id) => copyWith(ministries: member ? {...ministries, id} : ({...ministries}..remove(id))),
  };

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
  });

  final String eventId;
  final String title;

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
  );

  @override
  bool operator ==(Object other) =>
      other is RosterEvent &&
      other.eventId == eventId &&
      other.title == title &&
      other.lastDay == lastDay &&
      other.cancelled == cancelled &&
      other.calendarId == calendarId &&
      other.recurringEventId == recurringEventId &&
      other.originalStart == originalStart;

  @override
  int get hashCode => Object.hash(eventId, title, lastDay, cancelled, calendarId, recurringEventId, originalStart);
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

/// Whether [after] is [before] with only the duties named in [roles]
/// changed, added or taken off: what a 事工's 負責人 may do to a day
/// (functions/src/ledDuties.ts).
bool changesOnlyDuties(Roster before, Roster after, Set<String> roles) {
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

  UserProfile copyWith({String? appLocale, bool? photoAiConsent}) => UserProfile(
    uid: uid,
    name: name,
    email: email,
    locale: locale,
    appLocale: appLocale ?? this.appLocale,
    photoAiConsent: photoAiConsent ?? this.photoAiConsent,
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
  }) : start = churchCivilTime(start),
       end = churchCivilTime(end);

  final String? id;
  final String title;

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
  );

  CalendarEvent copyWith({
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? location,
    String? description,
  }) => CalendarEvent(
    id: id,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    allDay: allDay ?? this.allDay,
    location: location ?? this.location,
    description: description ?? this.description,
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
