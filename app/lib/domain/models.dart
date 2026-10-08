/// Plain data types shared by the repositories, the state layer and the UI.
///
/// Nothing here imports Firebase: IDs are strings and times are [DateTime] or
/// [Day], so the data layer can move off Firestore without touching callers
/// (docs/design.md, 遷移預留).
library;

import 'package:flutter/foundation.dart';

import 'day.dart';

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

  /// Past this many characters some phones cut the home-screen name off;
  /// the most it may have is `TextLimits.homeName`.
  static const homeNameSafeLength = 6;

  /// How long a church its admin deleted can be restored (RESTORE_DAYS in
  /// functions/src/church.ts).
  static const restoreWindow = Duration(days: 30);

  bool get isActive => status == ChurchStatus.active;

  /// The last moment its admin can restore it; null unless deleted.
  DateTime? get restorableUntil => status == ChurchStatus.deleted ? deletedAt?.add(restoreWindow) : null;

  Church copyWith({String? name, ChurchStatus? status, String? logoUrl, String? Function()? homeName}) => Church(
    id: id,
    name: name ?? this.name,
    status: status ?? this.status,
    logoUrl: logoUrl ?? this.logoUrl,
    homeName: homeName == null ? this.homeName : homeName(),
    deletedAt: deletedAt,
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
  const Zone({required this.serviceType, this.duties = const []});

  final String serviceType;
  final List<String> duties;

  Zone copyWith({List<String>? duties}) => Zone(serviceType: serviceType, duties: duties ?? this.duties);

  @override
  bool operator ==(Object other) =>
      other is Zone && other.serviceType == serviceType && listEquals(other.duties, duties);

  @override
  int get hashCode => Object.hash(serviceType, Object.hashAll(duties));
}

/// Kinds of push notification a member can turn off per church.
enum NotificationKind { reminder, rosterChange, memberLeft }

@immutable
class Member {
  const Member({
    required this.uid,
    required this.name,
    this.email = '',
    this.role = Role.staff,
    this.groups = const {},
    this.zones = const [],
    this.mutedNotifications = const {},
    this.joinedAt,
  });

  final String uid;
  final String name;
  final String email;
  final Role role;
  final Set<Group> groups;
  final List<Zone> zones;
  final Set<NotificationKind> mutedNotifications;
  final DateTime? joinedAt;

  bool get isAdmin => role == Role.admin;

  bool inGroup(Group group) => isAdmin || groups.contains(group);

  /// The service types this member holds a zone in, in zone order. Stored
  /// as `zoneTypes` because the security rules cannot look inside [zones].
  List<String> get zoneTypes => [
    for (final type in {for (final zone in zones) zone.serviceType}) type,
  ];

  /// Whether this member may edit rosters of [serviceType].
  bool canEditRosters(String serviceType) =>
      isAdmin || (groups.contains(Group.rosterEditors) && zoneTypes.contains(serviceType));

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

  Member copyWith({
    String? name,
    Role? role,
    Set<Group>? groups,
    List<Zone>? zones,
    Set<NotificationKind>? mutedNotifications,
  }) => Member(
    uid: uid,
    name: name ?? this.name,
    email: email,
    role: role ?? this.role,
    groups: groups ?? this.groups,
    zones: zones ?? this.zones,
    mutedNotifications: mutedNotifications ?? this.mutedNotifications,
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

/// One service on one day.
@immutable
class Roster {
  const Roster({
    required this.type,
    required this.day,
    this.duties = const [],
    this.events = const [],
    this.saved = true,
  });

  /// Document ID: one roster per service per day.
  static String idFor(String type, Day day) => '${day.key}_$type';

  String get id => idFor(type, day);

  /// The service ID.
  final String type;
  final Day day;
  final List<Duty> duties;
  final List<EventTag> events;

  /// False for a roster that only exists on screen, built from the service
  /// template because nobody has edited that day yet.
  final bool saved;

  Roster copyWith({
    List<Duty>? duties,
    List<EventTag>? events,
    Day? day,
    bool? saved,
  }) => Roster(
    type: type,
    day: day ?? this.day,
    duties: duties ?? this.duties,
    events: events ?? this.events,
    saved: saved ?? this.saved,
  );

  /// Whether [uid] (or, for names without a uid, [name]) serves this day.
  List<String> dutiesOf({required String uid, required String name}) => [
    for (final duty in duties)
      if (duty.uids.values.contains(uid) || (duty.people.contains(name) && !duty.uids.containsKey(name))) duty.role,
  ];

  @override
  bool operator ==(Object other) =>
      other is Roster &&
      other.type == type &&
      other.day == day &&
      other.saved == saved &&
      listEquals(other.duties, duties) &&
      listEquals(other.events, events);

  @override
  int get hashCode => Object.hash(
    type,
    day,
    saved,
    Object.hashAll(duties),
    Object.hashAll(events),
  );
}

/// The global profile at users/{uid}.
@immutable
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    this.email = '',
    this.locale,
  });

  final String uid;
  final String name;
  final String email;

  /// BCP-47 tag such as `zh-Hant`, or null to follow the device.
  final String? locale;
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
  });

  final String code;
  final String churchId;
  final String churchName;
  final DateTime expiresAt;
  final bool revoked;
  final DateTime? createdAt;

  bool usableAt(DateTime now) => !revoked && now.isBefore(expiresAt);
}

/// One event on the church's Google Calendar.
@immutable
class CalendarEvent {
  const CalendarEvent({
    this.id,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.description,
  });

  final String? id;
  final String title;

  /// All-day events: midnight local of the first day; [end] is exclusive.
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? description;

  /// The local day the event starts on.
  Day get day => Day(start.year, start.month, start.day);

  /// The last local day the event covers. [end] is exclusive, so an event
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

  CalendarEvent copyWith({String? title, DateTime? start, DateTime? end, bool? allDay, String? location}) =>
      CalendarEvent(
        id: id,
        title: title ?? this.title,
        start: start ?? this.start,
        end: end ?? this.end,
        allDay: allDay ?? this.allDay,
        location: location ?? this.location,
        description: description,
      );
}

/// The days from [from] to [to] that [events] cover, each mapped to the day
/// the agenda lists its event under (the day it starts). A day covered by
/// several events points at the earliest of them.
Map<Day, Day> agendaAnchors(Iterable<CalendarEvent> events, {required Day from, required Day to}) {
  final anchors = <Day, Day>{};
  for (final e in events) {
    final days = e.daysWithin(from, to);
    if (days == null) continue;
    for (var d = days.first; !d.isAfter(days.last); d = d.addDays(1)) {
      final current = anchors[d];
      if (current == null || e.day.isBefore(current)) anchors[d] = e.day;
    }
  }
  return anchors;
}

/// churches/{cid}/settings/calendar, written by the backend.
@immutable
class CalendarSettings {
  const CalendarSettings({this.connected = false, this.needsReconnect = false, this.calendarName});

  final bool connected;
  final bool needsReconnect;

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

  /// 04:30 in Asia/Taipei.
  static const defaultFetchMinute = 4 * 60 + 30;

  final String title;
  final String body;

  /// Always `https`.
  final String url;

  /// A JSON URL fetched once a day for content that replaces [title],
  /// [body] and [url] while fresh. Set through the backend only.
  final String? source;

  /// When [source] is fetched: minutes after midnight, Asia/Taipei, in
  /// steps of 15.
  final int fetchMinute;

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
enum LinkFetchError { timeout, tooLarge, badFormat, notHttps, http, network, unknown }

/// What the backend last fetched from the church link's content source
/// (settings/linkContent).
@immutable
class LinkContent {
  const LinkContent({
    required this.source,
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
      other.title == title &&
      other.body == body &&
      other.link == link &&
      other.fetchedAt == fetchedAt &&
      other.error == error &&
      other.errorStatus == errorStatus &&
      other.errorAt == errorAt;

  @override
  int get hashCode => Object.hash(source, title, body, link, fetchedAt, error, errorStatus, errorAt);
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
  });

  final String id;
  final String name;
  final String email;
  final Role role;
  final Set<Group> groups;
  final List<Zone> zones;

  @override
  bool operator ==(Object other) =>
      other is PendingMember &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.role == role &&
      setEquals(other.groups, groups) &&
      listEquals(other.zones, zones);

  @override
  int get hashCode => Object.hash(id, name, email, role, Object.hashAll(groups), Object.hashAll(zones));
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
