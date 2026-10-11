import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/domain/models.dart';

import 'contract_suite.dart';
import 'world.dart';

void serviceCasContractTests(Future<ContractWorld> Function() open) {
  test('duty rename atomically moves zone assignments and staff order without rewriting history', () async {
    final g = await Grace.open(await open());
    final oldRoster = sundayOn(
      18,
      duties: const [
        Duty(role: '司會', people: ['林同工']),
      ],
    );
    await g.church.saveRoster(oldRoster);
    await g.church.updateStaffOrder('sunday', {
      '司會': ['林同工'],
    });
    final next = sunday.copyWith(duties: ['主持', '司琴', '招待']);
    await g.church.compareAndSetService(before: sunday, after: next, dutyRename: (from: '司會', to: '主持'));
    final member = await g.church.member(g.editor).first;
    expect(member!.zones.single.duties, ['主持']);
    final order = await g.church.staffOrder('sunday').first;
    expect(order.rankingOf('主持'), ['林同工']);
    expect(order.rankingOf('司會'), isEmpty);
    expect(await g.church.allRosters(), [oldRoster]);
    await expectLater(
      g.church.compareAndSetService(before: sunday, after: next),
      fails(CloudErrorCode.conflict),
    );
  });

  test('single-service CAS preserves concurrent changes to other services', () async {
    final g = await Grace.open(await open());
    final changedYouth = youth.copyWith(name: '青年聚會');
    await g.church.saveServices([sunday, changedYouth]);
    await g.church.compareAndSetService(
      before: sunday,
      after: sunday.copyWith(name: '主日聚會'),
    );
    final settings = await g.church.services().first;
    expect(settings.byId('sunday')!.name, '主日聚會');
    expect(settings.byId('youth'), changedYouth);
  });
}
