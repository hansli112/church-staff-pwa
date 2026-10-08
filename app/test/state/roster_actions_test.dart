import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/roster_actions.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  Future<(ProviderContainer, RosterActions)> open(MemoryBackend backend, {bool load = true}) async {
    final container = ProviderContainer(overrides: await testOverrides(backend));
    addTearDown(container.dispose);
    container.listen(appStageProvider, (_, _) {});
    if (load) container.listen(rosterEditingProvider('sunday'), (_, _) {});
    await pumpEventQueue();
    return (container, container.read(rosterActionsProvider));
  }

  test('says when everything editing reads is loaded, and only then writes', () async {
    final b = seededChurch();
    final (container, actions) = await open(b, load: false);
    final day = savedDay(b, 11);
    expect(() => actions.setPeople(day, '司琴', ['李美玉']), throwsStateError, reason: 'not guessing at members');

    container.listen(rosterEditingProvider('sunday'), (_, _) {});
    await pumpEventQueue();
    expect(container.read(rosterEditingProvider('sunday')), isTrue);
    await actions.setPeople(day, '司琴', ['李美玉']).done;
    expect(savedDay(b, 11).duties.firstWhere((d) => d.role == '司琴').uids, {'李美玉': 'mei'});
  });

  test('new common events and the day’s events are taken back together', () async {
    final b = seededChurch();
    final (_, actions) = await open(b);
    const retreat = EventTag(name: '退修會', color: 2);
    final day = savedDay(b, 11);
    final write = actions.setEvents(day, const [retreat], addToCommon: const [retreat]);
    await write.done;
    await pumpEventQueue();
    expect(b.services['grace']!.byId('sunday')!.events, const [EventTag(name: '聖餐', color: 0), retreat]);
    expect(savedDay(b, 11).events, const [retreat]);

    await write.undo();
    expect(b.services['grace']!.byId('sunday')!.events, const [EventTag(name: '聖餐', color: 0)]);
    expect(savedDay(b, 11).events, isEmpty);
  });

  test('a new common event alone leaves a template day a draft', () async {
    final b = seededChurch();
    final (_, actions) = await open(b);
    const retreat = EventTag(name: '退修會', color: 2);
    final draft = Roster(type: 'sunday', day: Day(2026, 10, 18));
    await actions.setEvents(draft, const [], addToCommon: const [retreat]).done;
    expect(b.services['grace']!.byId('sunday')!.events, contains(retreat));
    expect(b.rosters['grace']![draft.id], isNull);
  });

  test('an import is applied in full and undone in full, staff order included', () async {
    final b = seededChurch();
    final (_, actions) = await open(b);
    final before11 = savedDay(b, 11);
    final orderBefore = b.staffOrders['grace']!['sunday'];
    final rows = [
      {
        'date': '2026-10-11',
        'duties': [
          {
            'role': '招待',
            'people': ['王牧師'],
          },
        ],
      },
      {
        'date': '2026-10-18',
        'duties': [
          {
            'role': '司琴',
            'people': ['李美玉'],
          },
        ],
      },
    ];
    final plan = actions.previewImport('sunday', rows);
    expect(plan.rosters.map((r) => r.day), [Day(2026, 10, 11), Day(2026, 10, 18)]);

    final write = actions.applyImport('sunday', rows);
    await write.done;
    await pumpEventQueue();
    expect(savedDay(b, 11).duties.firstWhere((d) => d.role == '招待').people, ['王牧師']);
    expect(b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))], isNotNull);

    await write.undo();
    expect(savedDay(b, 11), before11);
    expect(b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))], isNull);
    expect(b.staffOrders['grace']!['sunday'], orderBefore);
  });
}
