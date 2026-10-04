/// Firestore document <-> domain model.
///
/// Field names are the contract with firestore.rules and the Cloud
/// Functions; docs/data-model.md lists them.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/day.dart';
import '../../domain/models.dart';

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
  homeName: data['homeName'] is String ? data['homeName'] as String : null,
  deletedAt: readTime(data['deletedAt']),
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
            ),
    ],
    mutedNotifications: {
      for (final name in prefs is Map ? _strings(prefs['muted']) : const <String>[])
        for (final kind in NotificationKind.values)
          if (kind.name == name) kind,
    },
    joinedAt: readTime(data['joinedAt']),
  );
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
    for (final z in m.zones) {'serviceType': z.serviceType, 'duties': z.duties},
  ],
  'zoneTypes': m.zoneTypes,
};

Json notificationPrefsToJson(Set<NotificationKind> muted) => {
  'muted': [
    for (final k in NotificationKind.values)
      if (muted.contains(k)) k.name,
  ],
};

EventTag? _event(Object? raw) {
  if (raw is! Map || raw['name'] is! String) return null;
  final color = raw['color'];
  return EventTag(name: raw['name'] as String, color: color is int ? color : 0);
}

Json _eventToJson(EventTag e) => {'name': e.name, 'color': e.color};

Service serviceFromJson(Json data) => Service(
  id: data['id'] as String,
  name: data['name'] as String? ?? '',
  weekday: (data['weekday'] as num?)?.toInt().clamp(1, 7) ?? DateTime.sunday,
  enabled: data['enabled'] as bool? ?? true,
  duties: _strings(data['duties']),
  events: [
    if (data['events'] is List)
      for (final e in data['events'] as List<dynamic>) ?_event(e),
  ],
);

Json serviceToJson(Service s) => {
  'id': s.id,
  'name': s.name,
  'weekday': s.weekday,
  'enabled': s.enabled,
  'duties': s.duties,
  'events': [for (final e in s.events) _eventToJson(e)],
};

ServiceSettings serviceSettingsFromJson(Json? data) {
  if (data == null) return const ServiceSettings(services: []);
  return ServiceSettings(
    services: [
      if (data['services'] is List)
        for (final s in data['services'] as List<dynamic>)
          if (s is Map && s['id'] is String) serviceFromJson(Map<String, dynamic>.from(s)),
    ],
    ids: _strings(data['ids']),
  );
}

/// Returns null for a document too broken to show (no type or date).
Roster? rosterFromJson(Json data) {
  final type = data['type'];
  final day = Day.tryParse(data['dateKey'] as String?);
  if (type is! String || type.isEmpty || day == null) return null;
  return Roster(
    type: type,
    day: day,
    duties: [
      if (data['duties'] is List)
        for (final d in data['duties'] as List<dynamic>)
          if (d is Map && d['role'] is String)
            Duty(
              role: d['role'] as String,
              people: _strings(d['people']),
              uids: {
                if (d['uids'] is Map)
                  for (final e in (d['uids'] as Map).entries)
                    if (e.key is String && e.value is String) e.key as String: e.value as String,
              },
            ),
    ],
    events: [
      if (data['events'] is List)
        for (final e in data['events'] as List<dynamic>) ?_event(e),
    ],
  );
}

Json rosterToJson(Roster r) => {
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
      },
  ],
  'events': [for (final e in r.events) _eventToJson(e)],
};

Invite inviteFromJson(String code, Json data) => Invite(
  code: code,
  churchId: data['cid'] as String? ?? '',
  churchName: data['churchName'] as String? ?? '',
  expiresAt: readTime(data['expiresAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  revoked: data['revoked'] as bool? ?? false,
  createdAt: readTime(data['createdAt']),
);

UserProfile profileFromJson(String uid, Json data) => UserProfile(
  uid: uid,
  name: data['name'] as String? ?? '',
  email: data['email'] as String? ?? '',
  locale: data['locale'] as String?,
);

CalendarSettings calendarSettingsFromJson(Json? data) => CalendarSettings(
  connected: data?['connected'] == true,
  needsReconnect: data?['needsReconnect'] == true,
  calendarName: data?['calendarName'] as String?,
);

DateTime _eventTime(String value, bool allDay) {
  if (allDay) {
    final d = Day.parse(value.substring(0, 10));
    return DateTime(d.year, d.month, d.day);
  }
  return DateTime.parse(value).toLocal();
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
    );
  } on FormatException {
    return null;
  }
}

Json calendarEventToJson(CalendarEvent e) {
  String time(DateTime t) => e.allDay ? Day(t.year, t.month, t.day).key : t.toUtc().toIso8601String();
  return {
    'id': ?e.id,
    'title': e.title,
    'start': time(e.start),
    'end': time(e.end),
    'allDay': e.allDay,
    'location': ?e.location,
    'description': ?e.description,
  };
}
