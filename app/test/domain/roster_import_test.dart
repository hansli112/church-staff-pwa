import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/roster_import.dart';
import 'package:martha/domain/staff_order.dart';

const service = Service(
  id: 'sunday',
  name: '主日',
  weekday: 7,
  duties: ['司會', '司琴', '招待'],
  events: [EventTag(name: '聖餐', color: 0)],
);
const members = [
  Member(uid: 'u1', name: '陳小明'),
  Member(uid: 'u2', name: '林大華'),
  Member(uid: 'u3', name: '黃雅婷'),
  Member(uid: 'u4', name: '王大明'),
  Member(uid: 'u5', name: '李大明'),
  Member(uid: 'u6', name: '陳志明'),
];
final today = Day(2026, 10, 1);

ImportPlan plan(List<dynamic> rows, {List<Roster> saved = const [], StaffOrder? order}) => planImport(
  rows: rows,
  service: service,
  members: members,
  saved: saved,
  order: order ?? StaffOrder(),
  today: today,
);

void main() {
  test('full names and unique surname-less names match members, with uids', () {
    final p = plan([
      {
        'date': '2026-10-04',
        'duties': [
          {
            'role': '司會',
            'people': ['小明'],
          },
          {
            'role': '招待',
            'people': ['林大華', '陳小明'],
          },
        ],
        'events': ['聖餐'],
      },
    ]);
    final r = p.rosters.single;
    final mc = r.duties.firstWhere((d) => d.role == '司會');
    expect(mc.people, ['陳小明']);
    expect(mc.uids, {'陳小明': 'u1'});
    expect(r.events.single.color, 0, reason: 'common event colour');
    expect(r.duties.map((d) => d.role), ['司會', '司琴', '招待'], reason: 'template duties kept');
    expect(p.report.isClean, isTrue);
  });

  test('a suffix two members share is written as is and reported', () {
    final p = plan([
      {
        'date': '2026-10-04',
        'duties': [
          {
            'role': '司會',
            'people': ['大明'],
          },
        ],
      },
    ]);
    final mc = p.rosters.single.duties.firstWhere((d) => d.role == '司會');
    expect(mc.people, ['大明']);
    expect(mc.uids, isEmpty);
    expect(p.report.ambiguous, {'大明'});
  });

  test('one character off is only a hint, never applied', () {
    final p = plan([
      {
        'date': '2026-10-04',
        'duties': [
          {
            'role': '司琴',
            'people': ['陳志豪', '雅亭'],
          },
        ],
      },
    ]);
    final piano = p.rosters.single.duties.firstWhere((d) => d.role == '司琴');
    expect(piano.people, ['陳志豪', '雅亭']);
    expect(piano.uids, isEmpty);
    expect(p.report.notInList['陳志豪'], ['陳志明']);
    expect(p.report.notInList['雅亭'], ['黃雅婷']);
  });

  test('待定 is nobody; 暫停 drops the duty that week', () {
    final p = plan(
      [
        {
          'date': '2026-10-04',
          'duties': [
            {
              'role': '司會',
              'people': ['待定'],
            },
            {
              'role': '司琴',
              'people': ['暫停'],
            },
          ],
        },
      ],
      saved: [
        Roster(
          type: 'sunday',
          day: Day(2026, 10, 4),
          duties: const [
            Duty(role: '司琴', people: ['林大華']),
          ],
        ),
      ],
    );
    final r = p.rosters.single;
    expect(r.duties.firstWhere((d) => d.role == '司會').people, isEmpty);
    expect(r.duties.firstWhere((d) => d.role == '司琴').people, ['林大華'], reason: '暫停 leaves it alone');
  });

  test('past days, duplicates, unknown duties and broken rows are reported', () {
    final p = plan([
      {'date': '2026-09-27', 'duties': []},
      {
        'date': '2026-10-04',
        'duties': [
          {
            'role': '鼓',
            'people': ['陳小明'],
          },
        ],
      },
      {'date': '2026-10-04', 'duties': []},
      'garbage',
      {'date': '10/11'},
      {'date': 20261018},
    ]);
    expect(p.report.pastDays, ['2026-09-27']);
    expect(p.report.unknownDuties, {'鼓'});
    expect(p.report.badRows, [3, 4, 5, 6]);
    expect(p.rosters.length, 1);
  });

  test('learns staff order from the sheet, members only', () {
    final p = plan(
      [
        for (final d in ['2026-10-04', '2026-10-11'])
          {
            'date': d,
            'duties': [
              {
                'role': '招待',
                'people': ['黃雅婷', '外請', '陳小明'],
              },
            ],
          },
      ],
      order: StaffOrder({
        '招待': ['陳小明', '林大華'],
      }),
    );
    expect(p.order.rankingOf('招待'), ['黃雅婷', '陳小明', '林大華']);
    expect(p.rosters.first.duties.firstWhere((d) => d.role == '招待').people, ['黃雅婷', '陳小明', '外請']);
  });
}
