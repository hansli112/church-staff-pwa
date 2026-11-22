import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/roster_day.dart';

import '../support/harness.dart';
import '../support/seed.dart';

const _worship = Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]);

/// 10/20: the days of the seeded month gone by.
final _later = ChurchTimeZone.taipei.instantOf(DateTime.utc(2026, 10, 20, 9));

Future<ProviderContainer> opened(MemoryBackend b, Day day) async {
  final container = ProviderContainer(overrides: await testOverrides(b));
  addTearDown(container.dispose);
  container.listen(appStageProvider, (_, _) {});
  container.listen(ministriesProvider, (_, _) {});
  container.listen(rosterDayProvider(('sunday', day)), (_, _) {});
  await pumpEventQueue();
  return container;
}

RosterDay shown(ProviderContainer c, Day day) => c.read(rosterDayProvider(('sunday', day)))!.requireValue;

void main() {
  test("a day ahead shows what is saved, for the service's 負責人 to change", () async {
    final b = seededChurch(as: editor);
    final day = Day(2026, 10, 11);
    final c = await opened(b, day);
    final page = shown(c, day);
    expect(page.roster, savedDay(b, 11));
    expect(page.past, isFalse);
    expect(page.canEdit, isTrue);
    expect(page.wholeDay, isTrue);
  });

  test("a day ahead nobody arranged yet starts from the service's duties", () async {
    final b = seededChurch(as: editor);
    final day = Day(2026, 10, 25);
    final c = await opened(b, day);
    expect([for (final d in shown(c, day).roster.duties) d.role], ['司會', '司琴', '招待']);
  });

  test('a 同工 who arranges nothing only looks', () async {
    final b = seededChurch(as: staffMei);
    final day = Day(2026, 10, 11);
    final c = await opened(b, day);
    expect(shown(c, day).canEdit, isFalse);
  });

  test("a 事工's 負責人 changes only the duties it leads, and adds only those", () async {
    final lead = staffHao.withIdentities(const [MinistryLead('worship')]);
    final b = seededChurch(extra: [lead], as: lead);
    b.ministries['grace'] = const MinistrySettings(ministries: [_worship], ids: ['worship']);
    final day = Day(2026, 10, 25);
    final c = await opened(b, day);
    final page = shown(c, day);
    expect(page.canEdit, isTrue);
    expect(page.wholeDay, isFalse);
    expect(page.addable, isEmpty, reason: '司琴 is on the day already');
  });

  test('a day gone by is only looked at, by an admin too, read as it was saved', () async {
    final b = seededChurch(clock: () => _later);
    final day = Day(2026, 10, 11);
    final c = await opened(b, day);
    final page = shown(c, day);
    expect(page.past, isTrue);
    expect(page.canEdit, isFalse);
    expect(page.roster, savedDay(b, 11));
  });

  test("a day gone by nobody was arranged on has no duties, not the service's", () async {
    final b = seededChurch(clock: () => _later);
    final day = Day(2026, 10, 18);
    final c = await opened(b, day);
    expect(shown(c, day).roster.duties, isEmpty);
  });

  test('a service that is not there shows nothing', () async {
    final b = seededChurch();
    final c = await opened(b, Day(2026, 10, 11));
    expect(c.read(rosterDayProvider(('gone', Day(2026, 10, 11)))), isNull);
  });
}
