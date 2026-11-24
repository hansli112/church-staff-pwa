import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/church/church_logo.dart';
import 'package:martha/state/session.dart';
import 'package:martha/state/web_page.dart';

import '../support/harness.dart';
import '../support/seed.dart';
import '../support/telemetry.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(findShown(text).last);
  await settle(tester);
}

/// 設定 › 教會資訊 › 切換教會: the switcher is on the church's page.
Future<void> openChurchSwitcher(WidgetTester tester) async {
  await tapText(tester, '設定');
  await tapText(tester, '教會資訊');
  await tester.scrollUntilVisible(find.text('切換教會'), 300, scrollable: find.byType(Scrollable).last);
  await tapText(tester, '切換教會');
}

void main() {
  testWidgets('Google sign-in, create a church, land on its home', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'alice@gmail.com';
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);

    expect(find.text('使用 Google 登入'), findsOneWidget);
    await tapText(tester, '使用 Google 登入');

    expect(find.text('加入你的教會'), findsOneWidget);
    expect(
      b.users.values.single.email,
      'alice@gmail.com',
      reason: 'users/{uid} created',
    );

    await tapText(tester, '建立新教會');
    await tester.enterText(find.widgetWithText(TextField, '教會名稱'), '恩典堂');
    final name = find.widgetWithText(TextField, '你的名字');
    expect(tester.widget<TextField>(name).controller!.text, 'alice');
    expect(findShown('顯示在服事表上，建議用全名'), findsOneWidget);
    await tester.enterText(name, '');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '建立')).onPressed, isNull);
    await tester.enterText(name, '林愛麗');
    await tester.pump();
    await tapText(tester, '建立');

    expect(b.churches.values.single.name, '恩典堂');
    final uid = b.auth.currentUser!.uid;
    expect(b.members.values.single[uid]!.role, Role.admin);
    expect(b.members.values.single[uid]!.name, '林愛麗');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(telemetry.named('login'), [
      {'method': 'google'},
    ]);
    expect(telemetry.named('church_create'), [
      {'method': 'new'},
    ]);
    expect(telemetry.role, 'admin');
    expect(telemetry.screens, containsAllInOrder(['/login', '/welcome', '/welcome/create', '/home']));

    // The home page points the new admin at inviting people.
    expect(find.text('開始使用'), findsOneWidget);
    await tapText(tester, '邀請同工');
    expect(find.text('建立邀請連結'), findsOneWidget);
  });

  testWidgets('in no church yet, 登出 and 刪除帳號 are under 帳號, not on the welcome page', (tester) async {
    final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'alice@gmail.com';
    await pumpApp(tester, b);
    await tapText(tester, '使用 Google 登入');
    expect(find.text('加入你的教會'), findsOneWidget);
    expect(find.text('登出'), findsNothing);
    expect(find.text('刪除帳號'), findsNothing);
    expect(findShown('請教會的管理員給你邀請連結'), findsOneWidget);
    expect(find.text('輸入邀請碼'), findsNothing, reason: 'an invite is a link to tap, not a code to type');

    await tester.tap(find.byTooltip('帳號'));
    await settle(tester);
    await tapText(tester, '刪除帳號');
    expect(find.widgetWithText(TextButton, '刪除帳號'), findsOneWidget, reason: 'the 刪除帳號 page');
  });

  testWidgets('in no church yet, 登出 is under 帳號', (tester) async {
    final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'alice@gmail.com';
    await pumpApp(tester, b);
    await tapText(tester, '使用 Google 登入');
    await tester.tap(find.byTooltip('帳號'));
    await settle(tester);
    await tapText(tester, '登出');
    expect(findShown('使用 Google 登入'), findsOneWidget, reason: 'signed out');
  });

  testWidgets('getting started is gone once someone else has joined', (tester) async {
    await pumpApp(tester, seededChurch());
    expect(find.text('開始使用'), findsNothing);
  });

  testWidgets('an email sign-up verifies before anything else, then goes on to create a church', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock);
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);

    await tapText(tester, '用 email 登入');
    await tapText(tester, '註冊新帳號');
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '小明');
    await tester.enterText(fields.at(1), 'ming@example.com');
    await tester.enterText(fields.at(2), 'secret123');
    await tapText(tester, '註冊');

    expect(telemetry.named('sign_up'), [
      {'method': 'email'},
    ]);
    expect(telemetry.named('login'), isEmpty);
    expect(findShown('到信箱點驗證連結'), findsOneWidget);
    expect(findShown('驗證信已寄到 ming@example.com。點信裡的連結後，回到這裡就會自動繼續。'), findsOneWidget);
    expect(findShown('沒收到？看看垃圾郵件，或重寄一次。'), findsOneWidget);
    for (final later in ['建立新教會', '加入你的教會']) {
      expect(find.text(later), findsNothing, reason: '$later waits for the email');
    }
    expect(find.byType(FilledButton), findsNothing, reason: 'nothing to tap: it goes on by itself');
    await tester.pump(const Duration(seconds: 10));
    expect(findShown('到信箱點驗證連結'), findsOneWidget, reason: 'still waiting for the link');

    // The link clicked in the mail app: in a few seconds, on without a tap.
    b.auth.verify('ming@example.com');
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('到信箱點驗證連結'), findsNothing);
    await tapText(tester, '建立新教會');
    await tester.enterText(find.byType(TextField).first, '活水堂');
    await tester.pump();
    await tapText(tester, '建立');
    expect(b.churches.values.single.name, '活水堂');
  });

  testWidgets('an email not verified yet can sign out and use another', (tester) async {
    final b = MemoryBackend(clock: testClock);
    await b.auth.registerWithEmail('小明', 'ming@example.com', 'secret123', AppLanguage.zhHant);
    await pumpApp(tester, b);
    expect(find.text('登出'), findsNothing, reason: 'under 帳號, as on the welcome page');
    await tester.tap(find.byTooltip('帳號'));
    await settle(tester);
    expect(find.text('ming@example.com'), findsWidgets, reason: 'whom I am signed in as');
    await tapText(tester, '登出');
    expect(findShown('用 email 登入'), findsOneWidget);
  });

  testWidgets('on a closed church\'s page, 登出 and 刪除帳號 are under 帳號', (tester) async {
    final b = seededChurch();
    b.churches['grace'] = b.churches['grace']!.copyWith(status: ChurchStatus.suspended);
    await pumpApp(tester, b);
    expect(findShown('〈恩典堂〉已停用'), findsOneWidget);
    expect(find.text('登出'), findsNothing);
    await tester.tap(find.byTooltip('帳號'));
    await settle(tester);
    expect(find.text('刪除帳號'), findsOneWidget);
    await tapText(tester, '登出');
    expect(b.auth.currentUser, isNull);
  });

  testWidgets('an invite opened before signing up with email opens once the email is verified', (tester) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('恩典堂');
    b.addMember(cid, const Member(uid: 'admin', name: '牧師', role: Role.admin));
    b.invites['WELCOME26'] = Invite(
      code: 'WELCOME26',
      churchId: cid,
      churchName: '恩典堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    await b.auth.registerWithEmail('小明', 'ming@example.com', 'secret123', AppLanguage.zhHant);
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/c/$cid/join/WELCOME26');
    await settle(tester);
    expect(findShown('到信箱點驗證連結'), findsOneWidget);
    expect(find.text('加入〈恩典堂〉'), findsNothing);

    b.auth.verify('ming@example.com');
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(findShown('加入〈恩典堂〉'), findsOneWidget);
  });

  testWidgets('登入 tapped with the keyboard up closes it, and a wrong password says so above where it was', (
    tester,
  ) async {
    await pumpApp(tester, MemoryBackend(clock: testClock));
    await tapText(tester, '用 email 登入');
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ming@example.com');
    await tester.enterText(fields.at(1), 'wrong123');
    // The phone's keyboard, over the bottom half, as the password is typed.
    final half = tester.view.physicalSize.height / 2;
    tester.view.viewInsets = FakeViewPadding(bottom: half);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '登入'));
    await settle(tester);
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
      reason: 'the keyboard closed',
    );
    final error = findShown('email 或密碼不對');
    expect(error, findsOneWidget);
    expect(
      tester.getRect(error).bottom,
      lessThan(half / tester.view.devicePixelRatio),
      reason: 'not under the keyboard',
    );
  });

  testWidgets('someone in no church yet deletes their account from the welcome page', (tester) async {
    final b = MemoryBackend(clock: testClock);
    await pumpApp(tester, b);
    await tapText(tester, '用 email 登入');
    await tapText(tester, '註冊新帳號');
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '小明');
    await tester.enterText(fields.at(1), 'ming@example.com');
    await tester.enterText(fields.at(2), 'secret123');
    await tapText(tester, '註冊');

    await tester.tap(find.byTooltip('帳號'));
    await settle(tester);
    await tapText(tester, '刪除帳號');
    await tester.tap(find.widgetWithText(TextButton, '刪除帳號'));
    await settle(tester);
    await tapText(tester, '刪除帳號');
    expect(findShown('用 email 登入'), findsOneWidget, reason: 'signed out');
    await expectLater(b.auth.signInWithEmail('ming@example.com', 'secret123'), throwsA(isA<AuthException>()));
  });

  testWidgets('signing up with email asks for the full name, the one the rosters show', (tester) async {
    await pumpApp(tester, MemoryBackend(clock: testClock));
    await tapText(tester, '用 email 登入');
    await tapText(tester, '註冊新帳號');
    expect(find.widgetWithText(TextFormField, '你的全名'), findsOneWidget);
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

  testWidgets('a name another church has is a name like any other', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock)..addChurch('台北靈糧堂');
    b.auth.googleAccount = 'bob@gmail.com';
    await pumpApp(tester, b);
    await tapText(tester, '使用 Google 登入');
    await tapText(tester, '建立新教會');
    await tester.enterText(find.byType(TextField).first, '台北靈糧堂');
    await tester.pump();
    await tapText(tester, '建立');
    expect(b.churches.length, 2);
    expect(b.churches.values.map((c) => c.name), everyElement('台北靈糧堂'));
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'in the new one');
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
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/c/$cid/join/WELCOME26');
    await settle(tester);
    expect(find.text('使用 Google 登入'), findsOneWidget);
    expect(find.text('受邀加入〈恩典堂〉'), findsOneWidget, reason: 'the login page says who is inviting');

    await tapText(tester, '使用 Google 登入');
    expect(find.text('加入〈恩典堂〉'), findsOneWidget);
    // The name Google gave, to be put as the church calls them.
    final name = find.widgetWithText(TextField, '你的名字');
    expect(tester.widget<TextField>(name).controller!.text, 'new');
    await tester.enterText(name, '');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '加入')).onPressed, isNull);
    await tester.enterText(name, '陳新');
    await tester.pump();
    await tapText(tester, '加入');

    final uid = b.auth.currentUser!.uid;
    expect(b.members[cid]![uid]!.role, Role.staff);
    expect(b.members[cid]![uid]!.name, '陳新');
    expect(b.users[uid]!.name, '陳新', reason: 'the account’s name, as 帳號 → 名字 sets it');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(telemetry.named('join_group'), [
      {'method': 'invite'},
    ]);
    // Pages by their pattern: never the church's ID or the invite code.
    expect(telemetry.screens, contains('/c/:churchId/join/:code'));
    expect(telemetry.screens.where((s) => s.contains(cid) || s.contains('WELCOME26')), isEmpty);
  });

  testWidgets('an invite to a church I am already in opens that church, with nothing to join', (tester) async {
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

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/c/hope/join/HOPE2026?openExternalBrowser=1');
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('希望堂'), findsOneWidget, reason: 'switched to the church the invite is for');
    expect(find.text('加入'), findsNothing);
  });

  testWidgets('a typed code for a church I am already in says so and takes me there', (tester) async {
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

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/welcome/join/HOPE2026');
    await settle(tester);
    expect(find.text('你已經是〈希望堂〉的同工'), findsOneWidget);
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

  testWidgets('a member of one church starts another from 切換教會', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    await openChurchSwitcher(tester);
    await tapText(tester, '建立新教會');
    await tester.enterText(find.byType(TextField).first, '希望堂');
    await tester.pump();
    await tapText(tester, '建立');

    final hope = b.churches.entries.singleWhere((e) => e.value.name == '希望堂').key;
    expect(b.members[hope]!['mei']!.role, Role.admin);
    expect(b.members['grace']!.containsKey('mei'), isTrue);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('希望堂'), findsOneWidget, reason: 'switched to the new church');

    await openChurchSwitcher(tester);
    await tapText(tester, '恩典堂');
    expect(find.text('恩典堂'), findsOneWidget);
  });

  testWidgets('切換教會 has no code to type: another church is joined from its invite link', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await openChurchSwitcher(tester);
    expect(find.text('建立新教會'), findsOneWidget);
    expect(find.text('輸入邀請碼'), findsNothing);
  });
  testWidgets('back from starting a church returns to the church I am in', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await openChurchSwitcher(tester);
    await tapText(tester, '建立新教會');
    expect(find.text('教會名稱'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('加入你的教會'), findsNothing);
    expect(find.text('教會資訊'), findsWidgets, reason: 'back in 設定');
  });

  testWidgets('in LINE’s built-in browser, sign-in says to open the page in Safari or Chrome', (tester) async {
    const line =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari Line/14.16.0';
    await pumpApp(
      tester,
      MemoryBackend(clock: testClock),
      overrides: [userAgentProvider.overrideWithValue(line)],
    );
    expect(findShown('在 LINE 裡不能用 Google 登入。請用 Safari 或 Chrome 打開這個網頁，或用 email 登入。'), findsOneWidget);
    expect(findShown('複製連結'), findsOneWidget);
    expect(findShown('使用 Google 登入'), findsOneWidget, reason: 'still offered');
  });

  testWidgets('the address to copy out of LINE is the invite link, not the sign-in page', (tester) async {
    const line =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari Line/14.16.0';
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('恩典堂');
    b.invites['LINE2026'] = Invite(
      code: 'LINE2026',
      churchId: cid,
      churchName: '恩典堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    await pumpApp(tester, b, overrides: [userAgentProvider.overrideWithValue(line)]);
    final out = captureOutbox(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/c/$cid/join/LINE2026?openExternalBrowser=1');
    await settle(tester);
    await tapText(tester, '用網頁版');
    await tapText(tester, '複製連結');
    expect(out.copied.single, endsWith('/c/$cid/join/LINE2026?openExternalBrowser=1'));
  });

  testWidgets('in a real browser, sign-in shows no such note', (tester) async {
    await pumpApp(tester, MemoryBackend(clock: testClock));
    expect(find.text('複製連結'), findsNothing);
  });

  testWidgets('the join page shows it is loading while the invite comes', (tester) async {
    final b = seededChurch(as: staffMei);
    b.addChurch('希望堂', id: 'hope');
    b.invites['HOPE2026'] = Invite(
      code: 'HOPE2026',
      churchId: 'hope',
      churchName: '希望堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    final held = b.invitePreviewHeld = Completer<void>();
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/c/hope/join/HOPE2026');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('加入〈希望堂〉'), findsNothing);

    held.complete();
    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('加入〈希望堂〉'), findsOneWidget);
  });

  testWidgets('a link with a code that is no invite asks for a new one', (tester) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('恩典堂');
    b.auth.signInAs('x@gmail.com');
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/c/$cid/join/TYPO1234');
    await settle(tester);
    expect(findShown('找不到這個邀請，請向管理員要新的邀請'), findsOneWidget);
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

  testWidgets('an expired invite says so, and goes back to the welcome page', (
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
    expect(find.text('輸入邀請碼'), findsNothing);
    await tapText(tester, '回首頁');
    expect(findShown('加入你的教會'), findsOneWidget);
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

  testWidgets('a church not read here yet, offline, says it opens once online, not that it is closed', (tester) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('恩典堂');
    final user = b.auth.signInAs('s@gmail.com');
    b.addMember(cid, Member(uid: user.uid, name: '同工'));
    b.churches.remove(cid);
    b.setOnline(false);
    await pumpApp(tester, b);
    expect(find.text('離線中'), findsOneWidget);
    expect(findShown('連上網路就會開啟這間教會'), findsOneWidget);
    expect(find.text('無法開啟這間教會'), findsNothing);
    expect(findShown('要加入其他教會，點管理員給的邀請連結'), findsNothing);

    b.setOnline(true);
    await settle(tester);
    expect(find.text('無法開啟這間教會'), findsOneWidget);
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

  testWidgets('someone whose only church is deleted is told how to join another, and joins from the link', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('刪除堂');
    b.addChurch('希望堂', id: 'hope');
    b.invites['HOPE2026'] = Invite(
      code: 'HOPE2026',
      churchId: 'hope',
      churchName: '希望堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    final user = b.auth.signInAs('s@gmail.com');
    b.addMember(cid, Member(uid: user.uid, name: '同工'));
    b.churches[cid] = b.churches[cid]!.copyWith(status: ChurchStatus.deleted);
    await pumpApp(tester, b);
    expect(find.text('〈刪除堂〉已刪除'), findsOneWidget);
    expect(findShown('要加入其他教會，點管理員給的邀請連結'), findsOneWidget);
    expect(find.text('輸入邀請碼'), findsNothing);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/c/hope/join/HOPE2026');
    await settle(tester);
    await tapText(tester, '加入');
    expect(b.members['hope']!.containsKey(user.uid), isTrue);
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
