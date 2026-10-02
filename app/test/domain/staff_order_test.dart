import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff_order.dart';

// Cases ported from self-host test/roster_staff_order_test.dart.

Roster _roster(int day, Map<String, List<String>> duties) => Roster(
  type: 'sunday',
  day: Day(2026, 1, day),
  duties: [
    for (final entry in duties.entries)
      Duty(role: entry.key, people: entry.value),
  ],
);

void main() {
  group('sort', () {
    final order = StaffOrder({
      '招待': ['志豪', '美玉', '小明'],
    });

    test('follows the ranking, not the stored order', () {
      expect(order.sort('招待', ['小明', '志豪']), ['志豪', '小明']);
    });

    test('unranked people go last, keeping their order', () {
      expect(order.sort('招待', ['外請乙', '小明', '外請甲', '志豪']), [
        '志豪',
        '小明',
        '外請乙',
        '外請甲',
      ]);
    });

    test('returns the same list when already sorted', () {
      final people = ['志豪', '小明'];
      expect(identical(order.sort('招待', people), people), isTrue);
      final other = ['小明', '志豪'];
      expect(identical(order.sort('司琴', other), other), isTrue);
    });

    test('applyTo sorts every duty and keeps the object when unchanged', () {
      final roster = _roster(4, {
        '招待': ['小明', '志豪'],
      });
      expect(order.applyTo(roster).duties.single.people, ['志豪', '小明']);
      final sorted = order.applyTo(roster);
      expect(identical(order.applyTo(sorted), sorted), isTrue);
    });
  });

  group('orderedCandidates', () {
    test('ranked first, new people last', () {
      final order = StaffOrder({
        '司琴': ['美玉', '雅婷'],
      });
      expect(order.orderedCandidates('司琴', ['新人', '雅婷', '美玉']), [
        '美玉',
        '雅婷',
        '新人',
      ]);
    });

    test('drops ranked people who are no longer candidates', () {
      final order = StaffOrder({
        '司琴': ['離開的人', '美玉'],
      });
      expect(order.orderedCandidates('司琴', ['美玉']), ['美玉']);
    });
  });

  group('learnFrom', () {
    test('averages positions so one swapped sheet does not win', () {
      final learned = StaffOrder.learnFrom([
        _roster(4, {
          'Vocal': ['雅婷', '阿華'],
        }),
        _roster(11, {
          'Vocal': ['阿華', '雅婷'],
        }),
        _roster(18, {
          'Vocal': ['阿華', '雅婷'],
        }),
      ]);
      expect(learned.rankingOf('Vocal'), ['阿華', '雅婷']);
    });

    test('skips days with one person', () {
      final learned = StaffOrder.learnFrom([
        _roster(4, {
          '司琴': ['美玉'],
        }),
      ]);
      expect(learned.isEmpty, isTrue);
    });
  });

  group('combining', () {
    test('mergedWith keeps people the newer order does not mention', () {
      final stored = StaffOrder({
        '招待': ['志豪', '美玉', '小明', '阿德'],
        '司琴': ['雅婷', '阿華'],
      });
      final next = stored.mergedWith(
        StaffOrder({
          '招待': ['阿德', '美玉', '小明'],
        }),
      );
      expect(next.rankingOf('招待'), ['志豪', '阿德', '美玉', '小明']);
      expect(next.rankingOf('司琴'), ['雅婷', '阿華']);
    });

    test('mergedWith inserts a newcomer after the person before them', () {
      final next =
          StaffOrder({
            '招待': ['志豪', '美玉', '小明'],
          }).mergedWith(
            StaffOrder({
              '招待': ['美玉', '新人', '小明'],
            }),
          );
      expect(next.rankingOf('招待'), ['志豪', '美玉', '新人', '小明']);
    });

    test('changesTo lists only changed roles, null for removed', () {
      final before = StaffOrder({
        '招待': ['美玉', '小明'],
        '司琴': ['雅婷'],
        '鼓': ['阿華'],
      });
      final after = StaffOrder({
        '招待': ['小明', '美玉'],
        '司琴': ['雅婷'],
        '敬拜': ['阿德'],
      });
      final changes = before.changesTo(after);
      expect(changes, {
        '招待': ['小明', '美玉'],
        '敬拜': ['阿德'],
        '鼓': null,
      });
      expect(before.withChanges(changes), after);
      expect(after.changesTo(after), isEmpty);
    });

    test('withRolesRenamed moves the ranking', () {
      final renamed = StaffOrder({
        '招待': ['美玉', '小明'],
      }).withRolesRenamed({'招待': '接待'});
      expect(renamed.rankingOf('招待'), isEmpty);
      expect(renamed.rankingOf('接待'), ['美玉', '小明']);
    });

    test('json round-trips and drops junk', () {
      final order = StaffOrder({
        '招待': ['美玉', '小明'],
      });
      expect(StaffOrder.fromJson(order.toJson()), order);
      final parsed = StaffOrder.fromJson({
        'roles': {
          '招待': ['美玉', 3, '', '小明'],
          '壞掉': 'not a list',
        },
      });
      expect(parsed.rankingOf('招待'), ['美玉', '小明']);
      expect(parsed.rankingOf('壞掉'), isEmpty);
    });
  });
}
