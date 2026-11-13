import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  final target = findShown(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

/// Joined as 小明, in no service yet.
const ming = Member(uid: 'ming', name: '小明');

/// 王小明 on the rosters, without an account: 小明 by another name.
const wang = PendingMember(
  id: 'old-wang',
  name: '王小明',
  zones: [
    Zone(serviceType: 'sunday', duties: ['招待']),
  ],
  smallGroups: {'joy'},
);

MemoryBackend church({Member as = ming}) {
  final b = seededChurch(as: as, extra: const [ming]);
  b.smallGroups['grace'] = {'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday')};
  b.addPending('grace', wang, rosterIds: [Roster.idFor('sunday', Day(2026, 10, 18))]);
  b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))] = Roster(
    type: 'sunday',
    day: Day(2026, 10, 18),
    duties: const [
      Duty(role: '招待', people: ['王小明'], uids: {'王小明': 'old-wang'}),
    ],
  );
  return b;
}

void main() {
  testWidgets('one in no service finds themself among those without an account, and asks; it can be taken back', (
    tester,
  ) async {
    final b = church();
    await pumpApp(tester, b);
    await tapText(tester, '服事表上已經有你了嗎？');
    expect(findShown('服事表上哪一位是你？'), findsOneWidget);
    expect(findShownContaining('喜樂小組'), findsOneWidget, reason: 'their 小組, to know them by');
    expect(findShownContaining('主日崇拜・招待'), findsOneWidget);
    await tapText(tester, '王小明');
    expect(find.text('你是「王小明」嗎？'), findsOneWidget);
    expect(findShownContaining('管理員確認後，「王小明」的服事和所屬聚會就會接過來'), findsOneWidget);
    await tapText(tester, '送出');

    expect(b.claimAsks['grace']!['ming']!.pendingId, 'old-wang');
    expect(findShown('等管理員確認你是「王小明」'), findsOneWidget);
    expect(findShown('服事表上已經有你了嗎？'), findsNothing);

    await tapText(tester, '取消');
    expect(b.claimAsks['grace']!['ming'], isNull);
    expect(findShown('服事表上已經有你了嗎？'), findsOneWidget);
  });

  testWidgets('with nobody without an account, there is nobody to be', (tester) async {
    final b = church();
    b.pendingMembers['grace']!.clear();
    await pumpApp(tester, b);
    expect(findShown('歡迎加入〈恩典堂〉'), findsOneWidget);
    expect(findShown('服事表上已經有你了嗎？'), findsNothing);
  });

  testWidgets('an admin sees the ask on 同工 and says yes: merged, and the ask gone', (tester) async {
    final b = church(as: pastor);
    b.claimAsks['grace'] = {
      'ming': const ClaimAsk(uid: 'ming', name: '小明', pendingId: 'old-wang', pendingName: '王小明'),
    };
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    expect(findShown('1 位說自己在服事表上'), findsOneWidget);
    expect(findShownContaining('說自己是「王小明」'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('確認小明'));
    await settle(tester);
    expect(find.text('合併「王小明」？'), findsOneWidget);
    expect(findShownContaining('喜樂小組'), findsWidgets);
    await tapText(tester, '合併');

    expect(b.members['grace']!['ming']!.serves('sunday', '招待'), isTrue);
    expect(b.pendingMembers['grace'], isEmpty);
    expect(b.claimAsks['grace'], isEmpty);
    expect(findShownContaining('說自己是'), findsNothing);
  });

  testWidgets('an admin says no: the ask goes, nothing else', (tester) async {
    final b = church(as: pastor);
    b.claimAsks['grace'] = {
      'ming': const ClaimAsk(uid: 'ming', name: '小明', pendingId: 'old-wang', pendingName: '王小明'),
    };
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    await tester.tap(find.bySemanticsLabel('小明不是'));
    await settle(tester);
    expect(find.text('已退回'), findsOneWidget);
    expect(b.claimAsks['grace'], isEmpty);
    expect(b.pendingMembers['grace']!.keys, ['old-wang']);
  });
}
