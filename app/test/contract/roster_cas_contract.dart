import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/roster_news.dart';
import 'package:martha/domain/staff_order.dart';

import 'contract_suite.dart';
import 'world.dart';

/// The same public atomic-write contract runs on memory and Firebase.
void rosterCasContractTests(Future<ContractWorld> Function() open) {
  test('a stale staff order rejects the entire import without saving any roster', () async {
    final g = await Grace.open(await open());
    final roster = sundayOn(
      18,
      duties: const [
        Duty(role: '司琴', people: ['甲', '乙']),
      ],
    );
    await g.church.putStaffOrder('sunday', {
      '司琴': ['乙', '甲'],
    });
    await expectLater(
      g.church.compareAndSetRosters(
        RosterChange(
          before: {roster.id: null},
          after: {roster.id: roster},
          via: RosterVia.import,
          staffOrder: (
            serviceType: 'sunday',
            before: StaffOrder(),
            after: StaffOrder({
              '司琴': ['甲', '乙'],
            }),
          ),
        ),
      ),
      fails(CloudErrorCode.conflict),
    );
    expect(await g.church.readOnce.rosters(), isEmpty);
    expect((await g.church.staffOrder('sunday').first).rankingOf('司琴'), ['乙', '甲']);
  });

  test('bulk compare-and-set creates and deletes atomically, and undo restores absence', () async {
    final g = await Grace.open(await open());
    final first = sundayOn(
      18,
      duties: const [
        Duty(role: '司琴', people: ['甲']),
      ],
    );
    final second = sundayOn(
      25,
      duties: const [
        Duty(role: '司琴', people: ['乙']),
      ],
    );
    await g.church.putRoster(first);
    final before = <String, Roster?>{first.id: first, second.id: null};
    final after = <String, Roster?>{first.id: null, second.id: second};

    await g.church.compareAndSetRosters(RosterChange(before: before, after: after));
    expect(await g.church.readOnce.rosters(), [second]);
    await g.church.compareAndSetRosters(RosterChange(before: after, after: before));
    expect(await g.church.readOnce.rosters(), [first]);
  });
}
