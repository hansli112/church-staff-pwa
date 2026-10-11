import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/schedule.dart';

void main() {
  test('the rolling draft horizon does not hide already arranged far-future services', () {
    const service = Service(id: 'sunday', name: '主日崇拜', weekday: DateTime.sunday, duties: ['司琴']);
    final far = Roster(type: 'sunday', day: Day(2027, 7, 4));
    final shown = upcomingRosters(service: service, saved: [far], from: Day(2026, 10, 1));

    expect(shown.where((r) => !r.saved).length, 13);
    expect(shown.last, far);
  });

  test('personal duties use only the assigned uid, not guest or other members with the same name', () {
    final bound = Roster(
      type: 'sunday',
      day: Day(2026, 10, 4),
      duties: const [
        Duty(role: '外請', people: ['John Chen']),
        Duty(role: '另一位同工', people: ['John Chen'], uids: {'John Chen': 'someone-else'}),
        Duty(role: '已綁定', people: ['改名後名稱'], uids: {'改名後名稱': 'john'}),
      ],
    );
    final guestOnly = Roster(
      type: 'sunday',
      day: Day(2026, 10, 11),
      duties: const [
        Duty(role: '外請', people: ['John Chen']),
      ],
    );

    expect(bound.dutiesOf(uid: 'john'), ['已綁定']);
    final mine = myServices([bound, guestOnly], uid: 'john');
    expect(mine.map((s) => s.roster.day.key), ['2026-10-04']);
    expect(mine.single.duties, ['已綁定']);
  });
}
