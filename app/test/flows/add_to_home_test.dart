import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/church/add_to_home.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/web_page.dart';

import '../support/harness.dart';
import '../support/seed.dart';

const iphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.7 Mobile/15E148 Safari/604.1';
const android =
    'Mozilla/5.0 (Linux; Android 14; SM-A546E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36';
const mac =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.7 Safari/605.1.15';
const line = '$iphone Line/14.16.0';
const windows =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';

const steps = ['點 Safari 的「分享」按鈕。看不到的話，先點「⋯」', '往下找到「加入主畫面」，點它，再點「加入」', '從主畫面的圖示打開，再登入一次'];
const card = '一點就打開，也收得到服事通知';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

GoRouter routerOf(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).first));

/// Signed in, invited to 恩典堂, on [userAgent].
Future<(MemoryBackend, String)> invited(
  WidgetTester tester,
  String userAgent, {
  List<Override> overrides = const [],
}) async {
  final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'new@gmail.com';
  final cid = b.addChurch('恩典堂');
  b.addMember(cid, const Member(uid: 'admin', name: '牧師', role: Role.admin));
  b.invites['WELCOME26'] = Invite(
    code: 'WELCOME26',
    churchId: cid,
    churchName: '恩典堂',
    expiresAt: testNow.add(const Duration(days: 7)),
  );
  await pumpApp(tester, b, overrides: [userAgentProvider.overrideWithValue(userAgent), ...overrides]);
  routerOf(tester).go('/c/$cid/join/WELCOME26');
  await settle(tester);
  await tapText(tester, '使用 Google 登入');
  return (b, cid);
}

void main() {
  test('which phones are shown how to add the app to the home screen', () {
    AddToHome? on(String ua, {bool standalone = false, int touchPoints = 0}) =>
        addToHomeFor(ua, standalone: standalone, touchPoints: touchPoints);
    expect(on(iphone), AddToHome.iphone);
    expect(on(iphone, standalone: true), isNull, reason: 'opened from the home screen already');
    expect(on(mac, touchPoints: 5), AddToHome.iphone, reason: 'an iPad asking for the desktop site');
    expect(on(mac), isNull);
    expect(on(android), AddToHome.android);
    expect(on(android, standalone: true), isNull);
    expect(on(line), isNull, reason: 'LINE’s browser cannot add to the home screen');
    expect(on(windows), isNull);
    expect(on(''), isNull, reason: 'a store app');
  });

  testWidgets('joining on an iPhone’s browser shows how to add the app to the home screen first', (tester) async {
    final (b, cid) = await invited(tester, iphone);
    await tapText(tester, '加入');

    expect(b.members[cid]![b.auth.currentUser!.uid], isNotNull);
    expect(find.text('加入主畫面'), findsOneWidget);
    for (final step in steps) {
      expect(find.text(step), findsOneWidget);
    }
    expect(find.text('到「我的」→「通知」，開啟通知'), findsOneWidget);
    expect(find.text('主畫面的 App 跟 Safari 是分開的，所以要再登入一次。'), findsOneWidget);

    await tapText(tester, '稍後再說');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(card), findsOneWidget, reason: 'the home page reminds of it');
  });

  testWidgets('the home page’s reminder opens the steps, and stays away once dismissed', (tester) async {
    await pumpApp(tester, seededChurch(), overrides: [userAgentProvider.overrideWithValue(iphone)]);
    expect(find.text(card), findsOneWidget);

    await tapText(tester, card);
    expect(find.text(steps.first), findsOneWidget);
    await tapText(tester, '稍後再說');
    expect(find.text(card), findsOneWidget, reason: 'back on the home page');

    await tester.tap(find.byTooltip('不再顯示'));
    await settle(tester);
    expect(find.text(card), findsNothing);
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
    expect(container.read(prefsProvider).getBool('add_to_home_hidden'), isTrue, reason: 'for good on this phone');
  });

  testWidgets('opened from the home screen, joining goes straight to the church', (tester) async {
    await invited(tester, iphone, overrides: [standaloneProvider.overrideWithValue(true)]);
    await tapText(tester, '加入');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(card), findsNothing);
  });

  testWidgets('on a computer, starting a church goes straight to it', (tester) async {
    final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'alice@gmail.com';
    await pumpApp(tester, b, overrides: [userAgentProvider.overrideWithValue(windows)]);
    await tapText(tester, '使用 Google 登入');
    await tapText(tester, '建立新教會');
    await tester.enterText(find.byType(TextField), '恩典堂');
    await tester.pump();
    await tapText(tester, '建立');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('加入主畫面'), findsNothing);
  });

  testWidgets('starting a church on a phone’s browser shows the steps too', (tester) async {
    final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'alice@gmail.com';
    await pumpApp(tester, b, overrides: [userAgentProvider.overrideWithValue(android)]);
    await tapText(tester, '使用 Google 登入');
    await tapText(tester, '建立新教會');
    await tester.enterText(find.byType(TextField), '恩典堂');
    await tester.pump();
    await tapText(tester, '建立');
    expect(find.text('點 Chrome 右上角的選單（⋮）'), findsOneWidget, reason: 'Chrome has not offered to install');
    await tapText(tester, '稍後再說');
    expect(find.text('開始使用'), findsOneWidget);
  });

  testWidgets('on Android, Chrome’s offer installs in one tap', (tester) async {
    var shown = 0;
    final InstallPrompt prompt = (
      offered: () => true,
      show: () async {
        shown++;
        return true;
      },
    );
    await invited(tester, android, overrides: [installPromptProvider.overrideWithValue(prompt)]);
    await tapText(tester, '加入');
    expect(find.text('點 Chrome 右上角的選單（⋮）'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '加入主畫面'));
    await settle(tester);
    expect(shown, 1);
    expect(find.text('已加入主畫面，之後從主畫面的圖示打開'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('turning down Chrome’s offer stays on the steps', (tester) async {
    final InstallPrompt prompt = (offered: () => true, show: () async => false);
    await invited(tester, android, overrides: [installPromptProvider.overrideWithValue(prompt)]);
    await tapText(tester, '加入');
    await tester.tap(find.widgetWithText(FilledButton, '加入主畫面'));
    await settle(tester);
    expect(find.text('稍後再說'), findsOneWidget);
  });

  testWidgets('on an iPhone’s browser, 通知 says to add the app to the home screen first', (tester) async {
    await pumpApp(tester, seededChurch(), overrides: [userAgentProvider.overrideWithValue(iphone)]);
    routerOf(tester).go('/me/notifications');
    await settle(tester);

    expect(find.text('iPhone 要先把這個網頁加入主畫面，從主畫面打開，才收得到通知。'), findsOneWidget);
    for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(s.value, isFalse);
      expect(s.onChanged, isNull, reason: 'greyed out: nothing comes until then');
    }

    await tapText(tester, '怎麼加入主畫面');
    expect(find.text(steps.first), findsOneWidget);
    await tapText(tester, '稍後再說');
    expect(find.text('怎麼加入主畫面'), findsOneWidget, reason: 'back on 通知');
  });

  testWidgets('opened from the home screen, 通知 has its switches', (tester) async {
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [userAgentProvider.overrideWithValue(iphone), standaloneProvider.overrideWithValue(true)],
    );
    routerOf(tester).go('/me/notifications');
    await settle(tester);
    expect(find.text('怎麼加入主畫面'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNotNull);
  });
}
