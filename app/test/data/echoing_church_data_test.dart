import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/echoing_church_data.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff_order.dart';

import '../support/seed.dart';

Roster withPeople(Roster r, String role, List<String> people) => r.copyWith(
  duties: [for (final d in r.duties) d.role == role ? Duty(role: role, people: people) : d],
);

List<String> shownOn(List<Roster> list, int day, String role) => list
    .firstWhere((r) => r.id == Roster.idFor('sunday', Day(2026, 10, day)))
    .duties
    .firstWhere((d) => d.role == role)
    .people;

/// [stream]'s values as they come, and the latest.
class Seen<T> {
  Seen(Stream<T> stream) {
    _sub = stream.listen(values.add);
    addTearDown(() => _sub.cancel());
  }

  late final StreamSubscription<T> _sub;
  final values = <T>[];
  T get last => values.last;
}

void main() {
  late MemoryBackend b;
  late EchoingChurchData data;
  var now = DateTime(2026, 10, 1, 9);

  setUp(() {
    b = seededChurch()..writeDelay = const Duration(milliseconds: 200);
    now = DateTime(2026, 10, 1, 9);
    data = EchoingChurchData(b.church('grace'), clock: () => now);
  });

  test('a roster change shows at once, before the backend answers, and stays once written', () async {
    final rosters = Seen(data.rosters(from: Day(2026, 10, 1)));
    await pumpEventQueue();
    final before = savedDay(b, 4);
    final after = withPeople(before, '司會', ['王牧師']);

    final done = data.compareAndSetRosters(RosterChange(before: {before.id: before}, after: {after.id: after}));
    await pumpEventQueue();
    expect(shownOn(rosters.last, 4, '司會'), ['王牧師']);
    expect(peopleOn(b, 4, '司會'), ['林同工'], reason: 'not written yet');

    await done;
    await pumpEventQueue();
    expect(peopleOn(b, 4, '司會'), ['王牧師']);
    expect(rosters.values.map((l) => shownOn(l, 4, '司會')).skip(1), everyElement(['王牧師']), reason: 'never back');
  });

  test('a change the backend refuses is taken off the screen, and the refusal reaches the caller', () async {
    final rosters = Seen(data.rosters(from: Day(2026, 10, 1)));
    await pumpEventQueue();
    final before = savedDay(b, 4);
    final after = withPeople(before, '司會', ['王牧師']);
    b.failNextWrite = const CloudException(CloudErrorCode.unavailable);

    final done = data.compareAndSetRosters(RosterChange(before: {before.id: before}, after: {after.id: after}));
    await pumpEventQueue();
    expect(shownOn(rosters.last, 4, '司會'), ['王牧師']);
    await expectLater(done, throwsA(isA<CloudException>()));
    await pumpEventQueue();
    expect(shownOn(rosters.last, 4, '司會'), ['林同工']);
  });

  test('a change made on top of one still being written waits for it, so neither is refused', () async {
    final rosters = Seen(data.rosters(from: Day(2026, 10, 1)));
    await pumpEventQueue();
    final first = savedDay(b, 4);
    final second = withPeople(first, '司會', ['王牧師']);
    final firstDone = data.compareAndSetRosters(RosterChange(before: {first.id: first}, after: {second.id: second}));
    await pumpEventQueue();

    // What the screen shows now is what the next change starts from.
    final shown = rosters.last.firstWhere((r) => r.id == first.id);
    final third = withPeople(shown, '司琴', ['陳志豪']);
    final secondDone = data.compareAndSetRosters(RosterChange(before: {shown.id: shown}, after: {third.id: third}));
    await pumpEventQueue();
    expect(shownOn(rosters.last, 4, '司琴'), ['陳志豪']);

    await Future.wait([firstDone, secondDone]);
    expect(peopleOn(b, 4, '司會'), ['王牧師']);
    expect(peopleOn(b, 4, '司琴'), ['陳志豪']);
  });

  test('saving while a change is on its way, and not after', () async {
    final saving = Seen(data.watchSaving());
    await pumpEventQueue();
    final before = savedDay(b, 4);
    final done = data.compareAndSetRosters(
      RosterChange(
        before: {before.id: before},
        after: {
          before.id: withPeople(before, '司會', ['王牧師']),
        },
      ),
    );
    await pumpEventQueue();
    expect(data.saving, isTrue);
    await done;
    await pumpEventQueue();
    expect(data.saving, isFalse);
    expect(saving.values, [false, true, false]);
  });

  test('once written, a later change by someone else shows, not this one', () async {
    final rosters = Seen(data.rosters(from: Day(2026, 10, 1)));
    await pumpEventQueue();
    final before = savedDay(b, 4);
    await data.compareAndSetRosters(
      RosterChange(
        before: {before.id: before},
        after: {
          before.id: withPeople(before, '司會', ['王牧師']),
        },
      ),
    );
    await pumpEventQueue();

    b.rosters['grace']![before.id] = withPeople(savedDay(b, 4), '司會', ['陳志豪']);
    b.notify();
    await pumpEventQueue();
    expect(shownOn(rosters.last, 4, '司會'), ['陳志豪']);
  });

  test('a written change the server never shows the same way stops showing after a few seconds', () async {
    final rosters = Seen(data.rosters(from: Day(2026, 10, 1)));
    await pumpEventQueue();
    final before = savedDay(b, 4);
    final write = data.compareAndSetRosters(
      RosterChange(
        before: {before.id: before},
        after: {
          before.id: withPeople(before, '司會', ['王牧師']),
        },
      ),
    );
    // Someone else's change lands in the same snapshot as this one.
    await write;
    b.rosters['grace']![before.id] = withPeople(savedDay(b, 4), '司會', ['陳志豪']);
    b.notify();
    await pumpEventQueue();

    now = now.add(EchoingChurchData.linger + const Duration(seconds: 1));
    b.notify();
    await pumpEventQueue();
    expect(shownOn(rosters.last, 4, '司會'), ['陳志豪']);
  });

  test('a new saved day shows at once, and a deleted one goes at once', () async {
    final rosters = Seen(data.rosters(from: Day(2026, 10, 1)));
    await pumpEventQueue();
    final added = Roster(
      type: 'sunday',
      day: Day(2026, 10, 18),
      duties: const [
        Duty(role: '司會', people: ['王牧師']),
      ],
    );
    final gone = savedDay(b, 11);
    final done = data.compareAndSetRosters(
      RosterChange(before: {added.id: null, gone.id: gone}, after: {added.id: added, gone.id: null}),
    );
    await pumpEventQueue();
    expect(rosters.last.map((r) => r.day.day), [4, 18]);
    await done;
  });

  test('a day before the range read is not shown', () async {
    final rosters = Seen(data.rosters(from: Day(2026, 10, 10)));
    await pumpEventQueue();
    final early = savedDay(b, 4);
    final done = data.compareAndSetRosters(
      RosterChange(
        before: {early.id: early},
        after: {
          early.id: withPeople(early, '司會', ['王牧師']),
        },
      ),
    );
    await pumpEventQueue();
    expect(rosters.last.map((r) => r.day.day), [11]);
    await done;
  });

  test('my notification settings show at once, in my member doc and in the list', () async {
    final me = Seen(data.member('pastor'));
    final all = Seen(data.members());
    await pumpEventQueue();
    final done = data.setNotificationPrefs('pastor', {NotificationKind.reminder});
    await pumpEventQueue();
    expect(me.last!.mutedNotifications, {NotificationKind.reminder});
    expect(all.last.firstWhere((m) => m.uid == 'pastor').mutedNotifications, {NotificationKind.reminder});
    final timing = data.setReminderTiming('pastor', ReminderTiming.dayBefore);
    await pumpEventQueue();
    expect(me.last!.reminderTiming, ReminderTiming.dayBefore);
    await Future.wait([done, timing]);
  });

  test("an admin's member edits show at once", () async {
    final all = Seen(data.members());
    await pumpEventQueue();
    final mei = b.members['grace']!['mei']!;
    final edit = data.compareAndSetMember(
      before: mei,
      after: mei.copyWith(role: Role.admin),
    );
    final grant = data.grantDuty('hao', 'sunday', '司琴');
    final removal = data.removeMember('john');
    await pumpEventQueue();
    expect(all.last.firstWhere((m) => m.uid == 'mei').role, Role.admin);
    expect(all.last.firstWhere((m) => m.uid == 'hao').zones.single.duties, ['招待', '司琴']);
    expect(all.last.map((m) => m.uid), isNot(contains('john')));
    await Future.wait([edit, grant, removal]);
  });

  test('service settings and staff orders show at once', () async {
    final services = Seen(data.services());
    final order = Seen(data.staffOrder('sunday'));
    await pumpEventQueue();
    final list = services.last.services;
    final renamed = list.first.copyWith(name: '第一堂');
    final listDone = data.compareAndSetServiceList(before: list, after: [renamed, list.last]);
    await pumpEventQueue();
    expect(services.last.services.first.name, '第一堂');

    final youth = list.last;
    final serviceDone = data.compareAndSetService(
      before: youth,
      after: youth.copyWith(name: '青年聚會'),
    );
    await pumpEventQueue();
    expect(services.last.services.map((s) => s.name), ['第一堂', '青年聚會']);

    final day = savedDay(b, 4);
    final ranking = StaffOrder({
      '招待': ['李美玉', '陳志豪'],
    });
    final orderDone = data.compareAndSetRosters(
      RosterChange(
        before: {day.id: day},
        after: {day.id: day},
        staffOrder: (serviceType: 'sunday', before: b.staffOrders['grace']!['sunday']!, after: ranking),
      ),
    );
    await pumpEventQueue();
    expect(order.last, ranking);
    await Future.wait([listDone, serviceDone, orderDone]);
  });
}
