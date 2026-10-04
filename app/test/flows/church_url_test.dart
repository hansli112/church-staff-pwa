import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    expect(find.text('martha-app-dev.web.app/c/grace'), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tapText(tester, '教會網址');
    expect(find.text('分享教會網址'), findsOneWidget);
    await tapText(tester, '複製教會網址');
    expect(copied, 'https://martha-app-dev.web.app/c/grace');
    expect(find.text('已複製教會網址'), findsOneWidget);
  });
}
