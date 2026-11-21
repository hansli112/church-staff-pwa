import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/duty_pick.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/roster_actions.dart';

import '../support/harness.dart';
import '../support/seed.dart';

const _worship = Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]);

Future<ProviderContainer> opened(MemoryBackend b) async {
  final container = ProviderContainer(overrides: await testOverrides(b));
  addTearDown(container.dispose);
  container.listen(appStageProvider, (_, _) {});
  container.listen(rosterEditingProvider('sunday'), (_, _) {});
  // As the day's page does.
  container.listen(ministriesProvider, (_, _) {});
  await pumpEventQueue();
  return container;
}

Roster _event() => Roster(
  type: '',
  day: Day(2026, 12, 24),
  forEvent: RosterEvent(eventId: 'xmas', title: '聖誕晚會', lastDay: Day(2026, 12, 24)),
  duties: const [Duty(role: '司琴')],
);

Duty _duty(Roster r, String role) => r.duties.firstWhere((d) => d.role == role);

void main() {
  group('what picking may change', () {
    test("a service's 負責人 picks, puts anyone on the list, drags the order and adds a 同工", () async {
      final b = seededChurch(as: editor);
      final c = await opened(b);
      final rights = c.read(dutyPickingProvider).rightsOn(savedDay(b, 11), '司琴');
      expect(rights.putsOnList, isTrue);
      expect(rights.takesOffList, isTrue);
      expect(rights.reorders, isTrue);
      expect(rights.addsStaff, isTrue);
      expect(rights.dropsFutureGuests, isTrue);
    });

    test("a 事工's 負責人 takes off the list of a duty it leads, and nothing more", () async {
      final b = seededChurch(
        extra: [
          staffMei.withIdentities(const [MinistryLead('worship')]),
        ],
        as: staffMei,
      );
      b.ministries['grace'] = const MinistrySettings(ministries: [_worship], ids: ['worship']);
      final c = await opened(b);
      final rights = c.read(dutyPickingProvider).rightsOn(savedDay(b, 11), '司琴');
      expect(rights.takesOffList, isTrue);
      expect(rights.putsOnList, isFalse, reason: 'putting on moves the staff order: the whole day');
      expect(rights.reorders, isFalse);
      expect(rights.addsStaff, isFalse);
    });

    test('a duty only this day has, or an event, has no list and no one to add to', () async {
      final b = seededChurch(as: editor);
      final c = await opened(b);
      final picking = c.read(dutyPickingProvider);
      final once = picking.rightsOn(savedDay(b, 11), '獻詩');
      expect(once.putsOnList || once.takesOffList, isFalse);
      expect(once.reorders, isTrue);

      final event = picking.rightsOn(_event(), '司琴');
      expect(event.putsOnList || event.takesOffList || event.reorders || event.addsStaff, isFalse);
      expect(event.dropsFutureGuests, isFalse);
    });
  });

  group('saving a pick', () {
    test('a 同工 typed in is added on the list and put on the day by ID, before the day is saved', () async {
      final b = seededChurch(as: editor);
      final c = await opened(b);
      final day = savedDay(b, 11);
      final save = await c
          .read(dutyPickingProvider)
          .save(day, _duty(day, '司琴'), const DutyPick(people: ['王小明'], newStaff: {'王小明'}));
      await save.day!().done;
      final saved = _duty(savedDay(b, 11), '司琴');
      expect(saved.people, ['王小明']);
      final id = saved.uids['王小明']!;
      expect(b.pendingMembers['grace']![id]!.zones.single.duties, ['司琴']);
    });

    test('one that cannot be added says who, and the day is left as it was', () async {
      final b = seededChurch(as: editor);
      final c = await opened(b);
      final day = savedDay(b, 11);
      await expectLater(
        c.read(dutyPickingProvider).save(day, _duty(day, '司琴'), const DutyPick(people: ['李美玉'], newStaff: {'李美玉'})),
        throwsA(
          isA<StaffNotAdded>()
              .having((e) => e.name, 'name', '李美玉')
              .having((e) => (e.error as CloudException).code, 'code', CloudErrorCode.duplicateName),
        ),
      );
      expect(savedDay(b, 11), day);
    });

    test('taken off the list alone: nothing to save on the day, the list changed, and 復原 puts them back', () async {
      final b = seededChurch(as: editor);
      final c = await opened(b);
      final day = savedDay(b, 11);
      final duty = _duty(day, '司琴');
      final save = await c
          .read(dutyPickingProvider)
          .save(day, duty, DutyPick(people: duty.people, takeOffList: const [staffMei]));
      expect(save.day, isNull);
      await save.lists;
      expect(b.members['grace']!['mei']!.serves('sunday', '司琴'), isFalse);
      await save.undoTakeOff!();
      expect(b.members['grace']!['mei']!.serves('sunday', '司琴'), isTrue);
    });

    test('only dragged: the order is saved, the people as they were', () async {
      final b = seededChurch(as: editor);
      final c = await opened(b);
      final day = savedDay(b, 11);
      final duty = _duty(day, '招待');
      final save = await c
          .read(dutyPickingProvider)
          .save(day, duty, DutyPick(people: duty.people, ranking: const ['李美玉', '陳志豪']));
      expect(save.peopleChanged, isFalse);
      await save.day!().done;
      expect(b.staffOrders['grace']!['sunday']!.rankingOf('招待'), ['李美玉', '陳志豪']);
    });
  });
}
