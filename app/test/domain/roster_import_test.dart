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
  test('invalid import data reports language-neutral issues with item positions', () {
    final p = plan([
      {
        'date': '2026-10-04',
        'duties': [
          {'role': '司會', 'people': []},
          {
            'role': '司琴',
            'people': [42],
          },
        ],
        'events': [
          {'name': '聖餐', 'color': 6},
        ],
      },
    ]);
    final issues = List<Object>.from(p.report.errors[1]!);
    expect(issues, isNot(contains(isA<String>())));
    expect(p.report.errors[1]!.map((issue) => issue.code), [ImportIssueCode.peopleArray, ImportIssueCode.eventColor]);
    expect(p.report.errors[1]!.first.args, {'index': 2});
    expect(p.report.errors[1]!.last.args, {'index': 1});
  });

  test(
    'duplicate full names need a confirmed UID, and a removed confirmed member cannot fall back to name matching',
    () {
      const duplicates = [Member(uid: 'a', name: '陳小明'), Member(uid: 'b', name: '陳小明')];
      final rows = [
        {
          'date': '2026-10-04',
          'duties': [
            {
              'role': '司會',
              'people': ['陳小明'],
            },
          ],
        },
      ];
      ImportPlan withMembers(List<Member> current, {Map<String, ImportPersonChoice> choices = const {}}) => planImport(
        rows: rows,
        service: service,
        members: current,
        saved: const [],
        order: StaffOrder(),
        today: today,
        people: choices,
      );
      final unresolved = withMembers(duplicates);
      expect(unresolved.canApply, isFalse);
      expect(unresolved.report.unresolved['陳小明']!.map((m) => m.uid), ['a', 'b']);
      final confirmed = withMembers(duplicates, choices: const {'陳小明': ImportPersonChoice.member('b')});
      expect(confirmed.canApply, isTrue);
      expect(confirmed.rosters.single.duties.first.uids, {'陳小明': 'b'});
      final stale = withMembers([duplicates.first], choices: const {'陳小明': ImportPersonChoice.member('b')});
      expect(stale.canApply, isFalse);
      expect(stale.rosters.single.duties.first.uids, isEmpty);
    },
  );

  test('legacy event colors and alternate shapes cannot be accepted as canonical data', () {
    for (final event in [
      '聖餐',
      {'name': '聖餐', 'color': 0xffe53935},
      {'name': '聖餐', 'color': '0'},
      {'name': '聖餐', 'color': 0.0},
      {'name': '聖餐', 'color': -1},
      {'name': '聖餐', 'color': 6},
      {'name': '聖餐'},
      {'name': '聖餐', 'color': 0, 'argb': 1},
    ]) {
      final p = plan([
        {
          'date': '2026-10-04',
          'duties': [],
          'events': [event],
        },
      ]);
      expect(p.canApply, isFalse, reason: '$event');
      expect(p.report.errors[1], isNotEmpty, reason: '$event');
    }
  });

  test('only exact unique names link a UID; an abbreviation remains a confirmation candidate', () {
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
            'people': ['林大華'],
          },
        ],
      },
    ]);
    final r = p.rosters.single;
    expect(r.duties.firstWhere((d) => d.role == '司會').people, ['小明']);
    expect(r.duties.firstWhere((d) => d.role == '司會').uids, isEmpty);
    expect(r.duties.firstWhere((d) => d.role == '招待').uids, {'林大華': 'u2'});
    expect(p.report.notInList['小明'], ['陳小明']);
  });

  test('malformed people and legacy event strings are invalid rows, not successful imports', () {
    final p = plan([
      {'date': '2026-10-04', 'duties': []},
      {
        'date': '2026-10-11',
        'duties': [
          {
            'role': '司琴',
            'people': [42],
          },
        ],
        'events': ['聖餐'],
      },
    ]);
    expect(p.report.badRows, [2]);
    expect(p.rosters.map((r) => r.day.key), ['2026-10-04']);
  });

  test('confirmed candidate binds its UID; explicit guest never auto-links an exact name', () {
    final p = planImport(
      rows: [
        {
          'date': '2026-10-04',
          'duties': [
            {
              'role': '招待',
              'people': ['小明', '林大華'],
            },
          ],
        },
      ],
      service: service,
      members: members,
      saved: const [],
      order: StaffOrder(),
      today: today,
      people: const {
        '小明': ImportPersonChoice.member('u1'),
        '林大華': ImportPersonChoice.guest(),
      },
    );
    final duty = p.rosters.single.duties.firstWhere((d) => d.role == '招待');
    expect(duty.people, ['陳小明', '林大華']);
    expect(duty.uids, {'陳小明': 'u1'});
    expect(p.canApply, isTrue);
  });

  test('canonical event colors survive import and member sheet order is applied', () {
    final order = StaffOrder({
      '招待': ['林大華', '陳小明'],
    });
    final p = plan([
      {
        'date': '2026-10-04',
        'duties': [
          {
            'role': '招待',
            'people': ['陳小明', '林大華'],
          },
        ],
        'events': [
          {'name': '聖餐', 'color': 5},
        ],
      },
    ], order: order);
    expect(p.rosters.single.events, [const EventTag(name: '聖餐', color: 5)]);
    expect(p.order.rankingOf('招待'), ['陳小明', '林大華']);
    expect(p.rosters.single.duties.firstWhere((d) => d.role == '招待').people, ['陳小明', '林大華']);
  });

  test('merge preserves unmentioned duties and events; replacement exposes what will be removed', () {
    final before = Roster(
      type: 'sunday',
      day: Day(2026, 10, 4),
      duties: const [
        Duty(role: '司會', people: ['林大華'], uids: {'林大華': 'u2'}),
      ],
      events: const [EventTag(name: '聖餐', color: 0)],
    );
    final rows = [
      {
        'date': '2026-10-04',
        'duties': [
          {
            'role': '司琴',
            'people': ['陳小明'],
          },
        ],
        'events': [
          {'name': '浸禮', 'color': 2},
        ],
      },
    ];
    final merged = plan(rows, saved: [before]);
    expect(merged.rosters.single.duties.map((d) => d.role), ['司會', '司琴']);
    expect(merged.rosters.single.events.map((e) => e.name), ['聖餐', '浸禮']);
    final replacement = planImport(
      rows: rows,
      service: service,
      members: members,
      saved: [before],
      order: StaffOrder(),
      today: today,
      mode: ImportMode.replace,
    );
    expect(replacement.rosters.single.duties.map((d) => d.role), ['司琴']);
    expect(replacement.rosters.single.events.map((e) => e.name), ['浸禮']);
    expect(replacement.changes[before.id]!.before, before);
    expect(replacement.changes[before.id]!.after, replacement.rosters.single);
  });

  test('unresolved names and invalid rows block apply; empty people has no legacy placeholder semantics', () {
    final unresolved = plan([
      {
        'date': '2026-10-04',
        'duties': [
          {
            'role': '司琴',
            'people': ['待定'],
          },
        ],
      },
    ]);
    expect(unresolved.canApply, isFalse);
    expect(unresolved.report.unresolved.keys, ['待定']);
    final invalid = plan([
      {'date': '2026-10-04', 'duties': []},
      {
        'date': '2026-10-11',
        'duties': [
          {'role': '司琴', 'people': null},
        ],
      },
    ]);
    expect(invalid.canApply, isFalse);
    expect(invalid.report.errors[2], isNotEmpty);
  });

  test('preview reports repairable qualification, duty and common-event gaps without changing settings', () {
    final p = plan([
      {
        'date': '2026-10-04',
        'duties': [
          {
            'role': '鼓',
            'people': ['陳小明'],
          },
        ],
        'events': [
          {'name': '浸禮', 'color': 2},
        ],
      },
    ]);
    expect(p.report.unknownDuties, {'鼓'});
    expect(p.report.missingQualifications.single.member.uid, 'u1');
    expect(p.report.missingQualifications.single.role, '鼓');
    expect(p.report.unknownEvents, [const EventTag(name: '浸禮', color: 2)]);
    expect(p.canApply, isTrue, reason: 'one-day arrangements do not grant settings or member permissions');
    expect(service.duties, ['司會', '司琴', '招待']);
    expect(members.first.zones, isEmpty);
  });

  test('full exact names bind UIDs and canonical events keep the supplied palette color', () {
    final p = plan([
      {
        'date': '2026-10-04',
        'duties': [
          {
            'role': '司會',
            'people': ['陳小明'],
          },
          {
            'role': '招待',
            'people': ['林大華', '陳小明'],
          },
        ],
        'events': [
          {'name': '聖餐', 'color': 0},
        ],
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

  test('empty people clears a mentioned duty; an unmentioned duty is kept in merge mode', () {
    final p = plan(
      [
        {
          'date': '2026-10-04',
          'duties': [
            {
              'role': '司會',
              'people': [],
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
    expect(r.duties.firstWhere((d) => d.role == '司琴').people, ['林大華'], reason: 'unmentioned duty stays');
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

  test('importing events cannot relearn ordering from unmentioned saved duties', () {
    final order = StaffOrder({
      '招待': ['陳小明', '林大華'],
    });
    final p = plan(
      [
        {
          'date': '2026-10-04',
          'duties': [],
          'events': [
            {'name': '聖餐', 'color': 0},
          ],
        },
      ],
      order: order,
      saved: [
        Roster(
          type: 'sunday',
          day: Day(2026, 10, 4),
          duties: const [
            Duty(role: '招待', people: ['林大華', '陳小明'], uids: {'林大華': 'u2', '陳小明': 'u1'}),
          ],
        ),
      ],
    );
    expect(p.order, order);
  });

  test('each invalid row has a clear error and duplicate dates never report successful apply', () {
    final p = plan([
      {'date': '2026-10-04', 'duties': []},
      {'date': '2026-10-04', 'duties': []},
      'not a row',
    ]);
    expect(p.canApply, isFalse);
    expect(p.report.errors[2]!.single.code, ImportIssueCode.duplicateDate);
    expect(p.report.errors[3]!.single.code, ImportIssueCode.rowObject);
  });

  test('two sheet labels resolving to one name block import rather than collapsing an assignment', () {
    final p = planImport(
      rows: [
        {
          'date': '2026-10-04',
          'duties': [
            {
              'role': '招待',
              'people': ['小明', '陳小明'],
            },
          ],
        },
      ],
      service: service,
      members: members,
      saved: const [],
      today: today,
      order: StaffOrder(),
      people: const {'小明': ImportPersonChoice.member('u1')},
    );
    expect(p.canApply, isFalse);
    expect(p.report.errors[1]!.single.code, ImportIssueCode.resolvedDuplicatePeople);
    expect(p.report.errors[1]!.single.args, {'role': '招待'});
  });

  test('a guest sharing a member name cannot alter that member staff ranking', () {
    final p = planImport(
      rows: [
        {
          'date': '2026-10-04',
          'duties': [
            {
              'role': '招待',
              'people': ['林大華', '陳小明'],
            },
          ],
        },
      ],
      service: service,
      members: members,
      saved: const [],
      today: today,
      order: StaffOrder({
        '招待': ['陳小明', '林大華'],
      }),
      people: const {'林大華': ImportPersonChoice.guest()},
    );
    expect(p.order.rankingOf('招待'), ['陳小明', '林大華']);
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
