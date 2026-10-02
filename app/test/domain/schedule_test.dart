import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/schedule.dart';

void main() {
  const sunday = Service(
    id: 'sunday',
    name: '主日崇拜',
    weekday: DateTime.sunday,
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

  test('a disabled service shows only what was saved', () {
    final rosters = upcomingRosters(
      service: sunday.copyWith(enabled: false),
      saved: [Roster(type: 'sunday', day: Day(2026, 10, 11))],
      from: thursday,
      weeks: 4,
    );
    expect(rosters.map((r) => r.day.key), ['2026-10-11']);
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

  group('myServices', () {
    test('finds days by uid, and by name only when the name has no uid', () {
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
      final mine = myServices(rosters, uid: 'u1', name: '王大明');
      expect(mine.length, 1);
      expect(mine.single.roster.day.key, '2026-10-04');
      expect(mine.single.duties, ['司會']);

      final hers = myServices(rosters, uid: 'u9', name: '李小美');
      expect(hers.single.duties, ['司琴']);
    });
  });
}
