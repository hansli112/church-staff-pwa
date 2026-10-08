/// 匯出資料: everything a church's admin can take with them, built from a
/// snapshot of the church. Pure: no Firebase, no I/O. The format is
/// docs/export-format.md.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'models.dart';
import 'staff_order.dart';

/// What the export is made from: what an admin can already read.
class ChurchSnapshot {
  const ChurchSnapshot({
    required this.church,
    required this.services,
    this.members = const [],
    this.pendingMembers = const [],
    this.staffOrders = const {},
    this.rosters = const [],
    this.calendar,
    this.link,
    this.webhook,
  });

  final Church church;
  final ServiceSettings services;
  final List<Member> members;

  /// Moved from self-host, not signed in yet. Rosters may point at them.
  final List<PendingMember> pendingMembers;

  /// By service ID.
  final Map<String, StaffOrder> staffOrders;

  /// Every saved roster, past ones too.
  final List<Roster> rosters;
  final CalendarSettings? calendar;
  final ChurchLink? link;
  final WebhookSettings? webhook;
}

const exportFormat = 'martha-church-export';

/// 2: 活動的服事表 (serviceId null, eventId, title, endDate).
const exportVersion = 2;
const exportJsonName = 'martha-export.json';
const exportCsvName = '服事表.csv';

/// Rosters oldest first; on one day, in the order of the services, then
/// events'. Not an event's roster cancelled with its event.
List<Roster> _ordered(ChurchSnapshot s) {
  final rank = {for (final (i, svc) in s.services.services.indexed) svc.id: i};
  return [
    for (final r in s.rosters)
      if (!(r.forEvent?.cancelled ?? false)) r,
  ]..sort((a, b) {
    final byDay = a.day.compareTo(b.day);
    int of(Roster r) => r.isEvent ? 1000 : rank[r.type] ?? 999;
    return byDay != 0 ? byDay : of(a).compareTo(of(b));
  });
}

/// The whole church as JSON. No push tokens, calendar grant, webhook
/// secret or invite codes: the snapshot never has them.
Map<String, Object?> exportJson(ChurchSnapshot s, DateTime exportedAt) => {
  'format': exportFormat,
  'version': exportVersion,
  'exportedAt': exportedAt.toUtc().toIso8601String(),
  'church': {
    'id': s.church.id,
    'name': s.church.name,
    'homeName': s.church.homeName,
    'logoUrl': s.church.logoUrl,
  },
  'services': {
    'services': [
      for (final svc in s.services.services)
        {
          'id': svc.id,
          'name': svc.name,
          'weekday': svc.weekday,
          'enabled': svc.enabled,
          'duties': svc.duties,
          'events': [
            for (final e in svc.events) {'name': e.name, 'color': e.color},
          ],
        },
    ],
    'ids': s.services.ids,
  },
  'members': [
    for (final m in [...s.members]..sort((a, b) => a.name.compareTo(b.name)))
      {
        'uid': m.uid,
        'name': m.name,
        'email': m.email,
        'role': m.role.name,
        'groups': [
          for (final g in Group.values)
            if (m.groups.contains(g)) g.id,
        ],
        'zones': [
          for (final z in m.zones) {'serviceType': z.serviceType, 'duties': z.duties},
        ],
        'joinedAt': m.joinedAt?.toUtc().toIso8601String(),
      },
  ],
  'pendingMembers': [
    for (final p in [...s.pendingMembers]..sort((a, b) => a.name.compareTo(b.name)))
      {
        'id': p.id,
        'name': p.name,
        'email': p.email,
        'role': p.role.name,
        'groups': [
          for (final g in Group.values)
            if (p.groups.contains(g)) g.id,
        ],
        'zones': [
          for (final z in p.zones) {'serviceType': z.serviceType, 'duties': z.duties},
        ],
      },
  ],
  'staffOrders': {
    for (final e in s.staffOrders.entries)
      if (e.value.rankingsByRole.isNotEmpty) e.key: e.value.rankingsByRole,
  },
  'rosters': [
    for (final r in _ordered(s))
      {
        'id': r.id,
        'date': r.day.key,
        'endDate': r.lastDay.key,
        'serviceId': r.isEvent ? null : r.type,
        'eventId': r.forEvent?.eventId,
        'title': r.forEvent?.title,
        'duties': [
          for (final d in r.duties) {'duty': d.role, 'people': d.people, 'uids': d.uids},
        ],
        'events': [
          for (final e in r.events) {'name': e.name, 'color': e.color},
        ],
      },
  ],
  'calendar': s.calendar == null || !s.calendar!.connected
      ? null
      : {'connected': true, 'calendarName': s.calendar!.calendarName},
  'churchLink': s.link == null
      ? null
      : {
          'title': s.link!.title,
          'body': s.link!.body,
          'url': s.link!.url,
          'source': s.link!.source,
          'fetchMinute': s.link!.fetchMinute,
        },
  'webhook': s.webhook == null
      ? null
      : {
          'url': s.webhook!.url,
          'events': {'calendar': s.webhook!.calendar, 'roster': s.webhook!.roster},
        },
};

String _csvField(String v) => v.contains(RegExp('[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// A roster's 服事 column: the service's name, or the event's title.
String _name(ChurchSnapshot s, Roster r) => r.forEvent?.title ?? s.services.byId(r.type)?.name ?? r.type;

/// One row per duty on each saved day: 日期, 服事, 服事項目, 同工 (several
/// people joined with 「、」). UTF-8 with a BOM so Excel reads the Chinese.
String exportCsv(ChurchSnapshot s) {
  final rows = <List<String>>[
    ['日期', '服事', '服事項目', '同工'],
    for (final r in _ordered(s))
      for (final d in r.duties) [r.day.key, _name(s, r), d.role, d.people.join('、')],
  ];
  return '\uFEFF${rows.map((row) => row.map(_csvField).join(',')).join('\r\n')}\r\n';
}

/// The zip an admin downloads: [exportJsonName] and [exportCsvName].
Uint8List exportZip(ChurchSnapshot s, DateTime exportedAt) {
  final json = utf8.encode(const JsonEncoder.withIndent('  ').convert(exportJson(s, exportedAt)));
  final csv = utf8.encode(exportCsv(s));
  final archive = Archive()
    ..add(ArchiveFile.bytes(exportJsonName, json))
    ..add(ArchiveFile.bytes(exportCsvName, csv));
  return ZipEncoder().encodeBytes(archive);
}

/// `martha-恩典堂-2026-10-04.zip`
String exportFileName(Church church, DateTime at) {
  final safe = church.name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  final d = '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  return 'martha-$safe-$d.zip';
}
