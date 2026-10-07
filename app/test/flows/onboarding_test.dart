import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/church/church_logo.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

void main() {
  testWidgets('Google sign-in, create a church, land on its home', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'alice@gmail.com';
    await pumpApp(tester, b);

    expect(find.text('使用 Google 登入'), findsOneWidget);
    await tapText(tester, '使用 Google 登入');

    expect(find.text('加入你的教會'), findsOneWidget);
    expect(
      b.users.values.single.email,
      'alice@gmail.com',
      reason: 'users/{uid} created',
    );

    await tapText(tester, '建立新教會');
    await tester.enterText(find.byType(TextField), '恩典堂');
    await tester.pump();
    await tapText(tester, '建立');

    expect(b.churches.values.single.name, '恩典堂');
    final uid = b.auth.currentUser!.uid;
    expect(b.members.values.single[uid]!.role, Role.admin);
    expect(find.byType(NavigationBar), findsOneWidget);

    // The home page points the new admin at inviting people.
    expect(find.text('開始使用'), findsOneWidget);
    await tapText(tester, '邀請同工');
    expect(find.text('建立邀請連結'), findsOneWidget);
  });

  testWidgets('getting started is gone once someone else has joined', (tester) async {
    await pumpApp(tester, seededChurch());
    expect(find.text('開始使用'), findsNothing);
  });

  testWidgets('email sign-up must verify before creating a church', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock);
    await pumpApp(tester, b);

    await tapText(tester, '用 email 登入');
    await tapText(tester, '註冊新帳號');
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '小明');
    await tester.enterText(fields.at(1), 'ming@example.com');
    await tester.enterText(fields.at(2), 'secret123');
    await tapText(tester, '註冊');

    expect(find.text('驗證你的 email'), findsOneWidget);
    await tapText(tester, '建立新教會');
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '建立'),
    );
    expect(create.onPressed, isNull, reason: 'disabled until verified');

    b.auth.verify('ming@example.com');
    await tapText(tester, '我已經驗證');
    expect(find.text('驗證你的 email'), findsNothing);
    await tester.enterText(find.byType(TextField), '活水堂');
    await tester.pump();
    await tapText(tester, '建立');
    expect(b.churches.values.single.name, '活水堂');
  });

  testWidgets('a sign-up error goes away once the field is filled', (tester) async {
    await pumpApp(tester, MemoryBackend(clock: testClock));
    await tapText(tester, '用 email 登入');
    await tapText(tester, '註冊新帳號');
    await tapText(tester, '註冊');
    expect(find.text('請輸入名字'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), '小明');
    await tester.pump();
    expect(find.text('請輸入名字'), findsNothing);
    expect(find.text('請輸入 email'), findsOneWidget, reason: 'the other errors stay until fixed');
  });

  testWidgets('a taken name is refused with a way to contact us', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock)..addChurch('台北 靈糧堂');
    b.auth.googleAccount = 'bob@gmail.com';
    await pumpApp(tester, b);
    await tapText(tester, '使用 Google 登入');
    await tapText(tester, '建立新教會');
    await tester.enterText(find.byType(TextField), '台北靈糧堂');
    await tester.pump();
    await tapText(tester, '建立');
    expect(find.textContaining('已經有教會叫這個名字'), findsOneWidget);
    expect(find.text('聯絡我們'), findsOneWidget);
    expect(b.churches.length, 1);
  });

  testWidgets('an invite link opened signed out joins after sign-in', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('恩典堂');
    b.addMember(cid, const Member(uid: 'admin', name: '牧師', role: Role.admin));
    b.invites['WELCOME26'] = Invite(
      code: 'WELCOME26',
      churchId: cid,
      churchName: '恩典堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    b.auth.googleAccount = 'new@gmail.com';
    await pumpApp(tester, b);

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/c/$cid/join/WELCOME26');
    await settle(tester);
    expect(find.text('使用 Google 登入'), findsOneWidget);
    expect(find.text('受邀加入〈恩典堂〉'), findsOneWidget, reason: 'the login page says who is inviting');

    await tapText(tester, '使用 Google 登入');
    expect(find.text('加入〈恩典堂〉'), findsOneWidget);
    await tapText(tester, '加入');

    final uid = b.auth.currentUser!.uid;
    expect(b.members[cid]![uid]!.role, Role.staff);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('an invite to a church I am already in says so and takes me there', (tester) async {
    final b = seededChurch();
    b.addChurch('希望堂', id: 'hope');
    b.addMember('hope', pastor);
    b.invites['HOPE2026'] = Invite(
      code: 'HOPE2026',
      churchId: 'hope',
      churchName: '希望堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    await pumpApp(tester, b);
    expect(find.text('恩典堂'), findsOneWidget);

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/c/hope/join/HOPE2026');
    await settle(tester);
    expect(find.text('希望堂'), findsOneWidget);
    expect(find.text('你已經是〈希望堂〉的同工'), findsOneWidget);
    expect(find.text('加入〈希望堂〉'), findsNothing);
    expect(find.text('加入'), findsNothing);

    await tapText(tester, '首頁');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('希望堂'), findsOneWidget, reason: 'switched to the church the invite is for');
  });

  testWidgets('joining a second church from an invite switches to it', (tester) async {
    final b = seededChurch(as: staffMei);
    b.addChurch('希望堂', id: 'hope');
    b.invites['HOPE2026'] = Invite(
      code: 'HOPE2026',
      churchId: 'hope',
      churchName: '希望堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/c/hope/join/HOPE2026');
    await settle(tester);
    expect(find.text('加入〈希望堂〉'), findsOneWidget);
    await tapText(tester, '加入');
    expect(b.members['hope']!.containsKey('mei'), isTrue);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('希望堂'), findsOneWidget);
  });

  testWidgets('a pasted invite link works as a code', (tester) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('恩典堂');
    b.invites['PASTED26'] = Invite(
      code: 'PASTED26',
      churchId: cid,
      churchName: '恩典堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    b.auth.signInAs('x@gmail.com');
    await pumpApp(tester, b);
    await tapText(tester, '輸入邀請碼');
    await tester.enterText(find.byType(TextField), 'https://marthasit.web.app/c/$cid/join/PASTED26');
    await tester.pump();
    await tapText(tester, '下一步');
    await tapText(tester, '加入');
    expect(b.members[cid]!.containsKey(b.auth.currentUser!.uid), isTrue);
  });

  testWidgets('a mistyped code asks to check it', (tester) async {
    final b = MemoryBackend(clock: testClock)..addChurch('恩典堂');
    b.auth.signInAs('x@gmail.com');
    await pumpApp(tester, b);
    await tapText(tester, '輸入邀請碼');
    await tester.enterText(find.byType(TextField), 'TYPO1234');
    await tester.pump();
    await tapText(tester, '下一步');
    expect(find.text('找不到這個邀請，請確認邀請碼，或向管理員要新的邀請'), findsOneWidget);
  });

  testWidgets('the invite shows the church logo above its name', (tester) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('恩典堂');
    b.churches[cid] = b.churches[cid]!.copyWith(logoUrl: 'https://example.org/logo.png');
    b.invites['LOGO2026'] = Invite(
      code: 'LOGO2026',
      churchId: cid,
      churchName: '恩典堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    b.auth.signInAs('x@gmail.com');
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/welcome/join/LOGO2026');
    await settle(tester);
    expect(find.text('加入〈恩典堂〉'), findsOneWidget);
    expect(find.descendant(of: find.byType(ChurchLogo), matching: find.byType(Image)), findsOneWidget);
  });

  testWidgets('an expired invite says so and offers to enter another code', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('恩典堂');
    b.invites['OLDCODE1'] = Invite(
      code: 'OLDCODE1',
      churchId: cid,
      churchName: '恩典堂',
      expiresAt: testNow.subtract(const Duration(days: 1)),
    );
    b.auth.signInAs('x@gmail.com');
    await pumpApp(tester, b);
    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go('/c/$cid/join/OLDCODE1');
    await settle(tester);
    expect(find.text('這個邀請過期了，請向管理員要新的邀請'), findsOneWidget);
    expect(find.text('輸入邀請碼'), findsOneWidget);
  });

  testWidgets('a suspended church shows only the closed page', (tester) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('停用堂', status: ChurchStatus.suspended);
    final user = b.auth.signInAs('s@gmail.com');
    b.addMember(cid, Member(uid: user.uid, name: '同工'));
    await pumpApp(tester, b);
    expect(find.text('〈停用堂〉已停用'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('a deleted church can be restored by its admin', (tester) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('刪除堂');
    final user = b.auth.signInAs('a@gmail.com');
    b.addMember(cid, Member(uid: user.uid, name: '管理員', role: Role.admin));
    await b.church(cid).deleteChurch();
    await pumpApp(tester, b);
    expect(find.text('〈刪除堂〉已刪除'), findsOneWidget);
    await tapText(tester, '還原教會');
    expect(b.churches[cid]!.status, ChurchStatus.active);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a deleted church can no longer be restored after 30 days', (tester) async {
    var now = testNow;
    final b = MemoryBackend(clock: () => now);
    final cid = b.addChurch('刪除堂');
    final user = b.auth.signInAs('a@gmail.com');
    b.addMember(cid, Member(uid: user.uid, name: '管理員', role: Role.admin));
    await b.church(cid).deleteChurch();
    now = testNow.add(const Duration(days: 30)).subtract(const Duration(hours: 1));
    await pumpApp(tester, b);
    expect(find.text('還原教會'), findsOneWidget);

    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    await settle(tester);
    expect(find.text('還原教會'), findsNothing);
    expect(find.text('已經超過 30 天，不能再還原了'), findsOneWidget);
  });
}
