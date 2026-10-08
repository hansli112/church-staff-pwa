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

/// What the iPhone's steps say, beside the icons: 分享, 加入主畫面 › 加入,
/// then signing in again, then turning on notifications.
const iosSteps = ['分享', '加入', '從主畫面打開，再登入一次', '開啟通知'];
const androidMenu = '加到主畫面';
const card = '一點就打開，也收得到服事通知';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

GoRouter routerOf(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).first));

/// The pages loaded from the server, in place of the app.
class Loads {
  final List<String> pages = [];
  Override get override => loadPageProvider.overrideWithValue(pages.add);
}

/// Chrome's install offer, made ([offer]) and taken or turned down as told.
class FakeOffer extends InstallOffer {
  FakeOffer({this.offered = false, this.accept = true});

  final bool offered;
  final bool accept;
  var shown = 0;

  @override
  bool build() => offered;

  void offer() => state = true;

  @override
  Future<bool> show() async {
    shown++;
    state = false;
    return accept;
  }
}

/// On [userAgent], invited to 恩典堂 by a link, so on its own page; signed in.
Future<(MemoryBackend, String)> invited(
  WidgetTester tester,
  String userAgent, {
  List<Override> overrides = const [],
}) async {
  final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'new@gmail.com';
  final cid = b.addChurch('恩典堂', id: 'grace');
  b.addMember(cid, const Member(uid: 'admin', name: '牧師', role: Role.admin));
  b.invites['WELCOME26'] = Invite(
    code: 'WELCOME26',
    churchId: cid,
    churchName: '恩典堂',
    expiresAt: testNow.add(const Duration(days: 7)),
  );
  await pumpApp(
    tester,
    b,
    overrides: [
      userAgentProvider.overrideWithValue(userAgent),
      pageChurchProvider.overrideWithValue(cid),
      ...overrides,
    ],
  );
  routerOf(tester).go('/c/$cid/join/WELCOME26');
  await settle(tester);
  await tapText(tester, '使用 Google 登入');
  return (b, cid);
}

/// On [userAgent], on the plain app page, signs in and starts 恩典堂.
Future<MemoryBackend> startChurch(WidgetTester tester, String userAgent, {List<Override> overrides = const []}) async {
  final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'alice@gmail.com';
  await pumpApp(tester, b, overrides: [userAgentProvider.overrideWithValue(userAgent), ...overrides]);
  await tapText(tester, '使用 Google 登入');
  await tapText(tester, '建立新教會');
  await tester.enterText(find.byType(TextField), '恩典堂');
  await tester.pump();
  await tapText(tester, '建立');
  return b;
}

/// The seeded church on [userAgent], on 恩典堂's own page unless [page].
Future<void> seeded(
  WidgetTester tester,
  String userAgent, {
  String? page = 'grace',
  List<Override> overrides = const [],
}) => pumpApp(
  tester,
  seededChurch(),
  overrides: [
    userAgentProvider.overrideWithValue(userAgent),
    pageChurchProvider.overrideWithValue(page),
    ...overrides,
  ],
);

void main() {
  test('which phones are shown how to add the app to the home screen', () {
    AddToHome? on(String ua, {bool standalone = false, int touchPoints = 0}) =>
        addToHomeFor(ua, standalone: standalone, touchPoints: touchPoints);
    expect(on(iphone), AddToHome.ios);
    expect(on(iphone, standalone: true), isNull, reason: 'opened from the home screen already');
    expect(on(mac, touchPoints: 5), AddToHome.ios, reason: 'an iPad asking for the desktop site');
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
    expect(find.text('加入主畫面'), findsNWidgets(2), reason: 'the title, and the button to tap');
    for (final step in iosSteps) {
      expect(find.text(step), findsOneWidget);
    }

    await tapText(tester, '稍後再說');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(card), findsOneWidget, reason: 'the home page reminds of it');
  });

  testWidgets('starting a church loads its own page first, so the home screen gets its name and icon', (tester) async {
    final loads = Loads();
    final b = await startChurch(tester, android, overrides: [loads.override]);
    final cid = b.churches.keys.single;
    expect(loads.pages, ['/c/$cid?to=%2Fadd-to-home']);

    // The church's page, loaded again, comes straight to the steps.
    routerOf(tester).go(loads.pages.single);
    await settle(tester);
    expect(find.text(androidMenu), findsOneWidget, reason: 'Chrome has not offered to install');
    await tapText(tester, '稍後再說');
    expect(find.text('開始使用'), findsOneWidget);
  });

  testWidgets('the home page’s reminder opens the steps, and stays away once dismissed', (tester) async {
    await seeded(tester, iphone);
    expect(find.text(card), findsOneWidget);

    await tapText(tester, card);
    expect(find.text(iosSteps.first), findsOneWidget);
    await tapText(tester, '稍後再說');
    expect(find.text(card), findsOneWidget, reason: 'back on the home page');

    await tester.tap(find.byTooltip('不再顯示'));
    await settle(tester);
    expect(find.text(card), findsNothing);
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
    expect(container.read(prefsProvider).getBool('add_to_home_hidden'), isTrue, reason: 'for good on this phone');
  });

  testWidgets('from a page that is not the church’s own, the reminder loads the church’s page', (tester) async {
    final loads = Loads();
    await seeded(tester, iphone, page: null, overrides: [loads.override]);
    await tapText(tester, card);
    expect(loads.pages, ['/c/grace?to=%2Fadd-to-home']);
  });

  testWidgets('opened from the home screen, joining goes straight to the church', (tester) async {
    await invited(tester, iphone, overrides: [standaloneProvider.overrideWithValue(true)]);
    await tapText(tester, '加入');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(card), findsNothing);
  });

  testWidgets('on a computer, starting a church goes straight to it', (tester) async {
    final loads = Loads();
    await startChurch(tester, windows, overrides: [loads.override]);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('加入主畫面'), findsNothing);
    expect(loads.pages, isEmpty);
  });

  testWidgets('on Android, Chrome’s offer installs in one tap, and the reminder goes', (tester) async {
    final offer = FakeOffer(offered: true);
    await invited(tester, android, overrides: [installOfferProvider.overrideWith(() => offer)]);
    await tapText(tester, '加入');
    expect(find.text(androidMenu), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '加入主畫面'));
    await settle(tester);
    expect(offer.shown, 1);
    expect(find.text('已加入主畫面，之後從主畫面的圖示打開'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(card), findsNothing, reason: 'installed: nothing to remind of');
  });

  testWidgets('turning down Chrome’s offer leaves the steps by hand', (tester) async {
    final offer = FakeOffer(offered: true, accept: false);
    await invited(tester, android, overrides: [installOfferProvider.overrideWith(() => offer)]);
    await tapText(tester, '加入');
    await tester.tap(find.widgetWithText(FilledButton, '加入主畫面'));
    await settle(tester);
    expect(find.widgetWithText(FilledButton, '加入主畫面'), findsNothing, reason: 'an offer works once');
    expect(find.text(androidMenu), findsOneWidget);
  });

  testWidgets('Chrome’s offer coming late still gets its button', (tester) async {
    final offer = FakeOffer();
    await invited(tester, android, overrides: [installOfferProvider.overrideWith(() => offer)]);
    await tapText(tester, '加入');
    expect(find.text(androidMenu), findsOneWidget);

    offer.offer();
    await settle(tester);
    expect(find.widgetWithText(FilledButton, '加入主畫面'), findsOneWidget);
    expect(find.text(androidMenu), findsNothing);
  });

  testWidgets('on an iPhone’s browser, 通知 says to add the app to the home screen first', (tester) async {
    await seeded(tester, iphone);
    routerOf(tester).go('/me/notifications');
    await settle(tester);

    for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(s.value, isFalse);
      expect(s.onChanged, isNull, reason: 'greyed out: nothing comes until then');
    }
    await tapText(tester, '先加入主畫面，才收得到通知');
    expect(find.text(iosSteps.first), findsOneWidget);
    await tapText(tester, '稍後再說');
    expect(find.text('先加入主畫面，才收得到通知'), findsOneWidget, reason: 'back on 通知');
  });

  testWidgets('opened from the home screen, 通知 has its switches', (tester) async {
    await seeded(tester, iphone, overrides: [standaloneProvider.overrideWithValue(true)]);
    routerOf(tester).go('/me/notifications');
    await settle(tester);
    expect(find.text('先加入主畫面，才收得到通知'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNotNull);
  });

  testWidgets('the steps wrap, not overflow, at the largest text size', (tester) async {
    await pumpApp(
      tester,
      seededChurch(),
      textScale: 2,
      overrides: [userAgentProvider.overrideWithValue(iphone), pageChurchProvider.overrideWithValue('grace')],
    );
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    expect(find.text('從主畫面打開，再登入一次'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('教會資訊 opens the same steps on a phone’s browser', (tester) async {
    await seeded(tester, iphone);
    routerOf(tester).go('/me/church');
    await settle(tester);
    await tapText(tester, '加入主畫面');
    expect(find.text(iosSteps.first), findsOneWidget);
  });
}
