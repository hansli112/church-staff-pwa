import 'dart:async';

import 'package:fake_async/fake_async.dart';
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
    addTearDown(data.close);
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

  test('a written change the server shows differently stops showing after a few seconds, with nothing else coming', () {
    fakeAsync((async) {
      // Made here, so its timers and microtasks run on the fake clock.
      final b = seededChurch()..writeDelay = const Duration(milliseconds: 200);
      // A backend whose copy of a written day always shows it as someone
      // else left it: this change never arrives as made.
      final data = EchoingChurchData(_Overwritten(b.church('grace')));
      final before = savedDay(b, 4);
      final rosters = Seen(data.rosters(from: Day(2026, 10, 1)));
      async.flushMicrotasks();
      data.compareAndSetRosters(
        RosterChange(
          before: {before.id: before},
          after: {
            before.id: withPeople(before, '司會', ['王牧師']),
          },
        ),
      );
      async.elapse(const Duration(milliseconds: 200));
      expect(data.saving, isFalse);
      expect(shownOn(rosters.last, 4, '司會'), ['王牧師'], reason: 'within the few seconds');
      async.elapse(EchoingChurchData.linger);
      expect(shownOn(rosters.last, 4, '司會'), ['陳志豪']);
      data.close();
    });
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

  test('a 同工 without an account put on a duty, or taken off, shows at once', () async {
    final id = await data.addByName('王小明', 'sunday');
    final pending = Seen(data.pendingMembers());
    await pumpEventQueue();
    expect(pending.last.single.id, id);

    final granted = data.grantDuty(id, 'sunday', '司琴');
    await pumpEventQueue();
    expect(pending.last.single.zones.single.duties, ['司琴']);
    await granted;
    final revoked = data.revokeDuty(id, 'sunday', '司琴');
    await pumpEventQueue();
    expect(pending.last.single.zones.single.duties, isEmpty);
    await revoked;
    await pumpEventQueue();
    expect(pending.last.single.zones.single.duties, isEmpty, reason: "the backend's copy agrees");
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

  test("a 小組's 小組長 shows at once, and the one before no longer does", () async {
    b.writeDelay = Duration.zero;
    final id = await b
        .church('grace')
        .saveSmallGroup(
          const SmallGroupDetails(id: '', name: '喜樂', service: 'sunday'),
          leads: ['mei'],
        );
    b.writeDelay = const Duration(milliseconds: 200);
    final all = Seen(data.members());
    await pumpEventQueue();
    List<String> leadersIn(List<Member> list) => [
      for (final m in list)
        if (m.leadSmallGroups.contains(id)) m.uid,
    ];
    expect(leadersIn(all.last), ['mei']);

    final done = data.saveSmallGroup(
      SmallGroupDetails(id: id, name: '喜樂', service: 'sunday'),
      leads: ['hao'],
    );
    await pumpEventQueue();
    expect(leadersIn(all.last), ['hao'], reason: 'before the backend answers');
    expect(b.members['grace']!['hao']!.leadSmallGroups, isEmpty, reason: 'not written yet');

    await done;
    await pumpEventQueue();
    expect(leadersIn(all.last), ['hao']);
    expect(all.values.skip(1).map(leadersIn), everyElement(['hao']), reason: 'never back');
  });

  test('a 小組 renamed shows at once, and never goes back', () async {
    b.writeDelay = Duration.zero;
    final id = await b.church('grace').saveSmallGroup(const SmallGroupDetails(id: '', name: '喜樂', service: 'sunday'));
    b.writeDelay = const Duration(milliseconds: 200);
    final groups = Seen(data.smallGroups());
    await pumpEventQueue();
    final joy = groups.last.single;

    final done = data.saveSmallGroup(joy.copyWith(name: '大喜樂'), before: joy);
    await pumpEventQueue();
    expect(groups.last.single.name, '大喜樂', reason: 'before the backend answers');
    expect(b.smallGroups['grace']![id]!.name, '喜樂', reason: 'not written yet');

    await done;
    await pumpEventQueue();
    expect(groups.values.skip(1).map((l) => l.single.name), everyElement('大喜樂'));
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

  test("the church's 時區, 申請加入 and 回報人數 show at once, and go back if refused", () async {
    final church = Seen(data.church());
    await pumpEventQueue();
    final zone = ChurchTimeZone.values.firstWhere((z) => z != church.last!.timeZone);

    final zoned = data.setTimeZone(zone);
    final asks = data.joining.setTakesRequests(!church.last!.takesJoinRequests);
    final since = data.attendance.saveSince(Day(2026, 10, 1));
    await pumpEventQueue();
    expect(church.last!.timeZone, zone, reason: 'before the backend answers');
    expect(church.last!.attendanceSince, Day(2026, 10, 1));
    expect(data.saving, isTrue);
    await Future.wait([zoned, asks, since]);
    await pumpEventQueue();
    expect(church.values.skip(1).map((c) => c!.timeZone), everyElement(zone), reason: 'never back');

    b.failNextWrite = const CloudException(CloudErrorCode.unavailable);
    final off = data.attendance.saveSince(null);
    await pumpEventQueue();
    expect(church.last!.attendanceSince, isNull);
    await expectLater(off, throwsA(isA<CloudException>()));
    await pumpEventQueue();
    expect(church.last!.attendanceSince, Day(2026, 10, 1), reason: 'refused, back');
  });

  test('人數, and a 其他聚會 renamed, moved or deleted, show at once', () async {
    b.writeDelay = Duration.zero;
    b.churches['grace'] = b.churches['grace']!.copyWith(attendanceSince: () => Day(2026, 10, 1));
    final a = await b.church('grace').attendance.saveGathering(const Gathering(id: '', name: '禱告會'));
    final c = await b.church('grace').attendance.saveGathering(const Gathering(id: '', name: '查經'));
    b.writeDelay = const Duration(milliseconds: 200);
    final gatherings = Seen(data.attendance.gatherings());
    final record = Seen(data.attendance.watch('gathering:$a'));
    await pumpEventQueue();
    expect(gatherings.last.map((g) => g.name), ['查經', '禱告會']);

    final counted = data.attendance.save('gathering:$a', Day(2026, 10, 7), const AttendanceDay.count(12));
    final renamed = data.attendance.saveGathering(gatherings.last.last.copyWith(name: '週三禱告會'));
    final moved = data.attendance.orderGatherings([a, c]);
    await pumpEventQueue();
    expect(record.last.days[Day(2026, 10, 7)]?.count, 12, reason: 'before the backend answers');
    expect(gatherings.last.map((g) => g.name), ['週三禱告會', '查經']);
    await Future.wait([counted, renamed, moved]);
    await pumpEventQueue();
    expect(gatherings.last.map((g) => g.name), ['週三禱告會', '查經'], reason: "the backend's copy agrees");

    final deleted = data.attendance.deleteGathering(c);
    await pumpEventQueue();
    expect(gatherings.last.map((g) => g.name), ['週三禱告會']);
    await deleted;
  });

  test('a 備註 shows at once, an emptied one goes at once', () async {
    final notes = Seen(data.rosterNotes.watch());
    await pumpEventQueue();
    final id = Roster.idFor('sunday', Day(2026, 10, 4));

    final saved = data.rosterNotes.save(id, const RosterNote(text: ' 帶傘 '));
    await pumpEventQueue();
    expect(notes.last[id]?.text, '帶傘', reason: 'before the backend answers');
    await saved;
    final emptied = data.rosterNotes.save(id, const RosterNote(text: ''));
    await pumpEventQueue();
    expect(notes.last, isNot(contains(id)));
    await emptied;
  });

  test("the webhook's switches show at once, and turned off it goes at once", () async {
    b.webhooks['grace'] = const WebhookSettings(url: 'https://example.com/hook');
    final hook = Seen(data.webhook.watch());
    await pumpEventQueue();

    final on = data.webhook.save(url: 'https://example.com/hook', calendar: true);
    await pumpEventQueue();
    expect(hook.last?.calendar, isTrue, reason: 'before the backend answers');
    await on;
    final off = data.webhook.save(url: null);
    await pumpEventQueue();
    expect(hook.last, isNull);
    await off;
  });

  test('a 同工 without an account deleted goes at once', () async {
    final id = await data.addByName('王小明', 'sunday');
    final pending = Seen(data.pendingMembers());
    await pumpEventQueue();
    expect(pending.last.map((p) => p.id), [id]);

    final deleted = data.deletePendingMember(id);
    await pumpEventQueue();
    expect(pending.last, isEmpty, reason: 'before the backend answers');
    await deleted;
    await pumpEventQueue();
    expect(pending.last, isEmpty);
  });

  test('小組 moved show in their new places at once', () async {
    b.writeDelay = Duration.zero;
    final joy = await b.church('grace').saveSmallGroup(const SmallGroupDetails(id: '', name: '喜樂', service: 'sunday'));
    final peace = await b
        .church('grace')
        .saveSmallGroup(const SmallGroupDetails(id: '', name: '平安', service: 'sunday'));
    b.writeDelay = const Duration(milliseconds: 200);
    final groups = Seen(data.smallGroups());
    await pumpEventQueue();

    final moved = data.orderSmallGroups('sunday', [peace, joy]);
    await pumpEventQueue();
    int? orderOf(String id) => groups.last.firstWhere((g) => g.id == id).order;
    expect([orderOf(peace), orderOf(joy)], [0, 1], reason: 'before the backend answers');
    await moved;
  });

  test('a calendar event or my 不能服事的日子 count as saving while on their way', () async {
    final saving = data.unavailable.saveMine(UnavailableDays([UnavailableSpan(Day(2026, 10, 11), Day(2026, 10, 11))]));
    await pumpEventQueue();
    expect(data.saving, isTrue);
    await saving;
    await pumpEventQueue();
    expect(data.saving, isFalse);
  });

  test('a tap waiting on the backend with nothing to show early counts as saving while on its way', () {
    final sunday = Roster(type: 'sunday', day: Day(2026, 10, 11));
    final sends = <String, Future<Object?> Function(EchoingChurchData d)>{
      '刪除教會': (d) => d.run(const DeleteChurch()),
      '恢復教會': (d) => d.run(const RestoreChurch()),
      '家人': (d) => d.run(const AnswerFamily('h1', yes: true)),
      '認領': (d) => d.run(const AskClaim('p1')),
      '取消認領': (d) => d.run(const AskClaim(null)),
      '回覆認領': (d) => d.run(const AnswerClaim('mei', allow: true)),
      '找人代': (d) => d.run(AskCover(sunday, '司琴')),
      '交換': (d) => d.run(AskSwap(sunday, '司琴', sunday, 'mei')),
      '回覆交換': (d) => d.run(const AnswerSwap('s1', yes: true)),
      '復原交換': (d) => d.run(const UndoSwap('s1')),
      '收回': (d) => d.run(const WithdrawSwap('s1')),
      '通知同工填': (d) => d.run(AskUnavailable('sunday', from: Day(2026, 11, 1), to: Day(2026, 11, 30))),
      '提醒同工填': (d) => d.run(const RemindUnavailable('sunday')),
      '通知排班': (d) => d.run(const NotifyPlanned('sunday')),
      '申請加入': (d) => d.run(const AnswerJoinRequest('mei', allow: true)),
      '送出': (d) => d.unavailable.send(),
      '提醒回報人數': (d) => d.attendance.remind('k', Day(2026, 10, 11)),
      '選日曆': (d) => d.calendar.select('cal', '行事曆'),
      '中斷日曆': (d) => d.calendar.disconnect(),
      '新邀請': (d) => d.joining.createInvite(validFor: const Duration(days: 7)),
      '延長邀請': (d) => d.joining.renewInvite('c1', validFor: const Duration(days: 7)),
    };
    for (final MapEntry(key: what, value: send) in sends.entries) {
      final d = EchoingChurchData(_Waiting());
      send(d).ignore();
      expect(d.saving, isTrue, reason: what);
      d.close();
    }
  });
}

/// Church data whose every write is still on its way.
class _Waiting implements ChurchData {
  @override
  final calendar = _WaitingCalendar();
  @override
  final joining = _WaitingJoining();
  @override
  final attendance = _WaitingAttendance();
  @override
  final unavailable = _WaitingUnavailable();

  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

class _WaitingCalendar implements CalendarData {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

class _WaitingJoining implements JoiningData {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

class _WaitingAttendance implements AttendanceData {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

class _WaitingUnavailable implements UnavailableData {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

/// Church data whose rosters come back with 陳志豪 wherever 王牧師 was put.
class _Overwritten implements ChurchData {
  _Overwritten(this._inner);

  final ChurchData _inner;

  @override
  Stream<List<Roster>> rosters({required Day from}) => _inner
      .rosters(from: from)
      .map(
        (list) => [
          for (final r in list) r.duties.any((d) => d.people.contains('王牧師')) ? withPeople(r, '司會', ['陳志豪']) : r,
        ],
      );

  @override
  Future<void> compareAndSetRosters(RosterChange change) => _inner.compareAndSetRosters(change);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
