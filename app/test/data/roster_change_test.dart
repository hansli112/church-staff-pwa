import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/roster_news.dart';
import 'package:martha/domain/staff_order.dart';

Roster sundayOn(int day) => Roster(type: 'sunday', day: Day(2026, 10, day));

const sunday = Service(id: 'sunday', name: '主日', weekday: DateTime.sunday, duties: ['司琴']);

void main() {
  test('a change names exactly the documents it touches, before and after', () {
    final a = sundayOn(4), b = sundayOn(11);
    expect(() => RosterChange(before: {a.id: null}, after: {b.id: b}), throwsArgumentError);
    expect(() => RosterChange(before: {'x': null}, after: {'x': a}), throwsArgumentError);
    expect(() => RosterChange(before: {'a/b': null}, after: {'a/b': null}), throwsArgumentError);
  });

  test('alongside rosters, a service may only gain or lose common events', () {
    final renamed = sunday.copyWith(name: '主日崇拜');
    expect(
      () => RosterChange(before: const {}, after: const {}, serviceChange: (before: sunday, after: renamed)),
      throwsArgumentError,
    );
    final tagged = sunday.copyWith(events: const [EventTag(name: '聖餐', color: 0)]);
    RosterChange(before: const {}, after: const {}, serviceChange: (before: sunday, after: tagged));
  });

  test('more than one transaction can hold is refused before reaching a backend', () {
    final days = [for (var i = 0; i < 500; i++) Roster(type: 'sunday', day: Day(2027, 1, 1).addDays(i))];
    final before = {for (final r in days) r.id: null};
    final after = {for (final r in days) r.id: r};
    RosterChange(before: before, after: after);
    expect(
      () => RosterChange(
        before: before,
        after: after,
        staffOrder: (serviceType: 'sunday', before: StaffOrder(), after: StaffOrder()),
      ),
      throwsA(isA<CloudException>().having((e) => e.reason, 'reason', CloudReason.tooManyChanges)),
    );
  });

  test('its reverse puts back every document, the staff order and the service', () {
    final a = sundayOn(4);
    final tagged = sunday.copyWith(events: const [EventTag(name: '聖餐', color: 0)]);
    final ranked = StaffOrder({
      '司琴': ['甲'],
    });
    final change = RosterChange(
      before: {a.id: null},
      after: {a.id: a},
      via: RosterVia.import,
      staffOrder: (serviceType: 'sunday', before: StaffOrder(), after: ranked),
      serviceChange: (before: sunday, after: tagged),
    );
    final back = change.reversed;
    expect(back.before, {a.id: a});
    expect(back.after, {a.id: null});
    expect(back.via, RosterVia.import);
    expect((back.staffOrder!.before, back.staffOrder!.after), (ranked, StaffOrder()));
    expect((back.serviceChange!.before, back.serviceChange!.after), (tagged, sunday));
  });

  test('a caller changing its maps afterwards does not change the write', () {
    final a = sundayOn(4);
    final before = <String, Roster?>{a.id: null};
    final after = <String, Roster?>{a.id: a};
    final change = RosterChange(before: before, after: after);
    after[a.id] = null;
    expect(change.after, {a.id: a});
  });
}
