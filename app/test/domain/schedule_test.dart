import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/schedule.dart';

void main() {
  const sunday = Service(
    id: 'sunday',
    name: '主日崇拜',
    weekdays: [DateTime.sunday],
    duties: ['司會', '司琴'],
  );
  final thursday = Day(2026, 10, 1);

  test('fills each week with a draft from the template', () {
    final rosters = upcomingRosters(
      service: sunday,
      saved: const [],
      from: thursday,
      weeks: 3,
    );
    expect(rosters.map((r) => r.day.key), [
      '2026-10-04',
      '2026-10-11',
      '2026-10-18',
    ]);
    expect(rosters.every((r) => !r.saved), isTrue);
    expect(rosters.first.duties.map((d) => d.role), ['司會', '司琴']);
    expect(rosters.first.duties.first.people, isEmpty);
  });

  test('a saved roster replaces the draft for its week', () {
    final saved = Roster(
      type: 'sunday',
      day: Day(2026, 10, 10), // moved to Saturday that week
      duties: const [
        Duty(role: '司會', people: ['王大明']),
      ],
    );
    final rosters = upcomingRosters(
      service: sunday,
      saved: [saved],
      from: thursday,
      weeks: 2,
    );
    expect(rosters.map((r) => r.day.key), ['2026-10-04', '2026-10-10']);
    expect(rosters[1].saved, isTrue);
  });

  test('ignores other services and past days', () {
    final rosters = upcomingRosters(
      service: sunday,
      saved: [
        Roster(type: 'youth', day: Day(2026, 10, 4)),
        Roster(type: 'sunday', day: Day(2026, 9, 27)),
      ],
      from: thursday,
      weeks: 1,
    );
    expect(rosters.single.saved, isFalse);
    expect(rosters.single.day.key, '2026-10-04');
  });

  test('includes today', () {
    final rosters = upcomingRosters(
      service: sunday,
      saved: const [],
      from: Day(2026, 10, 4),
      weeks: 1,
    );
    expect(rosters.single.day.key, '2026-10-04');
  });

  group('a service on several weekdays', () {
    const morning = Service(id: 'morning', name: '晨更', weekdays: [1, 2, 3, 4, 5], duties: ['帶領']);

    test('has a day on each of them', () {
      final rosters = upcomingRosters(service: morning, saved: const [], from: thursday, weeks: 2);
      expect(rosters.map((r) => r.day.key), [
        '2026-10-01',
        '2026-10-02',
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
        '2026-10-08',
        '2026-10-09',
      ]);
    });

    test('one saved on one of them takes its place alone; one saved off them, none', () {
      final rosters = upcomingRosters(
        service: morning,
        saved: [
          Roster(type: 'morning', day: Day(2026, 10, 6)),
          Roster(type: 'morning', day: Day(2026, 10, 10)), // Saturday, since dropped
        ],
        from: Day(2026, 10, 5),
        weeks: 1,
      );
      expect(rosters.map((r) => (r.day.key, r.saved)), [
        ('2026-10-05', false),
        ('2026-10-06', true),
        ('2026-10-07', false),
        ('2026-10-08', false),
        ('2026-10-09', false),
        ('2026-10-10', true),
      ]);
    });
  });

  test("a saved day's duties show in its service's order; ones the service lacks after them", () {
    final saved = Roster(
      type: 'sunday',
      day: Day(2026, 10, 4),
      duties: const [
        Duty(role: '司琴'),
        Duty(role: '奉獻禱告'),
        Duty(role: '司會'),
        Duty(role: '歌者 2'),
      ],
    );
    expect(
      dutiesInOrder(saved, const ['司會', '歌者 2', '司琴']).map((d) => d.role),
      ['司會', '歌者 2', '司琴', '奉獻禱告'],
    );
  });

  group('myServices', () {
    test('finds days only by explicitly bound uid and never by an unbound name', () {
      final rosters = [
        Roster(
          type: 'sunday',
          day: Day(2026, 10, 4),
          duties: const [
            Duty(role: '司會', people: ['王大明'], uids: {'王大明': 'u1'}),
            Duty(role: '司琴', people: ['李小美']),
          ],
        ),
        Roster(
          type: 'sunday',
          day: Day(2026, 10, 11),
          duties: const [
            Duty(role: '司會', people: ['王大明'], uids: {'王大明': 'u2'}),
          ],
        ),
      ];
      final mine = myServices(rosters, uid: 'u1');
      expect(mine.length, 1);
      expect(mine.single.roster.day.key, '2026-10-04');
      expect(mine.single.duties, ['司會']);

      final unbound = myServices(rosters, uid: 'u9');
      expect(unbound, isEmpty);
    });
  });
}
