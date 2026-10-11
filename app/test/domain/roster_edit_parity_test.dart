import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/roster_edit.dart';
import 'package:martha/domain/staff_order.dart';

void main() {
  test('future guest removal previews only unbound exact names in the same service and duty', () {
    final saved = [
      Roster(
        type: 'sunday',
        day: Day(2026, 9, 27),
        duties: const [
          Duty(role: '司琴', people: ['John Chen']),
        ],
      ),
      Roster(
        type: 'sunday',
        day: Day(2026, 10, 1),
        duties: const [
          Duty(role: '司琴', people: ['John Chen']),
        ],
      ),
      Roster(
        type: 'sunday',
        day: Day(2026, 10, 4),
        duties: const [
          Duty(role: '司琴', people: ['John Chen', '李美玉'], uids: {'李美玉': 'mei'}),
        ],
      ),
      Roster(
        type: 'sunday',
        day: Day(2026, 10, 11),
        duties: const [
          Duty(role: '司琴', people: ['John Chen'], uids: {'John Chen': 'john'}),
        ],
      ),
      Roster(
        type: 'sunday',
        day: Day(2026, 10, 18),
        duties: const [
          Duty(role: '招待', people: ['John Chen']),
        ],
      ),
      Roster(
        type: 'youth',
        day: Day(2026, 10, 3),
        duties: const [
          Duty(role: '司琴', people: ['John Chen']),
        ],
      ),
    ];

    final plan = planGuestRemoval(saved: saved, type: 'sunday', role: '司琴', name: 'John Chen', today: Day(2026, 10, 1));

    expect(plan.before.keys, ['2026-10-04_sunday']);
    expect(plan.after.values.single!.duties.single.people, ['李美玉']);
    expect(plan.after.values.single!.duties.single.uids, {'李美玉': 'mei'});
    expect(saved[2].duties.single.people, ['John Chen', '李美玉'], reason: 'preview is not a write');
  });

  test('duty synchronization previews future dates only and preserves people and uid identity', () {
    final historical = Roster(
      type: 'sunday',
      day: Day(2026, 9, 27),
      duties: const [
        Duty(role: '司琴', people: ['李美玉'], uids: {'李美玉': 'mei'}),
      ],
    );
    final next = historical.copyWith(day: Day(2026, 10, 4));
    final far = historical.copyWith(day: Day(2027, 7, 4));

    final plan = planDutyRename(
      saved: [historical, next, far],
      type: 'sunday',
      from: '司琴',
      to: '鋼琴',
      today: Day(2026, 10, 1),
    );

    expect(plan.before.keys, ['2026-10-04_sunday', '2027-07-04_sunday']);
    expect(plan.after.values.first!.duties.single.role, '鋼琴');
    expect(plan.after.values.first!.duties.single.uids, {'李美玉': 'mei'});
    expect(historical.duties.single.role, '司琴');
    expect(next.duties.single.role, '司琴');
  });

  test('common-event renaming previews future wording without recoloring old assignments', () {
    final old = Roster(
      type: 'sunday',
      day: Day(2026, 9, 27),
      events: const [EventTag(name: '聖餐', color: 4)],
    );
    final next = old.copyWith(day: Day(2026, 10, 4));

    final plan = planEventRename(saved: [old, next], type: 'sunday', from: '聖餐', to: '聖餐主日', today: Day(2026, 10, 1));

    expect(plan.before.keys, [next.id]);
    expect(plan.after.values.single!.events, const [EventTag(name: '聖餐主日', color: 4)]);
    expect(old.events, const [EventTag(name: '聖餐', color: 4)]);
  });

  test('moving an arranged guest does not rebind a same-name member', () {
    final first = Roster(
      type: 'sunday',
      day: Day(2026, 10, 4),
      duties: const [
        Duty(role: '司琴', people: ['John Chen']),
      ],
    );
    final second = Roster(
      type: 'sunday',
      day: Day(2026, 10, 11),
      duties: const [Duty(role: '司琴')],
    );

    final (out, into) = swapPeople(
      '司琴',
      SwapSide(first, 'John Chen'),
      SwapSide(second, null),
      nameIds: const {'John Chen': 'john'},
      order: StaffOrder({}),
    );

    expect(out.duties.single.people, isEmpty);
    expect(into.duties.single.people, ['John Chen']);
    expect(into.duties.single.uids, isEmpty);
  });
}
