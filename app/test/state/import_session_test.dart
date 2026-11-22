import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/roster_import.dart';
import 'package:martha/state/import_session.dart';
import 'package:martha/state/providers.dart';

import '../support/harness.dart';
import '../support/seed.dart';

final _rows = [
  {
    'date': '2026-10-11',
    'duties': [
      {
        'role': '司琴',
        'people': ['李美玉'],
      },
    ],
  },
];

Future<ProviderContainer> opened(MemoryBackend b) async {
  final container = ProviderContainer(overrides: await testOverrides(b));
  addTearDown(container.dispose);
  container.listen(appStageProvider, (_, _) {});
  container.listen(importPlanProvider('sunday'), (_, _) {});
  await pumpEventQueue();
  return container;
}

ImportSession session(ProviderContainer c) => c.read(importSessionProvider('sunday').notifier);

ImportPlan plan(ProviderContainer c) => c.read(importPlanProvider('sunday'))!;

void main() {
  test('loaded rows are planned against the rosters as they are now, and planned again when one changes', () async {
    final b = seededChurch();
    final c = await opened(b);
    expect(c.read(importPlanProvider('sunday')), isNull, reason: 'nothing loaded yet');
    session(c).load(_rows);
    expect(plan(c).changes.values.single.before, savedDay(b, 11));

    final day = savedDay(b, 11);
    final newer = day.copyWith(events: const [EventTag(name: '聖餐', color: 0)]);
    b.rosters['grace']![day.id] = newer;
    b.notify();
    await pumpEventQueue();
    expect(plan(c).changes.values.single.before, newer);
  });

  test('switching account drops the draft and says so', () async {
    final b = seededChurch();
    final c = await opened(b);
    session(c).load(_rows);
    b.auth.signInAs('editor@example.com', uid: 'editor', name: '林同工');
    await pumpEventQueue();
    final draft = c.read(importSessionProvider('sunday'));
    expect(draft.rows, isEmpty);
    expect(draft.scopeChanged, isTrue);
    expect(c.read(importPlanProvider('sunday')), isNull);
    session(c).load(_rows);
    expect(c.read(importSessionProvider('sunday')).scopeChanged, isFalse, reason: 'said until new rows come');
  });

  test('photos recognized after switching account never reach the new draft', () async {
    final held = Completer<void>();
    final b = seededChurch()
      ..recognized = _rows
      ..recognizing = held.future;
    final c = await opened(b);
    final reading = session(c).recognize(const [
      PhotoInput(mimeType: 'image/jpeg', bytes: [1, 2, 3]),
    ]);
    b.auth.signInAs('editor@example.com', uid: 'editor', name: '林同工');
    await pumpEventQueue();
    held.complete();
    await reading;
    await pumpEventQueue();
    expect(c.read(importSessionProvider('sunday')).rows, isEmpty);
  });

  test('who a name is survives editing the rows, not loading new ones', () async {
    final b = seededChurch();
    final c = await opened(b);
    session(c).load(_rows);
    session(c).choose('李美玉', const ImportPersonChoice.guest());
    session(c).setDate(0, Day(2026, 10, 18));
    expect(c.read(importSessionProvider('sunday')).people, {'李美玉': const ImportPersonChoice.guest()});
    expect(plan(c).changes.values.single.after.duties.firstWhere((d) => d.role == '司琴').uids, isEmpty);
    session(c).load(_rows);
    expect(c.read(importSessionProvider('sunday')).people, isEmpty);
  });

  test('adding a missing duty to the service plans the import again', () async {
    final b = seededChurch();
    final c = await opened(b);
    session(c).load([
      {
        'date': '2026-10-18',
        'duties': [
          {
            'role': '鼓',
            'people': ['陳志豪'],
          },
        ],
      },
    ]);
    expect(plan(c).report.unknownDuties, ['鼓']);
    await session(c).addDuty('鼓');
    await pumpEventQueue();
    expect(b.services['grace']!.byId('sunday')!.duties, contains('鼓'));
    expect(plan(c).report.unknownDuties, isEmpty);
  });

  test('applying checks the preview that was shown, not a newer one', () async {
    final b = seededChurch();
    final c = await opened(b);
    session(c).load(_rows);
    final shown = plan(c);
    final day = savedDay(b, 11);
    b.rosters['grace']![day.id] = day.copyWith(events: const [EventTag(name: '聖餐', color: 0)]);
    b.notify();
    await pumpEventQueue();
    await expectLater(
      Future<void>.sync(() => session(c).apply(shown).done),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
    );
    await session(c).apply(plan(c)).done;
    expect(savedDay(b, 11).duties.firstWhere((d) => d.role == '司琴').people, ['李美玉']);
  });

  group('editing a row', () {
    test('a date picked is the day the row is for', () async {
      final c = await opened(seededChurch());
      session(c).load(_rows);
      session(c).setDate(0, Day(2026, 10, 18));
      expect(c.read(importSessionProvider('sunday')).rows.single['date'], '2026-10-18');
      expect(plan(c).changes.keys.single, contains('2026-10-18'));
    });

    test('a duty is added, changed and taken away; its people trimmed, blank lines left out', () async {
      final c = await opened(seededChurch());
      session(c).load(_rows);
      session(c).putDuty(0, null, role: ' 招待 ', people: const ['陳志豪', '  ', ' 李美玉 ']);
      session(c).putDuty(0, 0, role: '司琴', people: const ['王小明']);
      expect(c.read(importSessionProvider('sunday')).rows.single['duties'], [
        {
          'role': '司琴',
          'people': ['王小明'],
        },
        {
          'role': '招待',
          'people': ['陳志豪', '李美玉'],
        },
      ]);
      session(c).removeDuty(0, 0);
      expect((c.read(importSessionProvider('sunday')).rows.single['duties'] as List).single['role'], '招待');
    });

    test('a 特別活動 is added with its color, changed and taken away', () async {
      final c = await opened(seededChurch());
      session(c).load(_rows);
      session(c).putEvent(0, null, name: ' 聖餐 ', color: 2);
      session(c).putEvent(0, 0, name: '浸禮', color: 4);
      session(c).putEvent(0, null, name: '愛宴', color: 1);
      expect(c.read(importSessionProvider('sunday')).rows.single['events'], [
        {'name': '浸禮', 'color': 4},
        {'name': '愛宴', 'color': 1},
      ]);
      session(c).removeEvent(0, 1);
      expect(c.read(importSessionProvider('sunday')).rows.single['events'], [
        {'name': '浸禮', 'color': 4},
      ]);
    });

    test('a row is changed as it is now, not as the sheet saw it', () async {
      final c = await opened(seededChurch());
      session(c).load(_rows);
      session(c).putEvent(0, null, name: '聖餐', color: 0);
      session(c).setDate(0, Day(2026, 10, 18));
      final row = c.read(importSessionProvider('sunday')).rows.single as Map;
      expect(row['events'], isNotEmpty, reason: 'the date kept what was added before');
      expect(row['duties'], isNotEmpty);
    });
  });
}
