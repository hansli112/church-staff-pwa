import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/plan_weeks.dart';
import 'package:martha/domain/serving_around.dart';

const sunday = Service(id: 'sunday', name: '主日崇拜', weekday: DateTime.sunday, duties: ['司會', '司琴', '招待']);

Roster day(int month, int date, List<Duty> duties, {String type = 'sunday'}) =>
    Roster(type: type, day: Day(2026, month, date), duties: duties);

void main() {
  group('排好幾週 (#90)', () {
    test('columns: the template’s duties I arrange, then others the days have', () {
      final days = [
        day(10, 4, const [Duty(role: '司琴'), Duty(role: '敬拜')]),
      ];
      expect(planDuties(sunday, days, const Arranges.all()), ['司會', '司琴', '招待', '敬拜']);
      expect(planDuties(sunday, days, const Arranges.only({'司琴', '敬拜'})), ['司琴', '敬拜']);
    });

    test('opens at the month of the first day with a duty nobody is on', () {
      final days = [
        day(10, 25, const [
          Duty(role: '司琴', people: ['美玉']),
          Duty(role: '招待'),
        ]),
        day(11, 1, const [Duty(role: '司琴')]),
      ];
      expect(firstGap(days, ['司琴']), Day(2026, 11, 1), reason: '招待 is not mine');
      expect(firstGap(days, ['招待']), Day(2026, 10, 1));
      expect(firstGap(days.take(1), ['司琴']), isNull);
    });

    test('the days by month: saved ones and drafts on the weekday, from today on', () {
      final months = planMonths(
        service: sunday,
        saved: [
          day(10, 14, const [Duty(role: '司琴')]),
        ],
        today: Day(2026, 10, 1),
        month: Day(2026, 10, 1),
        months: 2,
      );
      expect([for (final m in months) m.month], [Day(2026, 10, 1), Day(2026, 11, 1)]);
      // The week of the 18th has the saved Wednesday instead.
      expect([for (final d in months.first.days) d.day.day], [4, 11, 14, 25]);
      expect(months.last.days.map((d) => d.day.day), [1, 8, 15, 22, 29]);
      expect(months.last.days.every((d) => !d.saved), isTrue);
    });

    test('across a year, and a month with no day left out', () {
      final months = planMonths(
        service: sunday,
        saved: const [],
        today: Day(2026, 12, 28),
        month: Day(2026, 12, 1),
        months: 2,
      );
      expect([for (final m in months) m.month], [Day(2027, 1, 1)], reason: 'December has no Sunday left');
      expect(months.single.days.first.day, Day(2027, 1, 3));
      expect(addMonths(Day(2026, 11, 1), 3), Day(2027, 2, 1));
    });

    test('a 事工’s duty the template lacks is a column once a day has it', () {
      final days = [
        day(10, 4, const [Duty(role: '司會'), Duty(role: '敬拜')]),
        day(10, 11, const [Duty(role: '敬拜')]),
      ];
      expect(planDuties(sunday, days, const Arranges.only({'敬拜', '鼓'})), ['敬拜']);
      expect(firstGap(days, ['敬拜']), Day(2026, 10, 1));
    });
  });

  group('what someone serves around a day (#90)', () {
    Duty on(String role, String name, String uid) => Duty(role: role, people: [name], uids: {name: uid});

    test('other days in its month anywhere, and what else on the day; the day itself not counted', () {
      final here = day(10, 11, [on('司琴', '美玉', 'mei')]);
      final retreat = Roster(
        type: '',
        day: Day(2026, 10, 10),
        duties: [on('招待', '美玉', 'mei')],
        forEvent: RosterEvent(eventId: 'x1', title: '退修會', lastDay: Day(2026, 10, 11)),
      );
      final around = servingAround(
        here,
        [
          here,
          day(10, 4, [on('司琴', '美玉', 'mei'), on('招待', '美玉', 'mei')]),
          day(10, 4, [on('司琴', '美玉', 'mei')]),
          day(11, 1, [on('司琴', '美玉', 'mei')]),
          day(10, 11, [on('司會', '美玉', 'mei'), on('司琴', '志豪', 'hao')], type: 'youth'),
          retreat,
        ],
        nameOf: (r) => r.forEvent?.title ?? (r.type == 'youth' ? '青年崇拜' : '主日崇拜'),
      );
      expect(around['mei']!.inMonth, 3, reason: 'the 4th once, youth on the 11th, the retreat');
      expect([for (final o in around['mei']!.sameDay) '${o.name} ${o.duties.join('、')}'], ['青年崇拜 司會', '退修會 招待']);
      expect(around['hao']!.inMonth, 1);
    });

    test('a uid whose name is no longer listed serves nothing', () {
      final around = servingAround(
        day(10, 11, const []),
        [
          day(10, 4, const [
            Duty(role: '司琴', uids: {'美玉': 'mei'}),
          ]),
        ],
        nameOf: (_) => '主日崇拜',
      );
      expect(around, isEmpty);
    });
  });
}
