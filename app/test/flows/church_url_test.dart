import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
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

    await tapText(tester, '我的');
    await tapText(tester, '切換教會');
    await tapText(tester, '恩典堂');
    expect(find.text('恩典堂'), findsOneWidget);
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
    expect(find.text('你還不是這間教會的同工。請向管理員要邀請連結來加入。'), findsOneWidget);
    await tapText(tester, '回首頁');
    expect(find.text('恩典堂'), findsOneWidget);
  });

  testWidgets('without any church, the next step is an invite code', (tester) async {
    final b = MemoryBackend();
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

  testWidgets('church info shows the church URL, to copy or share', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me/church');
    expect(find.text('marthasit-dev.web.app/c/grace'), findsOneWidget);
    final out = captureOutbox(tester);
    await tapText(tester, '教會網址');
    expect(find.text('分享教會網址'), findsOneWidget);
    await tapText(tester, '複製教會網址');
    expect(out.copied.single, 'https://marthasit-dev.web.app/c/grace');
    expect(find.text('已複製教會網址'), findsOneWidget);
  });

  testWidgets('an admin sets a shorter home-screen name, and can clear it', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/church');
    expect(find.text('同教會名稱'), findsOneWidget);

    await tapText(tester, '主畫面名稱');
    await tester.enterText(find.byType(TextField), '恩典堂台北分堂');
    await tester.pump();
    expect(find.text('部分手機會被截斷'), findsOneWidget, reason: 'over 6 characters');
    await tester.enterText(find.byType(TextField), '恩典堂一二三四五六');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '恩典堂一二三四五', reason: 'at most 8');
    await tester.enterText(find.byType(TextField), '恩典堂');
    await tester.pump();
    expect(find.text('部分手機會被截斷'), findsNothing);
    await tapText(tester, '儲存');
    expect(b.churches['grace']!.homeName, '恩典堂');
    expect(find.text('恩典堂'), findsWidgets);

    await tapText(tester, '主畫面名稱');
    await tester.enterText(find.byType(TextField), '');
    await tapText(tester, '儲存');
    expect(b.churches['grace']!.homeName, isNull);
  });

  testWidgets('only admins see the home-screen name; everyone sees how to add to home', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me/church');
    expect(find.text('主畫面名稱'), findsNothing);
    await tapText(tester, '加入主畫面');
    expect(find.text('iPhone 上已經加入的圖示不會跟著更新。換了名稱或 logo 之後，請刪掉圖示再加入一次。'), findsOneWidget);
  });
}
