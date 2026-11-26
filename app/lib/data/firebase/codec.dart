/// Firestore document <-> domain model.
///
/// Field names are the contract with firestore.rules and the Cloud
/// Functions; docs/data-model.md lists them.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/day.dart';
import '../../domain/family.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../domain/swap.dart';

typedef Json = Map<String, dynamic>;

DateTime? readTime(Object? value) => switch (value) {
  Timestamp t => t.toDate(),
  DateTime d => d,
  int ms => DateTime.fromMillisecondsSinceEpoch(ms),
  _ => null,
};

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final v in raw)
      if (v is String) v,
];

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

Church churchFromJson(String id, Json data, {String? logoUrl}) => Church(
  id: id,
  name: data['name'] as String? ?? '',
  status: _enumByName(
    ChurchStatus.values,
    data['status'],
    ChurchStatus.suspended,
  ),
  logoUrl: logoUrl,
  // Only an open church's is looked up (FirestoreChurchData.church).
  hasLogo:
      data['status'] == ChurchStatus.active.name &&
      data['logoVersion'] is String &&
      (data['logoVersion'] as String).isNotEmpty,
  homeName: data['homeName'] is String ? data['homeName'] as String : null,
  deletedAt: readTime(data['deletedAt']),
  timeZone: ChurchTimeZone.of(data['timeZone'] as String?),
  attendanceSince: Day.tryParse(data['attendanceSince'] as String?),
  takesJoinRequests: data['joinRequestsClosed'] != true,
);

/// Unknown roles, groups or broken zones are dropped rather than thrown:
/// one bad document must not break the whole member list.
Member memberFromJson(String uid, Json data) {
  final prefs = data['notificationPrefs'];
  return Member(
    uid: uid,
    name: data['name'] as String? ?? '',
    email: data['email'] as String? ?? '',
    role: _enumByName(Role.values, data['role'], Role.member),
    groups: {for (final id in _strings(data['groups'])) ?Group.byId(id)},
    zones: [
      if (data['zones'] is List)
        for (final z in data['zones'] as List<dynamic>)
          if (z is Map && z['serviceType'] is String)
            Zone(
              serviceType: z['serviceType'] as String,
              duties: _strings(z['duties']),
              smallGroups: _strings(z['smallGroups']),
            ),
    ],
    identities: _identitiesOf(data),
    smallGroups: _strings(data['smallGroups']).toSet(),
    mutedNotifications: {
      for (final name in prefs is Map ? _strings(prefs['muted']) : const <String>[])
        for (final kind in NotificationKind.values)
          if (kind.name == name) kind,
    },
    reminderTiming: _enumByName(
      ReminderTiming.values,
      prefs is Map ? prefs['reminderTiming'] : null,
      ReminderTiming.weekly,
    ),
    reminderHour: switch (prefs is Map ? prefs['reminderHour'] : null) {
      final int h when ReminderHours.valid(h) => h,
      _ => ReminderHours.usual,
    },
    reminderDays: switch (prefs is Map ? prefs['reminderDays'] : null) {
      final int d when ReminderDays.valid(d) => d,
      _ => ReminderDays.usual,
    },
    joinedAt: readTime(data['joinedAt']),
  );
}

/// A member doc's 身分. Whoever the rules let lead something
/// (`leadTypes`, `leadMinistries`, `leadSmallGroups`, `leadDuties`) with no 身分 stored
/// saying so still leads, after what they hold: a doc from before 身分, or
/// a 小組長 an app from before #85 saved without it, not knowing the kind
/// (testdata/church_rules.json, memberIdentities).
List<Identity> _identitiesOf(Json data) {
  final stored = [
    if (data['identities'] is List)
      for (final i in data['identities'] as List<dynamic>) ?Identity.fromJson(i),
  ];
  bool leadsService(String id) =>
      stored.any((i) => i == ServiceLead(id) || (i is PastorIdentity && (i.services?.contains(id) ?? false)));
  return [
    ...stored,
    for (final id in _strings(data['leadTypes']))
      if (!leadsService(id)) ServiceLead(id),
    for (final id in _strings(data['leadMinistries']))
      if (!stored.contains(MinistryLead(id))) MinistryLead(id),
    for (final id in _strings(data['leadSmallGroups']))
      if (!stored.contains(SmallGroupLead(id))) SmallGroupLead(id),
    for (final key in _strings(data['leadDuties']))
      if (DutyLead.parse(key) case final lead? when !stored.contains(lead)) lead,
  ];
}

/// The fields an admin edits. uid, email and joinedAt are left alone.
Json memberToJson(Member m) => {
  'uid': m.uid,
  'name': m.name,
  'role': m.role.name,
  'groups': [
    for (final g in Group.values)
      if (m.groups.contains(g)) g.id,
  ],
  'zones': [
    for (final z in m.zones) {'serviceType': z.serviceType, 'duties': z.duties, 'smallGroups': z.smallGroups},
  ],
  'zoneTypes': m.zoneTypes,
  // 身分 (#82), and what the rules read of them.
  'identities': [for (final i in m.identities) i.toJson()],
  'leadTypes': m.leadTypes,
  'leadMinistries': m.leadMinistries,
  'leadSmallGroups': m.leadSmallGroups,
  'leadDuties': m.leadDuties,
  'smallGroups': m.smallGroups.toList(),
};

/// churches/{cid}/smallGroups/{id} (#85).
SmallGroupDetails smallGroupFromJson(String id, Json data) => SmallGroupDetails(
  id: id,
  name: data['name'] as String? ?? '',
  service: data['service'] as String? ?? '',
  weekday: switch (data['weekday']) {
    final int w when w >= 1 && w <= 7 => w,
    _ => null,
  },
  every: data['every'] == 2 ? 2 : 1,
  startsOn: Day.tryParse(data['startsOn'] as String?),
  monthWeeks: _monthWeeks(data['monthWeeks']),
  order: _order(data),
);

/// What editSmallGroup takes of [g]; where it is, it keeps.
Json smallGroupToJson(SmallGroupDetails g) => {
  if (g.id.isNotEmpty) 'id': g.id,
  'name': g.name,
  'service': g.service,
  ...meetingTimeToJson(g.time),
};

/// A 聚會時間's weeks of each month, 1–4, as read.
List<int> _monthWeeks(Object? v) => [
  if (v is List)
    for (final w in v)
      if (w is int && w >= 1 && w <= Limits.monthWeeks) w,
];

/// A 聚會時間 as a 小組's, a 其他聚會's or a service's (with no weekday) doc has it.
MeetingTime meetingTimeFromJson(Json? data) => MeetingTime(
  weekday: switch (data?['weekday']) {
    final int w when w >= 1 && w <= 7 => w,
    _ => null,
  },
  every: data?['every'] == 2 ? 2 : 1,
  startsOn: Day.tryParse(data?['startsOn'] as String?),
  monthWeeks: _monthWeeks(data?['monthWeeks']),
);

/// [t]'s fields: when it meets monthly, its weeks; else every [MeetingTime.every] weeks.
Json meetingTimeToJson(MeetingTime t) => {
  'weekday': ?t.weekday,
  if (t.monthWeeks.isNotEmpty) 'monthWeeks': t.monthWeeks else if (t.weekday != null) 'every': t.every,
  if (t.weekday != null) 'startsOn': ?t.startsOn?.key,
};

/// churches/{cid}/gatherings/{id}: a 其他聚會.
Gathering gatheringFromJson(String id, Json data) => Gathering(
  id: id,
  name: data['name'] as String? ?? '',
  time: meetingTimeFromJson(data),
  order: _order(data),
);

/// Where a 小組 or a 其他聚會 is in its list, as dragged; null for one never placed.
int? _order(Json data) => switch (data['order']) {
  final int o => o,
  _ => null,
};

/// What saving [g] writes: not where it is, which only orderGatherings writes.
Json gatheringToJson(Gathering g) => {'name': g.name, ...meetingTimeToJson(g.time)};

/// attendance/{key} of a service: its 聚會時間 when not by its rosters;
/// every week was 每週都填人數 (#93), which older apps read.
MeetingTime? serviceTimeFromJson(Json? data) => switch (meetingTimeFromJson(data)) {
  final t when t.monthWeeks.isNotEmpty || t.every == 2 => MeetingTime(
    every: t.every,
    startsOn: t.startsOn,
    monthWeeks: t.monthWeeks,
  ),
  _ when data?['everyWeek'] == true => MeetingTime(startsOn: Day.tryParse(data?['startsOn'] as String?)),
  _ => null,
};

/// Who else fills in a group's 人數, attendance/{key}.fillers.
List<String> attendanceFillersFromJson(Json? data) => [
  if (data?['fillers'] is List)
    for (final u in data!['fillers'] as List<dynamic>)
      if (u is String) u,
];

/// attendance/{key} and its days (#85).
List<AttendancePause> attendancePausesFromJson(Json? data) => [
  if (data?['pauses'] is List)
    for (final p in data!['pauses'] as List<dynamic>)
      if (p is Map)
        if ((Day.tryParse(p['from'] as String?), Day.tryParse(p['until'] as String?)) case (final from?, final until?))
          AttendancePause(from: from, until: until),
];

Json attendancePausesToJson(List<AttendancePause> pauses) => {
  'pauses': [
    for (final p in pauses) {'from': p.from.key, 'until': p.until.key},
  ],
};

AttendanceDay? attendanceDayFromJson(Json data) {
  final together = [
    if (data['together'] is List)
      for (final k in data['together'] as List<dynamic>)
        if (k is String) k,
  ];
  return switch (data) {
    {'with': final String host} => AttendanceDay.joined(host),
    {'none': true} => AttendanceDay.none(together: together),
    {'count': final int n} => AttendanceDay.count(n, note: data['note'] as String? ?? '', together: together),
    _ => null,
  };
}

Json attendanceDayToJson(AttendanceDay d, String by) =>
    d.none ? {'none': true, 'by': by} : {'count': d.count, if (d.note.isNotEmpty) 'note': d.note, 'by': by};

MinistrySettings ministrySettingsFromJson(Json? data) => MinistrySettings(
  ministries: [
    if (data?['ministries'] is List)
      for (final m in data!['ministries'] as List<dynamic>)
        if (m is Map && m['id'] is String && m['name'] is String)
          // `duties` and `addedIn`, saved before 2026-11-26, mean nothing now.
          Ministry(id: m['id'] as String, name: m['name'] as String),
  ],
  ids: _strings(data?['ids']),
);

Json ministrySettingsToJson(MinistrySettings s) => {
  'ministries': [
    for (final m in s.ministries)
      {
        'id': m.id,
        'name': m.name,
      },
  ],
  'ids': s.ids,
};

ChurchLink? churchLinkFromJson(Json? data) {
  final title = data?['title'];
  final url = data?['url'];
  if (title is! String || url is! String) return null;
  return ChurchLink(
    title: title,
    body: data!['body'] as String? ?? '',
    url: url,
    source: data['source'] as String?,
    fetchMinute: (data['fetchMinute'] as num?)?.toInt() ?? ChurchLink.defaultFetchMinute,
  );
}

LinkFetchError? linkFetchErrorFromName(Object? name) {
  if (name == null) return null;
  for (final e in LinkFetchError.values) {
    if (e.name == name) return e;
  }
  return LinkFetchError.unknown;
}

LinkContent? linkContentFromJson(Json? data) {
  final source = data?['source'];
  if (source is! String) return null;
  return LinkContent(
    source: source,
    date: data!['date'] as String?,
    title: data['title'] as String? ?? '',
    body: data['body'] as String? ?? '',
    link: data['link'] as String?,
    fetchedAt: readTime(data['fetchedAt']),
    error: linkFetchErrorFromName(data['error']),
    errorStatus: (data['errorStatus'] as num?)?.toInt(),
    errorAt: readTime(data['errorAt']),
  );
}

/// The fields the app writes; source and fetchMinute belong to the backend.
Json churchLinkToJson(ChurchLink link) => {'title': link.title, 'body': link.body, 'url': link.url};

WebhookDelivery? webhookDeliveryFromJson(Object? raw) {
  if (raw is! Map) return null;
  return WebhookDelivery(
    ok: raw['ok'] == true,
    status: (raw['status'] as num?)?.toInt(),
    error: _enumByNameOrNull(WebhookDeliveryError.values, raw['error']),
    event: raw['event'] as String?,
    at: readTime(raw['at']),
  );
}

T? _enumByNameOrNull<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

WebhookSettings? webhookFromJson(Json? data) {
  final url = data?['url'];
  if (url is! String) return null;
  final events = data!['events'];
  return WebhookSettings(
    url: url,
    calendar: events is Map && events['calendar'] == true,
    roster: events is Map && events['roster'] == true,
    lastDelivery: webhookDeliveryFromJson(data['lastDelivery']),
  );
}

PendingMember pendingMemberFromJson(String id, Json data) {
  final m = memberFromJson(id, data);
  return PendingMember(
    id: id,
    name: m.name,
    email: m.email,
    role: m.role,
    groups: m.groups,
    zones: m.zones,
    smallGroups: m.smallGroups,
    mutedNotifications: m.mutedNotifications,
  );
}

/// A request without its time is as old as can be: gone.
JoinRequest joinRequestFromJson(String uid, Json data) => JoinRequest(
  uid: uid,
  name: data['name'] as String? ?? '',
  email: data['email'] as String? ?? '',
  note: data['note'] as String? ?? '',
  createdAt: readTime(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  rejectedAt: readTime(data['rejectedAt']),
);

ClaimAsk claimAskFromJson(String uid, Json data) => ClaimAsk(
  uid: uid,
  name: data['name'] as String? ?? '',
  pendingId: data['pendingId'] as String? ?? '',
  pendingName: data['pendingName'] as String? ?? '',
);

/// A 家人 household as functions/src/family.ts keeps it.
Household householdFromJson(String id, Json data) {
  List<String> ids(Object? v) => [for (final x in v is List ? v : const []) ?(x is String ? x : null)];
  Map<String, String> names(Object? v) => {
    if (v is Map)
      for (final e in v.entries)
        if (e.key is String && e.value is String) e.key as String: e.value as String,
  };
  return Household(
    id: id,
    people: ids(data['people']),
    noAccount: ids(data['noAccount']),
    invited: ids(data['invited']),
    invitedBy: names(data['invitedBy']),
    names: names(data['names']),
  );
}

/// Those functions/src/family.ts familyCandidates gives.
List<FamilyCandidate> familyCandidatesFromJson(Object? people) => [
  for (final p in people is List ? people : const [])
    if (p is Map && p['id'] is String)
      FamilyCandidate(id: p['id'] as String, name: p['name'] as String? ?? '', account: p['account'] == true),
];

/// A pending member's duties as functions/src/claim.ts servesOf gives them.
List<ClaimServe> claimServesFromJson(Object? serves) => [
  for (final s in serves is List ? serves : const [])
    if (s is Map)
      ClaimServe(
        day: Day.tryParse(s['dateKey'] as String?),
        service: s['service'] as String? ?? '',
        duty: s['duty'] as String? ?? '',
      ),
];

Json notificationPrefsToJson(Set<NotificationKind> muted) => {'muted': mutedToJson(muted)};

/// `notificationPrefs.muted`.
List<String> mutedToJson(Set<NotificationKind> muted) => [
  for (final k in NotificationKind.values)
    if (muted.contains(k)) k.name,
];

EventTag? _event(Object? raw) {
  if (raw is! Map || raw['name'] is! String) return null;
  final color = raw['color'];
  return EventTag(name: raw['name'] as String, color: color is int ? color : 0);
}

Json _eventToJson(EventTag e) => {'name': e.name, 'color': e.color};

Service serviceFromJson(Json data) =>
    Service(
      id: data['id'] as String,
      name: data['name'] as String? ?? '',
      weekdays: const [],
      duties: _strings(data['duties']),
      events: [
        if (data['events'] is List)
          for (final e in data['events'] as List<dynamic>) ?_event(e),
      ],
      manyDuties: data['manyDuties'] is List ? _strings(data['manyDuties']) : null,
    ).meetingOn(
      _weekdays(data),
      every: data['every'] == 2 ? 2 : 1,
      startsOn: Day.tryParse(data['startsOn'] as String?),
      monthWeeks: _monthWeeks(data['monthWeeks']),
    );

/// A service's days: `weekdays` when it meets on more than one, else
/// `weekday` alone, as older apps wrote and still read (the first of them).
List<int> _weekdays(Json data) {
  final many = {
    if (data['weekdays'] is List)
      for (final d in data['weekdays'] as List)
        if (d is num && d >= 1 && d <= 7) d.toInt(),
  };
  if (many.isNotEmpty) return [...many]..sort();
  return [(data['weekday'] as num?)?.toInt().clamp(1, 7) ?? DateTime.sunday];
}

/// Whether any of [services] meets on several days: settings/services
/// says so (`severalDays`), so firestore.rules turns away an older app's
/// write of the list, which would lose their `weekdays`.
bool severalDays(List<Service> services) => services.any((s) => s.weekdays.length > 1);

/// Whether any of [services] meets every other week or on some weeks of
/// each month: settings/services says so (`repeats`), as [severalDays].
bool repeats(List<Service> services) => services.any((s) => s.repeats);

Json serviceToJson(Service s) => {
  'id': s.id,
  'name': s.name,
  'weekday': s.weekdays.first,
  if (s.weekdays.length > 1) 'weekdays': s.weekdays,
  if (s.monthWeeks.isNotEmpty)
    'monthWeeks': s.monthWeeks
  else if (s.every == 2) ...{
    'every': 2,
    'startsOn': ?s.startsOn?.key,
  },
  // Older apps and editService still read it: a service turned off
  // (停用) before 聚會 could be deleted.
  'enabled': true,
  'duties': s.duties,
  'events': [for (final e in s.events) _eventToJson(e)],
  'manyDuties': ?s.manyDuties,
};

ServiceSettings serviceSettingsFromJson(Json? data) {
  if (data == null) return const ServiceSettings(services: []);
  return ServiceSettings(
    services: [
      if (data['services'] is List)
        for (final s in data['services'] as List<dynamic>)
          // One turned off (停用) is as good as deleted: it goes at the next save.
          if (s is Map && s['id'] is String && s['enabled'] != false) serviceFromJson(Map<String, dynamic>.from(s)),
    ],
    ids: _strings(data['ids']),
  );
}

List<Duty> _duties(Object? raw) => [
  if (raw is List)
    for (final d in raw)
      if (d is Map && d['role'] is String)
        Duty(
          role: d['role'] as String,
          people: _strings(d['people']),
          uids: {
            if (d['uids'] is Map)
              for (final e in (d['uids'] as Map).entries)
                if (e.key is String && e.value is String) e.key as String: e.value as String,
          },
          groups: {
            if (d['groups'] is Map)
              for (final e in (d['groups'] as Map).entries)
                if (e.key is String && e.value is String) e.key as String: e.value as String,
          },
        ),
];

/// Returns null for a document too broken to show (no type or date, or an
/// event's roster with no event).
Roster? rosterFromJson(Json data) {
  final day = Day.tryParse(data['dateKey'] as String?);
  if (day == null) return null;
  if (data['kind'] == 'event') {
    final eventId = data['eventId'];
    if (eventId is! String || eventId.isEmpty) return null;
    final last = Day.tryParse(data['endDateKey'] as String?);
    return Roster(
      type: '',
      day: day,
      duties: _duties(data['duties']),
      forEvent: RosterEvent(
        eventId: eventId,
        title: data['title'] as String? ?? '',
        lastDay: last == null || last.isBefore(day) ? day : last,
        cancelled: data['cancelledAt'] != null,
        calendarId: data['calendarId'] as String?,
        recurringEventId: data['recurringEventId'] as String?,
        originalStart: data['originalStart'] as String?,
        group: switch (data['group']) {
          final String g when g.isNotEmpty => g,
          _ => null,
        },
      ),
    );
  }
  final type = data['type'];
  if (type is! String || type.isEmpty) return null;
  return Roster(
    type: type,
    day: day,
    duties: _duties(data['duties']),
    events: [
      if (data['events'] is List)
        for (final e in data['events'] as List<dynamic>) ?_event(e),
    ],
    noService: data['noService'] == true,
  );
}

/// An event's roster has no type: app versions from before 活動的服事表
/// read it as broken and leave it out. Only the backend writes
/// cancelledAt.
Json rosterToJson(Roster r) => {
  if (r.forEvent case final e?) ...{
    'kind': 'event',
    'eventId': e.eventId,
    'title': e.title,
    'endDateKey': e.lastDay.key,
    // Written back as read: the rules let the app change none of them.
    'calendarId': ?e.calendarId,
    'recurringEventId': ?e.recurringEventId,
    'originalStart': ?e.originalStart,
    'group': ?e.group,
  } else
    'type': r.type,
  'dateKey': r.day.key,
  'duties': [
    for (final d in r.duties)
      {
        'role': d.role,
        'people': d.people,
        'uids': {
          for (final e in d.uids.entries)
            if (d.people.contains(e.key)) e.key: e.value,
        },
        // 服事交給小組: only when there is one, so the days look as they did.
        if (d.groups.keys.any(d.people.contains))
          'groups': {
            for (final e in d.groups.entries)
              if (d.people.contains(e.key)) e.key: e.value,
          },
      },
  ],
  'events': [for (final e in r.events) _eventToJson(e)],
  if (r.noService) 'noService': true,
};

Invite inviteFromJson(String code, Json data) => Invite(
  code: code,
  churchId: data['cid'] as String? ?? '',
  churchName: data['churchName'] as String? ?? '',
  expiresAt: readTime(data['expiresAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  revoked: data['revoked'] as bool? ?? false,
  createdAt: readTime(data['createdAt']),
  zoneTypes: [
    if (data['zoneTypes'] is List)
      for (final t in data['zoneTypes'] as List<dynamic>)
        if (t is String) t,
  ],
);

UserProfile profileFromJson(String uid, Json data) => UserProfile(
  uid: uid,
  name: data['name'] as String? ?? '',
  email: data['email'] as String? ?? '',
  locale: data['locale'] as String?,
  appLocale: data['appLocale'] as String?,
  photoAiConsent: data['photoAiConsentAt'] != null,
  seenOn: data['seenOn'] as String?,
  notificationsSeen: {
    if (data['notificationsSeenAt'] case final Map<dynamic, dynamic> seen)
      for (final e in seen.entries)
        if ((e.key, readTime(e.value)) case (final String cid, final DateTime at)) cid: at,
  },
);

/// users/{uid}/notifications/{id}: written by functions/src/push.ts.
NotificationItem notificationFromJson(String id, Json data) => NotificationItem(
  id: id,
  churchId: data['cid'] as String? ?? '',
  kind: NotificationKind.values.asNameMap()[data['kind']],
  title: data['title'] as String? ?? '',
  body: data['body'] as String? ?? '',
  link: data['link'] as String? ?? '/home',
  at: readTime(data['at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
);

CalendarSettings calendarSettingsFromJson(Json? data) => CalendarSettings(
  connected: data?['connected'] == true,
  needsReconnect: data?['needsReconnect'] == true,
  calendarName: data?['calendarName'] as String?,
  calendarId: data?['calendarId'] as String?,
  revision: switch (data?['updatedAt']) {
    Timestamp stamp => '${stamp.seconds}:${stamp.nanoseconds}',
    _ => null,
  },
);

/// A timed event's time comes on the church's clock with its offset
/// (functions/src/calendar.ts `inZone`): the clock's reading is the time.
final _onChurchClock = RegExp(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?)([+-]\d{2}:\d{2})$');

DateTime _eventTime(String value, bool allDay) {
  if (allDay) return Day.parse(value.substring(0, 10)).midnight;
  final m = _onChurchClock.firstMatch(value);
  if (m == null) throw const FormatException("Calendar time requires the church's offset");
  return DateTime.parse('${m[1]}Z');
}

CalendarEvent? calendarEventFromJson(Object? raw) {
  if (raw is! Map || raw['title'] is! String || raw['start'] is! String || raw['end'] is! String) return null;
  final allDay = raw['allDay'] == true;
  try {
    return CalendarEvent(
      id: raw['id'] as String?,
      title: raw['title'] as String,
      start: _eventTime(raw['start'] as String, allDay),
      end: _eventTime(raw['end'] as String, allDay),
      allDay: allDay,
      location: raw['location'] as String?,
      description: raw['description'] as String?,
      recurringEventId: raw['recurringEventId'] as String?,
      originalStart: raw['originalStart'] as String?,
      group: switch (raw['group']) {
        final String g when g.isNotEmpty => g,
        _ => null,
      },
      googleOnly: raw['googleOnly'] == true,
      colorId: switch (raw['colorId']) {
        final String c when c.isNotEmpty => c,
        _ => null,
      },
    );
  } on FormatException {
    return null;
  }
}

/// Times go on the church's clock without an offset: the backend reads them
/// in the church's time zone.
Json calendarEventToJson(CalendarEvent e) {
  String time(DateTime t) => e.allDay ? Day(t.year, t.month, t.day).key : t.toIso8601String().substring(0, 19);
  return {
    'id': ?e.id,
    'title': e.title,
    'start': time(e.start),
    'end': time(e.end),
    'allDay': e.allDay,
    'location': ?e.location,
    'description': ?e.description,
    // Whose it is (#84): '' the church's.
    'group': e.group ?? '',
    // Null: grey, none of its own.
    'colorId': e.colorId,
  };
}

/// unavailable/{uid} (#91): `spans`, each {from, to, note}. Stretches it
/// cannot read are left out.
UnavailableDays unavailableDaysFromJson(Map<String, dynamic>? data) {
  final spans = <UnavailableSpan>[];
  for (final s in (data?['spans'] as List?) ?? const []) {
    if (s is! Map) continue;
    final (from, to) = (Day.tryParse(s['from'] as String?), Day.tryParse(s['to'] as String?));
    if (from == null || to == null || to.isBefore(from)) continue;
    spans.add(UnavailableSpan(from, to, note: s['note'] is String ? s['note'] as String : ''));
  }
  return UnavailableDays(spans..sort((a, b) => a.from.compareTo(b.from)));
}

/// The first day of month [key] (`YYYY-MM`), if it is one.
Day? _monthOf(Object? key) => key is String && key.length == 7 ? Day.tryParse('$key-01') : null;

/// What 通知同工填 asked of a member, from their unavailable/{uid}; null when
/// never asked.
UnavailableAsked? unavailableAskedFromJson(Map<String, dynamic>? data) {
  final asked = data?['asked'];
  if (asked is! Map) return null;
  final (at, from, to) = ((asked['at'] as Timestamp?)?.toDate(), _monthOf(asked['from']), _monthOf(asked['to']));
  if (at == null || from == null || to == null) return null;
  return UnavailableAsked(at: at, from: from, to: to, sentAt: (data?['sentAt'] as Timestamp?)?.toDate());
}

/// A service's last 通知同工填 from unavailableAsks/{type}, with when each
/// last answered ([answeredAt]) by
/// uid; null when never asked, or asked before whom it told was kept.
UnavailableRound? unavailableRoundFromJson(Map<String, dynamic>? ask, Map<String, DateTime?> answeredAt) {
  final told = ask?['told'];
  final (at, from, to) = ((ask?['at'] as Timestamp?)?.toDate(), _monthOf(ask?['from']), _monthOf(ask?['to']));
  if (told is! List || at == null || from == null || to == null) return null;
  final uids = told.whereType<String>().toList();
  return UnavailableRound(
    at: at,
    from: from,
    to: to,
    told: uids,
    sent: {
      for (final uid in uids)
        if (sentSince(answeredAt[uid], at)) uid,
    },
  );
}

Map<String, Object> unavailableDaysToJson(UnavailableDays days) => {
  'spans': [
    for (final s in days.spans) {'from': s.from.key, 'to': s.to.key, 'note': s.note},
  ],
};

/// swapRequests/{id} (#92); null when it cannot be read as one.
SwapRequest? swapRequestFromJson(String id, Map<String, dynamic> data) {
  final kind = SwapKind.values.asNameMap()[data['kind']];
  final day = Day.tryParse(data['dateKey'] as String?);
  if (kind == null ||
      day == null ||
      data['serviceId'] is! String ||
      data['duty'] is! String ||
      data['from'] is! String) {
    return null;
  }
  List<String> strings(Object? v) => [
    for (final x in (v as List?) ?? const [])
      if (x is String) x,
  ];
  return SwapRequest(
    id: id,
    kind: kind,
    serviceId: data['serviceId'] as String,
    day: day,
    duty: data['duty'] as String,
    from: data['from'] as String,
    fromName: data['fromName'] as String? ?? '',
    asked: strings(data['asked']),
    passed: strings(data['passed']),
    to: data['to'] as String?,
    toName: data['toName'] as String?,
    toDay: Day.tryParse(data['toDateKey'] as String?),
    status: SwapStatus.values.asNameMap()[data['status']] ?? SwapStatus.voided,
    taker: data['taker'] as String?,
    takerName: data['takerName'] as String?,
  );
}

RosterNote rosterNoteFromJson(Json j) => RosterNote(
  text: j['text'] is String ? j['text'] as String : '',
  files: [
    for (final f in (j['files'] is List ? j['files'] as List : const []))
      if (f is Map && f['id'] is String && f['url'] is String)
        NoteFile(
          id: f['id'] as String,
          name: f['name'] is String ? f['name'] as String : f['id'] as String,
          type: f['type'] is String ? f['type'] as String : '',
          size: f['size'] is num ? (f['size'] as num).toInt() : 0,
          url: f['url'] as String,
        ),
  ],
);
