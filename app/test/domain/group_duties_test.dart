import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/roster_edit.dart';
import 'package:martha/domain/schedule.dart';
import 'package:martha/domain/staff_order.dart';

// 服事交給小組: a duty on a day given to a 小組 (Duty.groups, its name as
// shown to the 小組's id). Everyone in it holds the duty.

Roster day(int d, List<Duty> duties) => Roster(type: 'sunday', day: Day(2026, 10, d), duties: duties);

const joy = Duty(role: '招待', people: ['美玉', '喜樂小組'], uids: {'美玉': 'mei'}, groups: {'喜樂小組': 'joy'});

void main() {
  group('who holds it', () {
    test('everyone in the 小組, besides those on it by name', () {
      final r = day(4, const [joy]);
      expect(r.dutiesOf(uid: 'hao', smallGroups: {'joy'}), ['招待']);
      expect(r.dutiesOf(uid: 'hao'), isEmpty, reason: 'not in it');
      expect(r.dutiesOf(uid: 'mei', smallGroups: {'joy'}), ['招待'], reason: 'once');
    });

    test('not once its name is off the duty, nor the same name typed', () {
      expect(
        day(4, const [
          Duty(role: '招待', people: [], groups: {'喜樂小組': 'joy'}),
        ]).dutiesOf(uid: 'hao', smallGroups: {'joy'}),
        isEmpty,
      );
      expect(
        day(4, const [
          Duty(role: '招待', people: ['喜樂小組']),
        ]).dutiesOf(uid: 'hao', smallGroups: {'joy'}),
        isEmpty,
      );
    });

    test('which 小組 gives me a duty, for 你的服事; not one I hold by name', () {
      final r = day(4, const [
        joy,
        Duty(role: '司琴', people: ['美玉'], uids: {'美玉': 'mei'}),
      ]);
      expect(r.groupDutiesOf(uid: 'hao', smallGroups: {'joy'}), {'招待': '喜樂小組'});
      expect(r.groupDutiesOf(uid: 'mei', smallGroups: {'joy'}), isEmpty);
    });

    test('我接下來的服事 has the days my 小組 serves', () {
      final mine = myServices(
        [
          day(4, const [joy]),
          day(11, const []),
        ],
        uid: 'hao',
        smallGroups: {'joy'},
      );
      expect([for (final s in mine) s.roster.day], [Day(2026, 10, 4)]);
    });
  });

  group('picking', () {
    final order = StaffOrder({});

    test('a 小組 picked is kept by its id; one already there stays so', () {
      final r = withPeople(
        day(4, const [Duty(role: '招待')]),
        '招待',
        ['喜樂小組', '美玉'],
        nameIds: const {'美玉': 'mei'},
        groupIds: const {'喜樂小組': 'joy'},
        order: order,
      );
      final d = r.duties.single;
      expect(d.groups, {'喜樂小組': 'joy'});
      expect(d.uids, {'美玉': 'mei'});
      final again = withPeople(r, '招待', ['喜樂小組'], nameIds: const {}, order: order);
      expect(again.duties.single.groups, {'喜樂小組': 'joy'});
    });

    test('a member of the same name as the 小組 is not taken for it', () {
      final r = withPeople(
        day(4, const [Duty(role: '招待')]),
        '招待',
        ['喜樂'],
        nameIds: const {'喜樂': 'someone'},
        groupIds: const {'喜樂': 'joy'},
        order: order,
      );
      expect(r.duties.single.uids, isEmpty);
      expect(r.duties.single.groups, {'喜樂': 'joy'});
    });

    test('a 小組 in place of the same name typed is a change', () {
      const typed = Duty(role: '招待', people: ['喜樂小組']);
      expect(pickChanges(typed, ['喜樂小組'], groupIds: const {'喜樂小組': 'joy'}), isTrue);
      expect(pickChanges(joy, ['美玉', '喜樂小組'], groupIds: const {'喜樂小組': 'joy'}), isFalse);
    });

    test('traded with another day, it is still the 小組', () {
      final (a, b) = swapPeople(
        '招待',
        SwapSide(day(4, const [joy]), '喜樂小組'),
        SwapSide(day(11, const [Duty(role: '招待')]), null),
        nameIds: const {},
        order: order,
      );
      expect(a.duties.single.people, ['美玉']);
      expect(a.duties.single.groups, isEmpty);
      expect(b.duties.single.groups, {'喜樂小組': 'joy'});
    });

    test('之後都不排 a typed name leaves a 小組 of that name', () {
      final plan = planGuestRemoval(
        saved: [
          day(11, const [joy]),
        ],
        type: 'sunday',
        role: '招待',
        name: '喜樂小組',
        today: Day(2026, 10, 1),
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('renamed', () {
    test('the 小組 renamed: its name on the duty, and only its', () {
      const d = Duty(role: '招待', people: ['喜樂小組', '恩典小組'], groups: {'喜樂小組': 'joy', '恩典小組': 'grace'});
      final r = d.renamedGroup('joy', '喜樂團契');
      expect(r.people, ['喜樂團契', '恩典小組']);
      expect(r.groups, {'喜樂團契': 'joy', '恩典小組': 'grace'});
    });
  });

  group('stored', () {
    test('kept as groups beside uids, only those listed; none, no field', () {
      final r = day(4, const [
        Duty(role: '招待', people: ['喜樂小組'], groups: {'喜樂小組': 'joy', '別的': 'x'}),
        Duty(role: '司琴', people: ['美玉'], uids: {'美玉': 'mei'}),
      ]);
      final json = rosterToJson(r);
      final duties = json['duties'] as List;
      expect((duties[0] as Map)['groups'], {'喜樂小組': 'joy'});
      expect((duties[1] as Map).containsKey('groups'), isFalse);
      expect(rosterFromJson(json)!.duties.first.groups, {'喜樂小組': 'joy'});
    });
  });
}
