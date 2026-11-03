import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(findShown(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

const meiPending = PendingMember(
  id: 'old-mei',
  name: '李美玉',
  email: 'mei@example.com',
  role: Role.leader,
  groups: {Group.rosterEditors},
  zones: [
    Zone(serviceType: 'sunday', duties: ['司琴']),
  ],
);

/// 恩典堂, moved from self-host, with 李美玉 pending; 李美玉 signs in fresh.
MemoryBackend movedChurch({bool signIn = true}) {
  final b = MemoryBackend(clock: testClock);
  final cid = b.addChurch('恩典堂', id: 'grace');
  b.setServices(cid, const [sundayService]);
  b.addMember(cid, pastor);
  b.addPending(cid, meiPending, rosterIds: [Roster.idFor('sunday', Day(2026, 10, 4))]);
  b.rosters[cid]![Roster.idFor('sunday', Day(2026, 10, 4))] = Roster(
    type: 'sunday',
    day: Day(2026, 10, 4),
    duties: const [
      Duty(role: '司琴', people: ['李美玉'], uids: {'李美玉': 'old-mei'}),
    ],
  );
  if (signIn) b.auth.signInAs('mei@example.com', uid: 'new-mei', name: '美玉');
  return b;
}

void main() {
  testWidgets('signing in with the same email offers to join; joining brings back the rosters', (tester) async {
    final b = movedChurch();
    await pumpApp(tester, b);
    expect(findShown('〈恩典堂〉的同工資料已經搬過來了，要加入嗎？'), findsOneWidget);
    await tapText(tester, '加入');

    final m = b.members['grace']!['new-mei']!;
    expect(m.role, Role.leader);
    // Self-host's roster editing was their 牧區's: its 負責人 now (#82).
    expect(m.groups, isEmpty);
    expect(m.leadTypes, ['sunday']);
    expect(m.serves('sunday', '司琴'), isTrue);
    expect(b.rosters['grace']!.values.single.duties.single.uids, {'李美玉': 'new-mei'});
    expect(b.pendingMembers['grace'], isEmpty);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('我接下來的服事'), findsOneWidget, reason: 'their roster day is theirs again');
  });

  testWidgets('joining is said once in, and not asked again while the rosters are still being pointed at them', (
    tester,
  ) async {
    final b = movedChurch();
    final repoint = b.claimRepointHeld = Completer<void>();
    await pumpApp(tester, b);
    // With 加入 to say yes to, entering a code is the other way in, not the first.
    expect(find.widgetWithText(FilledButton, '輸入邀請碼'), findsNothing);
    expect(findShown('輸入邀請碼'), findsOneWidget);
    await tapText(tester, '加入');

    expect(find.byType(NavigationBar), findsOneWidget, reason: 'in the church already');
    expect(findShown('〈恩典堂〉的同工資料已經搬過來了，要加入嗎？'), findsNothing);
    repoint.complete();
    await settle(tester);
    expect(findShown('已加入〈恩典堂〉'), findsOneWidget);
    expect(findShown('〈恩典堂〉的同工資料已經搬過來了，要加入嗎？'), findsNothing);
  });

  testWidgets('declining joins nothing and does not ask again on this device', (tester) async {
    final b = movedChurch();
    await pumpApp(tester, b);
    await tapText(tester, '不加入');
    expect(findShown('〈恩典堂〉的同工資料已經搬過來了，要加入嗎？'), findsNothing);
    expect(b.members['grace']!.containsKey('new-mei'), isFalse);
    expect(b.pendingMembers['grace']!.containsKey('old-mei'), isTrue, reason: 'kept for the admin');
    expect(find.text('加入你的教會'), findsOneWidget);
  });

  testWidgets('an unverified email is not asked', (tester) async {
    final b = movedChurch(signIn: false);
    await b.auth.registerWithEmail('美玉', 'mei@example.com', 'secret123', AppLanguage.zhHant);
    await pumpApp(tester, b);
    expect(find.text('驗證你的 email'), findsOneWidget);
    expect(find.textContaining('已經搬過來了'), findsNothing);
  });

  testWidgets('the sign-in page tells old password users to register again', (tester) async {
    await pumpApp(tester, MemoryBackend(clock: testClock));
    await tapText(tester, '用 email 登入');
    expect(findShownContaining('從舊版搬過來的同工：舊的密碼不能用'), findsOneWidget);
  });

  testWidgets('an admin can delete pending data, after confirming', (tester) async {
    final b = seededChurch();
    b.pendingMembers['grace'] = {'old-x': const PendingMember(id: 'old-x', name: '舊同工', email: 'x@example.com')};
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    await tapText(tester, '舊同工');
    await tapText(tester, '刪除這筆資料');
    expect(findShown('對方就不能用 email 認領了。服事表上的名字會保留。'), findsOneWidget);
    await tapText(tester, '刪除');
    expect(b.pendingMembers['grace'], isEmpty);
  });

  testWidgets('an admin merges pending data into someone who joined with another email', (tester) async {
    final b = seededChurch(
      extra: const [Member(uid: 'mei-google', name: '美玉', email: 'mei@gmail.com')],
    );
    b.addPending('grace', meiPending, rosterIds: [Roster.idFor('sunday', Day(2026, 10, 18))]);
    b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))] = Roster(
      type: 'sunday',
      day: Day(2026, 10, 18),
      duties: const [
        Duty(role: '司琴', people: ['李美玉'], uids: {'李美玉': 'old-mei'}),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/members/mei-google');
    await tester.scrollUntilVisible(find.text('合併還沒登入的資料'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '合併還沒登入的資料');
    await tapText(tester, '李美玉');
    expect(find.text('合併還沒登入的「李美玉」？'), findsOneWidget);
    expect(findShown('還沒登入的「李美玉」會合併到已加入的「美玉」，服事表、聚會和權限群組都會接上'), findsOneWidget);
    await tapText(tester, '合併');

    final m = b.members['grace']!['mei-google']!;
    expect(m.groups, isEmpty);
    expect(m.leadTypes, ['sunday']);
    expect(m.serves('sunday', '司琴'), isTrue);
    expect(b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))]!.duties.single.uids, {'李美玉': 'mei-google'});
    expect(b.pendingMembers['grace'], isEmpty);
    expect(find.text('已合併'), findsOneWidget);
    expect(find.text('合併還沒登入的資料'), findsNothing, reason: 'nothing left to merge');
  });

  testWidgets('someone without an email who joined by invite is offered to merge on 同工, by the same name', (
    tester,
  ) async {
    const huangPending = PendingMember(
      id: 'old-huang',
      name: '黃鎮台',
      zones: [
        Zone(serviceType: 'sunday', duties: ['招待']),
      ],
    );
    final b = seededChurch(
      extra: const [Member(uid: 'huang', name: '黃鎮台')],
    );
    b.addPending('grace', huangPending, rosterIds: [Roster.idFor('sunday', Day(2026, 10, 18))]);
    b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))] = Roster(
      type: 'sunday',
      day: Day(2026, 10, 18),
      duties: const [
        Duty(role: '招待', people: ['黃鎮台'], uids: {'黃鎮台': 'old-huang'}),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    expect(findShownContaining('還沒登入的資料裡也有「黃鎮台」'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('合併黃鎮台'));
    await settle(tester);
    expect(find.text('合併還沒登入的「黃鎮台」？'), findsOneWidget);
    expect(findShown('還沒登入的「黃鎮台」會合併到已加入的「黃鎮台」，服事表、聚會和權限群組都會接上'), findsOneWidget);
    await tapText(tester, '合併');

    expect(b.pendingMembers['grace'], isEmpty);
    expect(b.members['grace']!['huang']!.serves('sunday', '招待'), isTrue);
    expect(b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))]!.duties.single.uids, {'黃鎮台': 'huang'});
    expect(find.textContaining('還沒登入的資料裡也有'), findsNothing);
  });

  testWidgets('only admins are offered a merge on 同工', (tester) async {
    final b = seededChurch(
      as: editor,
      extra: const [Member(uid: 'huang', name: '黃鎮台')],
    );
    b.pendingMembers['grace'] = {'old-huang': const PendingMember(id: 'old-huang', name: '黃鎮台')};
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    expect(find.textContaining('還沒登入的資料裡也有'), findsNothing);
  });

  testWidgets('picking pending data to merge lists the same name first', (tester) async {
    final b = seededChurch(
      extra: const [Member(uid: 'huang', name: '黃鎮台')],
    );
    b.pendingMembers['grace'] = {
      'old-a': const PendingMember(id: 'old-a', name: '王大明', email: 'a@example.com'),
      'old-huang': const PendingMember(id: 'old-huang', name: '黃鎮台'),
    };
    await pumpApp(tester, b);
    await go(tester, '/me/members/huang');
    await tester.scrollUntilVisible(find.text('合併還沒登入的資料'), 200, scrollable: find.byType(Scrollable).last);
    expect(findShown('同工沒有 email、或用另一個 email 加入時，合併他還沒登入的資料，服事表、聚會和權限群組都會接上'), findsOneWidget);
    await tapText(tester, '合併還沒登入的資料');
    final huang = tester.getTopLeft(findShown('黃鎮台').last).dy;
    final other = tester.getTopLeft(findShown('王大明')).dy;
    expect(huang, lessThan(other));
  });

  testWidgets('without pending data there is nothing to merge; non-admins cannot merge', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/me/members/mei');
    expect(find.text('合併還沒登入的資料'), findsNothing);
    final b = seededChurch(as: editor);
    b.pendingMembers['grace'] = {'old-mei': meiPending};
    await expectLater(b.church('grace').mergePending('old-mei', 'mei'), throwsA(isA<Object>()));
    expect(b.pendingMembers['grace']!.length, 1);
  });
}
