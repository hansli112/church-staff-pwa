import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/roster_edit.dart';
import 'package:martha/domain/staff_order.dart';

Roster day(int d, Map<String, List<String>> duties) => Roster(
  type: 'sunday',
  day: Day(2026, 10, d),
  duties: [for (final e in duties.entries) Duty(role: e.key, people: e.value)],
);

List<String> people(Roster r, String role) => r.duties.firstWhere((d) => d.role == role).people;

void main() {
  final order = StaffOrder({
    '招待': ['志豪', '美玉', '小明', '阿德'],
  });
  const ids = {'志豪': 'u1', '美玉': 'u2', '小明': 'u3', '阿德': 'u4'};

  group('uniqueNameIds', () {
    test('drops names two members share', () {
      final map = uniqueNameIds(const [
        Member(uid: 'a', name: '王大明'),
        Member(uid: 'b', name: '王大明 '),
        Member(uid: 'c', name: '李小美'),
      ]);
      expect(map, {'李小美': 'c'});
    });
  });

  group('withPeople', () {
    test('sorts by staff order and attaches uids for members only', () {
      final r = withPeople(
        day(4, {'招待': []}),
        '招待',
        ['小明', '外請講員', '志豪', '小明'],
        nameIds: ids,
        order: order,
      );
      expect(people(r, '招待'), ['志豪', '小明', '外請講員']);
      expect(r.duties.single.uids, {'志豪': 'u1', '小明': 'u3'});
    });

    test('adds a duty that is not on the day yet', () {
      final r = withPeople(
        day(4, {
          '司會': ['阿德'],
        }),
        '招待',
        ['美玉'],
        nameIds: ids,
        order: order,
      );
      expect(r.duties.map((d) => d.role), ['司會', '招待']);
    });

    test('withoutDuty removes only that duty', () {
      final r = withoutDuty(
        day(4, {
          '司會': ['阿德'],
          '招待': ['美玉'],
        }),
        '司會',
      );
      expect(r.duties.map((d) => d.role), ['招待']);
    });
  });

  group('swap', () {
    test('the main person stays first after swapping into another week', () {
      final a = day(4, {
        '招待': ['志豪', '小明'],
      });
      final b = day(11, {
        '招待': ['美玉', '阿德'],
      });
      final (a2, b2) = swapPeople(
        '招待',
        SwapSide(a, '志豪'),
        SwapSide(b, '阿德'),
        nameIds: ids,
        order: order,
      );
      expect(people(a2, '招待'), ['小明', '阿德']);
      expect(people(b2, '招待'), ['志豪', '美玉']);
    });

    test('swapping with an empty day moves the person', () {
      final a = day(4, {
        '招待': ['志豪'],
      });
      final b = day(11, {'招待': []});
      final (a2, b2) = swapPeople(
        '招待',
        SwapSide(a, '志豪'),
        SwapSide(b, null),
        nameIds: ids,
        order: order,
      );
      expect(people(a2, '招待'), isEmpty);
      expect(people(b2, '招待'), ['志豪']);
    });

    test('swapping twice undoes it', () {
      final a = day(4, {
        '招待': ['志豪', '小明'],
      });
      final b = day(11, {
        '招待': ['美玉'],
      });
      final (a2, b2) = swapPeople(
        '招待',
        SwapSide(a, '志豪'),
        SwapSide(b, '美玉'),
        nameIds: ids,
        order: order,
      );
      final (a3, b3) = swapPeople(
        '招待',
        SwapSide(a2, '美玉'),
        SwapSide(b2, '志豪'),
        nameIds: ids,
        order: order,
      );
      expect(people(a3, '招待'), ['志豪', '小明']);
      expect(people(b3, '招待'), ['美玉']);
    });

    test('targets: same duty on other days, not people already here', () {
      final from = day(4, {
        '招待': ['志豪', '小明'],
      });
      final targets = swapTargets(
        [
          from,
          day(11, {
            '招待': ['美玉', '小明'],
          }),
          day(18, {'招待': []}),
          day(25, {
            '司會': ['阿德'],
          }),
          day(31, {
            '招待': ['志豪'],
          }),
        ],
        from,
        '招待',
        '志豪',
      );
      expect(targets.map((t) => '${t.roster.day.day}:${t.person}'), [
        '11:美玉',
        '18:null',
      ]);
    });
  });
}
