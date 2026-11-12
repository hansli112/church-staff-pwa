import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/providers.dart';

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

void main() {
  testWidgets('a member opening a church URL lands in that church and can switch back', (tester) async {
    final b = seededChurch();
    b.addChurch('希望堂', id: 'hope');
    b.addMember('hope', pastor);
    await pumpApp(tester, b);
    expect(find.text('恩典堂'), findsOneWidget);

    await go(tester, '/c/hope');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('希望堂'), findsOneWidget);

    await tapText(tester, '設定');
    await tapText(tester, '切換教會');
    await tapText(tester, '恩典堂');
    expect(find.text('恩典堂'), findsOneWidget);
  });

  testWidgets('a notification link opens its church at the page it names', (tester) async {
    final b = seededChurch();
    b.addChurch('希望堂', id: 'hope');
    b.addMember('hope', pastor);
    await pumpApp(tester, b);
    await go(tester, '/c/hope?to=%2Fme');
    expect(find.text('希望堂'), findsOneWidget);
    expect(find.text('教會資訊'), findsOneWidget, reason: 'on 我的, not 首頁');

    // Only a page of this app.
    await go(tester, '/c/hope?to=%2F%2Fevil.example');
    expect(find.text('教會資訊'), findsNothing, reason: 'home instead');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('launching from a home-screen shortcut opens its church', (tester) async {
    final b = seededChurch();
    b.addChurch('希望堂', id: 'hope');
    b.addMember('hope', pastor);
    tester.platformDispatcher.defaultRouteNameTestValue = '/c/hope';
    await pumpApp(tester, b);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('希望堂'), findsOneWidget);
  });

  testWidgets('someone who is not a member sees the church and how to join', (tester) async {
    final b = seededChurch();
    b.addChurch('希望堂', id: 'hope');
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    expect(find.text('希望堂'), findsOneWidget);
    expect(findShown('你還不是這間教會的同工，申請後管理員允許就會加入'), findsOneWidget);
    await tapText(tester, '回首頁');
    expect(findShown('恩典堂'), findsOneWidget);
  });

  testWidgets('without any church, the next step is an invite code', (tester) async {
    final b = MemoryBackend(clock: testClock);
    b.addChurch('希望堂', id: 'hope');
    b.auth.signInAs('new@example.com', uid: 'new', name: '新朋友');
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    expect(find.text('希望堂'), findsOneWidget);
    await tapText(tester, '輸入邀請碼');
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('an unknown or suspended church is not found, with a way home', (tester) async {
    final b = seededChurch();
    b.addChurch('關閉堂', id: 'closed', status: ChurchStatus.suspended);
    await pumpApp(tester, b);
    for (final id in ['nope', 'closed']) {
      await go(tester, '/c/$id');
      expect(find.text('找不到這間教會'), findsOneWidget);
      await tapText(tester, '回首頁');
      expect(find.byType(NavigationBar), findsOneWidget);
    }
  });

  testWidgets('邀請 shows the church URL, to copy or share, while requests are taken', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/invites');
    final out = captureOutbox(tester);
    await tapText(tester, '教會網址');
    expect(find.text('分享教會網址'), findsOneWidget);
    await tapText(tester, '複製教會網址');
    expect(out.copied.single, 'https://marthasit-dev.web.app/c/grace');
    expect(find.text('已複製教會網址'), findsOneWidget);

    await tapText(tester, '開放申請加入');
    expect(find.text('教會網址'), findsNothing, reason: 'nobody can ask from it');
  });

  const iconsStay = 'iPhone 上已經加入的圖示不會跟著更新。換了名稱或 logo 之後，請刪掉圖示再加入一次。';

  testWidgets('church info is about the church: how people join is in 邀請', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/me/church');
    for (final gone in ['教會網址', '主畫面名稱', '開放申請加入', 'App 圖示']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
  });

  testWidgets('only admins are told icons on an iPhone keep the old name and logo', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me/church');
    expect(find.text(iconsStay), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('away from a phone’s browser, nobody is told to add the app to home', (tester) async {
    await pumpApp(tester, seededChurch(), overrides: [isWebProvider.overrideWithValue(true)]);
    await go(tester, '/me/church');
    expect(find.text('加入主畫面'), findsNothing, reason: 'a computer, a store app, or the home screen already');
  });

  testWidgets('the note on iPhone icons is for an admin on an iPhone or iPad only', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/me/church');
    expect(find.text(iconsStay), findsNothing, reason: 'Android updates its icons');

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpApp(tester, seededChurch());
    await go(tester, '/me/church');
    expect(findShown(iconsStay), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
