import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/family.dart';
import 'package:martha/domain/models.dart';

void main() {
  const home = Household(
    id: 'h1',
    people: ['mom', 'kid1', 'dad'],
    noAccount: ['kid1'],
    invited: ['grandma'],
    names: {'mom': '陳志玲', 'kid1': '林小恩', 'dad': '林豪佳', 'grandma': '林奶奶'},
  );

  group('familyOf', () {
    test('everyone but me, those in it before those asked', () {
      final family = familyOf([home], 'mom');
      expect(
        [for (final p in family) (p.id, p.name, p.account, p.asked)],
        [
          ('kid1', '林小恩', false, false),
          ('dad', '林豪佳', true, false),
          ('grandma', '林奶奶', true, true),
        ],
      );
    });

    test('someone in two of my families is listed once', () {
      const other = Household(id: 'h2', people: ['mom', 'kid1'], noAccount: ['kid1'], names: {'kid1': '林小恩'});
      expect(familyOf([home, other], 'mom').map((p) => p.id), ['kid1', 'dad', 'grandma']);
    });

    test('none without a family', () {
      expect(familyOf(const [], 'mom'), isEmpty);
    });
  });

  group('servingWithFamily', () {
    Roster day(Day d, Map<String, String> people) => Roster(
      type: 'sunday',
      day: d,
      duties: [
        for (final e in people.entries) Duty(role: e.key, people: [e.value], uids: {e.value: _uids[e.value]!}),
      ],
    );

    test('my days and my family\'s, soonest first, mine first on a day; nobody asked yet', () {
      final rosters = [
        day(Day(2026, 11, 22), {'司會': '陳志玲', '兒主小幫手': '林小恩'}),
        day(Day(2026, 11, 28), {'敬拜主領': '林豪佳'}),
        day(Day(2026, 11, 29), {'獻詩': '林奶奶'}),
      ];
      final serving = servingWithFamily(rosters, me: 'mom', family: familyOf([home], 'mom'));
      expect(
        [for (final s in serving) (s.service.roster.day.key, s.service.duties.join('、'), s.who?.name)],
        [
          ('2026-11-22', '司會', null),
          ('2026-11-22', '兒主小幫手', '林小恩'),
          ('2026-11-28', '敬拜主領', '林豪佳'),
        ],
      );
    });
  });
}

const _uids = {'陳志玲': 'mom', '林小恩': 'kid1', '林豪佳': 'dad', '林奶奶': 'grandma'};
