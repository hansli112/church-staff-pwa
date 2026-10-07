import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
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
  final b = MemoryBackend();
  final cid = b.addChurch('恩典堂', id: 'grace');
  b.setServices(cid, const [sundayService]);
  b.addMember(cid, pastor);
  b.pendingMembers[cid] = {'old-mei': meiPending};
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
    expect(find.text('〈恩典堂〉的同工資料已經搬過來了，要加入嗎？'), findsOneWidget);
    await tapText(tester, '加入');

    final m = b.members['grace']!['new-mei']!;
    expect(m.role, Role.leader);
    expect(m.groups, {Group.rosterEditors});
    expect(m.serves('sunday', '司琴'), isTrue);
    expect(b.rosters['grace']!.values.single.duties.single.uids, {'李美玉': 'new-mei'});
    expect(b.pendingMembers['grace'], isEmpty);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('我接下來的服事'), findsOneWidget, reason: 'their roster day is theirs again');
  });

  testWidgets('declining joins nothing and does not ask again on this device', (tester) async {
    final b = movedChurch();
    await pumpApp(tester, b);
    await tapText(tester, '不要');
    expect(find.text('〈恩典堂〉的同工資料已經搬過來了，要加入嗎？'), findsNothing);
    expect(b.members['grace']!.containsKey('new-mei'), isFalse);
    expect(b.pendingMembers['grace']!.containsKey('old-mei'), isTrue, reason: 'kept for the admin');
    expect(find.text('加入你的教會'), findsOneWidget);
  });

  testWidgets('an unverified email is not asked', (tester) async {
    final b = movedChurch(signIn: false);
    await b.auth.registerWithEmail('美玉', 'mei@example.com', 'secret123');
    await pumpApp(tester, b);
    expect(find.text('驗證你的 email'), findsOneWidget);
    expect(find.textContaining('已經搬過來了'), findsNothing);
  });

  testWidgets('the sign-in page tells old password users to register again', (tester) async {
    await pumpApp(tester, MemoryBackend());
    await tapText(tester, '用 email 登入');
    expect(find.text('從舊版搬過來的同工：舊的密碼不能用，請用同一個 email 註冊新帳號，或用 Google 登入。'), findsOneWidget);
  });

  testWidgets('an admin can delete pending data, after confirming', (tester) async {
    final b = seededChurch();
    b.pendingMembers['grace'] = {'old-x': const PendingMember(id: 'old-x', name: '舊同工', email: 'x@example.com')};
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    await tapText(tester, '舊同工');
    await tapText(tester, '刪除這筆資料');
    expect(find.text('他就不能用 email 認領了。服事表上的名字會保留。'), findsOneWidget);
    await tapText(tester, '刪除');
    expect(b.pendingMembers['grace'], isEmpty);
  });

  testWidgets('an admin merges pending data into someone who joined with another email', (tester) async {
    final b = seededChurch(
      extra: const [Member(uid: 'mei-google', name: '美玉', email: 'mei@gmail.com')],
    );
    b.pendingMembers['grace'] = {'old-mei': meiPending};
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
    expect(find.text('把〈李美玉〉合併到〈美玉〉？'), findsOneWidget);
    await tapText(tester, '合併');

    final m = b.members['grace']!['mei-google']!;
    expect(m.groups, {Group.rosterEditors});
    expect(m.serves('sunday', '司琴'), isTrue);
    expect(b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))]!.duties.single.uids, {'李美玉': 'mei-google'});
    expect(b.pendingMembers['grace'], isEmpty);
    expect(find.text('已合併'), findsOneWidget);
    expect(find.text('合併還沒登入的資料'), findsNothing, reason: 'nothing left to merge');
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
