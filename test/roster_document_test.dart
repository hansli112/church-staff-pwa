import 'dart:convert';

import 'package:church_staff_pwa/core/config/church_config.dart';
import 'package:church_staff_pwa/core/config/default_church_config.dart';
import 'package:church_staff_pwa/core/time/church_time.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/data/roster_document.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void setZone(String zone) {
  ChurchConfig.current = ChurchConfig.fromJson({
    ...jsonDecode(defaultChurchConfigJson) as Map<String, dynamic>,
    'timeZone': zone,
  });
}

Map<String, dynamic> legacy() => {
  'date': Timestamp.fromDate(DateTime.utc(2026, 10, 2, 16)),
  'type': 'youth',
  'serviceName': '歷史聚會名稱',
  'duties': [
    {
      'role': '招待',
      'people': ['Test Person'],
      'personIdsByName': {'Test Person': 'uid-test'},
    },
  ],
};

void main() {
  late ChurchConfig previous;
  setUp(() => previous = ChurchConfig.current);
  tearDown(() => ChurchConfig.current = previous);

  test('legacy document ID preserves its date in any configured timezone', () {
    for (final zone in [
      'Asia/Taipei',
      'America/Los_Angeles',
      'Pacific/Auckland',
      'UTC',
    ]) {
      setZone(zone);
      final roster = rosterFromFirestore(legacy(), '20261003_youth');
      expect(roster.date, DateTime.utc(2026, 10, 3));
      expect(roster.type, ServiceType.youth);
      expect(roster.duties.single.people, ['Test Person']);
      expect(roster.duties.single.personIdsByName, {'Test Person': 'uid-test'});
    }
  });

  test(
    'editing old roster contents preserves stored timestamp and adds dateKey',
    () {
      setZone('America/Los_Angeles');
      final original = legacy();
      final roster = rosterFromFirestore(original, '20261003_youth');
      final updated = roster.copyWith(specialEvents: ['活動']);
      final stored = rosterToFirestore(updated);
      expect(stored['date'], original['date']);
      expect(stored['dateKey'], '2026-10-03');
      expect(stored['serviceName'], original['serviceName']);
      expect(stored['duties'], original['duties']);
      expect(stored['specialEvents'], ['活動']);
      expect(roster.serviceName, '歷史聚會名稱');
      expect(roster.displayName, ServiceType.youth.serviceName);
    },
  );

  test('dateKey survives subsequent church timezone changes', () {
    setZone('Asia/Taipei');
    final stored = rosterToFirestore(
      rosterFromFirestore(legacy(), '20261003_youth'),
    );
    setZone('America/Los_Angeles');
    final restored = rosterFromFirestore(stored, '20261003_youth');
    expect(restored.date, DateTime.utc(2026, 10, 3));
    expect(rosterToFirestore(restored)['date'], stored['date']);
  });

  test(
    'new documents store church midnight and an independent calendar date',
    () {
      setZone('America/Los_Angeles');
      final roster = ServiceRoster(
        id: '20260315_youth',
        date: DateTime.utc(2026, 3, 15),
        type: ServiceType.youth,
        serviceName: '青年聚會',
        duties: [],
      );
      final stored = rosterToFirestore(roster);
      expect(stored['dateKey'], '2026-03-15');
      expect(
        (stored['date'] as Timestamp).toDate().toUtc(),
        DateTime.utc(2026, 3, 15, 7),
      );
      expect(
        ChurchTime.dateKey(rosterFromFirestore(stored, roster.id).date),
        '2026-03-15',
      );
    },
  );

  test(
    'unknown type and name remain intact rather than turning into Sunday',
    () {
      final roster = rosterFromFirestore({
        ...legacy(),
        'type': 'archived',
      }, '20261003_archived');
      expect(roster.type.name, 'archived');
      expect(roster.type, isNot(ServiceType.sundayService));
      expect(roster.displayName, '歷史聚會名稱');
      expect(rosterToFirestore(roster)['type'], 'archived');
    },
  );

  test(
    'malformed explicit dates and missing type are not silently repaired',
    () {
      expect(
        () => rosterFromFirestore({
          ...legacy(),
          'dateKey': '2026-02-30',
        }, '20261003_youth'),
        throwsFormatException,
      );
      expect(
        () =>
            rosterFromFirestore({...legacy(), 'type': null}, '20261003_youth'),
        throwsFormatException,
      );
    },
  );
}
