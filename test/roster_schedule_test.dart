import 'dart:convert';

import 'package:church_staff_pwa/core/config/church_config.dart';
import 'package:church_staff_pwa/core/config/default_church_config.dart';
import 'package:church_staff_pwa/core/time/church_time.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/roster_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void configure({
  int weekday = 3,
  bool enabled = true,
  String zone = 'Asia/Taipei',
}) {
  ChurchConfig.current = ChurchConfig.fromJson({
    ...jsonDecode(defaultChurchConfigJson) as Map<String, dynamic>,
    'timeZone': zone,
    'services': [
      {
        'id': 'midweek',
        'label': '週間',
        'name': '週間聚會',
        'weekday': weekday,
        'enabled': enabled,
      },
    ],
  });
}

List<ServiceRoster> plan(
  DateTime now, {
  List<ServiceRoster> existing = const [],
}) => planQuarterRosters(
  now: now,
  types: ServiceType.values,
  templates: {
    const ServiceType('midweek'): ['招待'],
  },
  existing: existing,
);

void main() {
  late ChurchConfig previous;
  setUp(() => previous = ChurchConfig.current);
  tearDown(() => ChurchConfig.current = previous);

  test(
    'different configured weekdays read the same complete transaction week',
    () {
      const type = ServiceType('midweek');
      final friday = rosterWeekDocumentIds(type, DateTime.utc(2026, 10, 2));
      final sunday = rosterWeekDocumentIds(type, DateTime.utc(2026, 10, 4));
      expect(friday, sunday);
      expect(friday, [
        '20260928_midweek',
        '20260929_midweek',
        '20260930_midweek',
        '20261001_midweek',
        '20261002_midweek',
        '20261003_midweek',
        '20261004_midweek',
      ]);
      expect(friday.toSet(), hasLength(7));
    },
  );

  test(
    'transaction week IDs remain stable across year and device-zone boundaries',
    () {
      const type = ServiceType('midweek');
      final local = rosterWeekDocumentIds(type, DateTime(2027, 1, 1));
      final utc = rosterWeekDocumentIds(type, DateTime.utc(2027, 1, 3));
      expect(local, utc);
      expect(local.first, '20261228_midweek');
      expect(local.last, '20270103_midweek');
      expect(
        rosterDocumentId(type, DateTime.utc(2027, 1, 1)),
        '20270101_midweek',
      );
    },
  );

  test('configured weekday is honored for every day of the week', () {
    for (var weekday = 1; weekday <= 7; weekday++) {
      configure(weekday: weekday);
      final result = plan(DateTime.utc(2026, 10, 1));
      expect(result, isNotEmpty);
      expect(result.map((r) => r.date.weekday), everyElement(weekday));
      expect(
        result.every((r) => !r.date.isBefore(DateTime.utc(2026, 10, 1))),
        isTrue,
      );
      expect(result.map((r) => r.type.name), everyElement('midweek'));
      expect(result.first.serviceName, '週間聚會');
      expect(result.first.duties.single.people, ['待定']);
      expect(result.first.id, endsWith('_midweek'));
    }
  });

  test(
    'disabled gathering creates nothing but old rosters remain unchanged',
    () {
      configure(enabled: false);
      final old = ServiceRoster(
        id: 'old',
        date: DateTime.utc(2026, 10, 7),
        type: const ServiceType('midweek'),
        serviceName: '舊名稱',
        duties: [],
      );
      expect(plan(DateTime.utc(2026, 10, 1), existing: [old]), isEmpty);
      expect(old.serviceName, '舊名稱');
    },
  );

  test(
    'changing weekday does not move or duplicate an already scheduled week',
    () {
      configure(weekday: 5);
      final existing = ServiceRoster(
        id: '20261007_midweek',
        date: DateTime.utc(2026, 10, 7),
        type: const ServiceType('midweek'),
        serviceName: '舊名稱',
        duties: [
          RosterEntry(role: '招待', people: ['Test Person']),
        ],
      );
      final result = plan(DateTime.utc(2026, 10, 1), existing: [existing]);
      expect(
        result.map((r) => ChurchTime.dateKey(r.date)),
        isNot(contains('2026-10-09')),
      );
      expect(existing.date, DateTime.utc(2026, 10, 7));
      expect(existing.duties.single.people, ['Test Person']);
      expect(result.map((r) => r.date), contains(DateTime.utc(2026, 10, 16)));
    },
  );

  test('week crossing quarter boundary is not regenerated', () {
    configure(weekday: 5);
    final existing = ServiceRoster(
      id: '20260930_midweek',
      date: DateTime.utc(2026, 9, 30),
      type: const ServiceType('midweek'),
      serviceName: '週間',
      duties: [],
    );
    expect(
      plan(DateTime.utc(2026, 10, 1), existing: [existing]).first.date,
      DateTime.utc(2026, 10, 9),
    );
  });

  test('current quarter plus next quarter only in the last month', () {
    expect(
      rosterQuarterEnd(DateTime.utc(2026, 1, 10)),
      DateTime.utc(2026, 3, 31),
    );
    expect(
      rosterQuarterEnd(DateTime.utc(2026, 3, 10)),
      DateTime.utc(2026, 6, 30),
    );
    expect(
      rosterQuarterEnd(DateTime.utc(2026, 12, 10)),
      DateTime.utc(2027, 3, 31),
    );
  });

  test(
    'today is derived from the church timezone, not the browser timezone',
    () {
      final instant = DateTime.utc(2026, 9, 24, 1);
      configure(zone: 'America/Los_Angeles');
      expect(
        plan(ChurchTime.inZone(instant)).first.date,
        DateTime.utc(2026, 9, 23),
      );
      configure(zone: 'Asia/Taipei');
      expect(
        plan(ChurchTime.inZone(instant)).first.date,
        DateTime.utc(2026, 9, 30),
      );
    },
  );

  test('weekly dates remain seven days apart across DST', () {
    configure(weekday: 7, zone: 'America/Los_Angeles');
    final result = plan(DateTime.utc(2026, 3, 1));
    expect(result.take(3).map((r) => ChurchTime.dateKey(r.date)), [
      '2026-03-01',
      '2026-03-08',
      '2026-03-15',
    ]);
    final firstMidnight = ChurchTime.atDate(result[1].date);
    final secondMidnight = ChurchTime.atDate(result[2].date);
    expect(secondMidnight.difference(firstMidnight).inHours, 167);
  });

  test(
    'DST nonexistent wall-clock time is rejected; date parsing is strict',
    () {
      configure(zone: 'America/Los_Angeles');
      expect(
        () => ChurchTime.atTime(DateTime.utc(2026, 3, 8), 2, 30),
        throwsFormatException,
      );
      expect(
        ChurchTime.atTime(DateTime.utc(2026, 3, 8), 3, 30).toUtc(),
        DateTime.utc(2026, 3, 8, 10, 30),
      );
      expect(() => ChurchTime.parseDate('2026-02-30'), throwsFormatException);
      expect(() => ChurchTime.parseDate('2026-2-3'), throwsFormatException);
      expect(ChurchTime.parseDate('2028-02-29'), DateTime.utc(2028, 2, 29));
    },
  );
}
