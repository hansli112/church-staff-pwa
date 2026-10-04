import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/export.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff_order.dart';

void main() {
  const sunday = Service(id: 'sunday', name: '主日崇拜', weekday: 7, duties: ['司會', '司琴']);
  const youth = Service(id: 'youth', name: '青年, "崇拜"', weekday: 6);
  final at = DateTime.utc(2026, 10, 4, 2, 30);

  ChurchSnapshot snapshot({List<Roster>? rosters}) => ChurchSnapshot(
    church: const Church(id: 'grace', name: '恩典堂', homeName: '恩典', logoUrl: 'https://x/logo.png'),
    services: const ServiceSettings(services: [sunday, youth], ids: ['sunday', 'youth', 'old']),
    members: [
      Member(
        uid: 'mei',
        name: '李美玉',
        email: 'mei@example.com',
        groups: const {Group.rosterEditors},
        zones: const [
          Zone(serviceType: 'sunday', duties: ['司琴']),
        ],
        joinedAt: DateTime.utc(2026, 9, 1),
      ),
      const Member(uid: 'pastor', name: '王牧師', role: Role.admin),
    ],
    pendingMembers: const [
      PendingMember(id: 'old-hao', name: '陳志豪', email: 'hao@example.com', groups: {Group.calendarEditors}),
    ],
    staffOrders: {
      'sunday': StaffOrder({
        '司琴': ['李美玉', '陳志豪'],
      }),
      'youth': StaffOrder(),
    },
    rosters:
        rosters ??
        [
          Roster(
            type: 'youth',
            day: Day(2026, 10, 3),
            duties: const [
              Duty(role: '司會', people: ['Amy "A"']),
            ],
          ),
          Roster(
            type: 'sunday',
            day: Day(2026, 10, 4),
            events: const [EventTag(name: '聖餐', color: 0)],
            duties: const [
              Duty(role: '司會', people: ['王牧師'], uids: {'王牧師': 'pastor'}),
              Duty(role: '招待', people: ['李美玉', '陳志豪']),
            ],
          ),
          Roster(
            type: 'sunday',
            day: Day(2025, 12, 28),
            duties: const [
              Duty(role: '司琴', people: []),
            ],
          ),
        ],
    calendar: const CalendarSettings(connected: true, calendarName: '教會行事曆'),
    link: const ChurchLink(title: '奉獻', url: 'https://grace.example/give', source: 'https://feed.example/a.json'),
    webhook: const WebhookSettings(url: 'https://n8n.example/hook', calendar: true),
  );

  group('CSV', () {
    test('starts with a BOM, so Excel reads Chinese', () {
      expect(exportCsv(snapshot()).codeUnitAt(0), 0xFEFF);
    });

    test('one row per duty, oldest day first, people joined with 、', () {
      final lines = exportCsv(snapshot()).substring(1).split('\r\n');
      expect(lines, [
        '日期,服事,服事項目,同工',
        '2025-12-28,主日崇拜,司琴,',
        '2026-10-03,"青年, ""崇拜""",司會,"Amy ""A"""',
        '2026-10-04,主日崇拜,司會,王牧師',
        '2026-10-04,主日崇拜,招待,李美玉、陳志豪',
        '',
      ]);
    });

    test('a church without rosters has only the header', () {
      expect(exportCsv(snapshot(rosters: const [])), '\uFEFF日期,服事,服事項目,同工\r\n');
    });
  });

  group('JSON', () {
    test('format, version and time come first', () {
      final j = exportJson(snapshot(), at);
      expect(j.keys.take(3), ['format', 'version', 'exportedAt']);
      expect(j['format'], 'martha-church-export');
      expect(j['version'], 1);
      expect(j['exportedAt'], '2026-10-04T02:30:00.000Z');
    });

    test('carries the church, services, members, orders, rosters, calendar, link and webhook', () {
      final j = jsonDecode(jsonEncode(exportJson(snapshot(), at))) as Map<String, dynamic>;
      expect(j['church'], {'id': 'grace', 'name': '恩典堂', 'homeName': '恩典', 'logoUrl': 'https://x/logo.png'});
      expect(j['services']['ids'], ['sunday', 'youth', 'old']);
      expect(j['services']['services'][0]['duties'], ['司會', '司琴']);
      expect(j['members'][1], {
        'uid': 'pastor',
        'name': '王牧師',
        'email': '',
        'role': 'admin',
        'groups': <String>[],
        'zones': <Object>[],
        'joinedAt': null,
      });
      expect(j['members'][0]['groups'], ['roster-editors']);
      expect(j['members'][0]['joinedAt'], '2026-09-01T00:00:00.000Z');
      expect(j['members'][0]['zones'], [
        {
          'serviceType': 'sunday',
          'duties': ['司琴'],
        },
      ]);
      expect(j['pendingMembers'], [
        {
          'id': 'old-hao',
          'name': '陳志豪',
          'email': 'hao@example.com',
          'role': 'staff',
          'groups': ['calendar-editors'],
          'zones': <Object>[],
        },
      ]);
      expect(j['staffOrders'], {
        'sunday': {
          '司琴': ['李美玉', '陳志豪'],
        },
      });
      expect((j['rosters'] as List).map((r) => r['id']), [
        '2025-12-28_sunday',
        '2026-10-03_youth',
        '2026-10-04_sunday',
      ]);
      expect(j['rosters'][2]['duties'][0], {
        'duty': '司會',
        'people': ['王牧師'],
        'uids': {'王牧師': 'pastor'},
      });
      expect(j['rosters'][2]['events'], [
        {'name': '聖餐', 'color': 0},
      ]);
      expect(j['calendar'], {'connected': true, 'calendarName': '教會行事曆'});
      expect(j['churchLink']['source'], 'https://feed.example/a.json');
      expect(j['webhook'], {
        'url': 'https://n8n.example/hook',
        'events': {'calendar': true, 'roster': false},
      });
    });

    test('holds no secrets', () {
      final text = jsonEncode(exportJson(snapshot(), at));
      for (final secret in ['secret', 'token', 'fcm', 'invite', 'whsec', 'refresh']) {
        expect(text.toLowerCase(), isNot(contains(secret)));
      }
    });

    test('a church with nothing optional', () {
      const bare = ChurchSnapshot(
        church: Church(id: 'c', name: '新教會'),
        services: ServiceSettings(services: [sunday], ids: ['sunday']),
      );
      final j = exportJson(bare, at);
      expect(j['rosters'], isEmpty);
      expect(j['members'], isEmpty);
      expect(j['calendar'], isNull);
      expect(j['churchLink'], isNull);
      expect(j['webhook'], isNull);
    });
  });

  test('the zip holds the JSON and the CSV', () {
    final zip = ZipDecoder().decodeBytes(exportZip(snapshot(), at));
    expect(zip.files.map((f) => f.name), ['martha-export.json', '服事表.csv']);
    final json = jsonDecode(utf8.decode(zip.findFile('martha-export.json')!.content)) as Map;
    expect(json['format'], 'martha-church-export');
    final csv = zip.findFile('服事表.csv')!.content;
    expect(csv.take(3), [0xEF, 0xBB, 0xBF], reason: 'the BOM survives');
    expect(utf8.decode(csv), contains('日期,服事,服事項目,同工'));
  });

  test('file name', () {
    expect(
      exportFileName(const Church(id: 'g', name: '恩典堂 台北/分堂'), DateTime(2026, 10, 4)),
      'martha-恩典堂_台北_分堂-2026-10-04.zip',
    );
  });
}
