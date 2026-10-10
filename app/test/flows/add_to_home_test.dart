import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart' show ListRow;
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/church/add_to_home.dart';
import 'package:martha/features/church/links.dart';
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

const iosSteps = [
  '點「⋯」，再選「分享」',
  '點「加入主畫面」',
  '點手機上的「恩典堂」圖示打開，再登入一次',
];
const androidMenu = '安裝並建立捷徑 → 安裝';
const card = '一點就打開，也收得到服事通知';

Future<void> tapText(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text(text), 300, scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(find.text(text).last);
  await settle(tester);
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
    expect(on(line), AddToHome.ios, reason: 'LINE gets instructions to switch to an external browser');
    expect(on(windows), isNull);
    expect(on(''), isNull, reason: 'a store app');
  });

  testWidgets('joining on an iPhone’s browser shows how to add the app to the home screen first', (tester) async {
    final (b, cid) = await invited(tester, iphone);
    await tapText(tester, '加入');

    expect(b.members[cid]![b.auth.currentUser!.uid], isNotNull);
    expect(find.text('加入主畫面'), findsOneWidget, reason: 'the title');
    for (final step in iosSteps) {
      expect(findShown(step), findsOneWidget);
    }
    expect(find.text('開啟後要收服事通知：我的 → 通知 → 開啟通知'), findsOneWidget);

    await tapText(tester, '稍後再說');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(card), findsOneWidget, reason: 'the home page reminds of it');
  });

  testWidgets('iPhone Chrome points to page sharing, not the more menu or Share Chrome', (tester) async {
    await seeded(tester, '$iphone CriOS/140.0.7339.39');
    routerOf(tester).go('/add-to-home');
    await settle(tester);

    expect(find.text('點網址列旁的分享圖示'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.text('不是「⋯」選單，也不是「分享 Chrome」'), findsOneWidget);
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
    expect(find.text('已加入，之後點手機上的「恩典堂」圖示打開'), findsOneWidget);
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
    expect(findShown('點手機上的「恩典堂」圖示打開，再登入一次'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final ua in [iphone, '$iphone CriOS/140.0', '$iphone FxiOS/140.0', android, '$android EdgA/140.0', line]) {
      testWidgets('guide fits a narrow phone with large text: $brightness / $ua', (tester) async {
        await pumpApp(
          tester,
          seededChurch(),
          brightness: brightness,
          textScale: 2,
          overrides: [userAgentProvider.overrideWithValue(ua), pageChurchProvider.overrideWithValue('grace')],
        );
        tester.view.physicalSize = const Size(320 * 3, 640 * 3);
        routerOf(tester).go('/add-to-home');
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tapText(tester, '畫面不一樣？');
        expect(tester.takeException(), isNull);
        await tapText(tester, 'Chrome');
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('稍後再說'), 300, scrollable: find.byType(Scrollable).first);
        await tapText(tester, '稍後再說');
        expect(find.byType(NavigationBar), findsOneWidget, reason: 'the exit stays reachable');
      });
    }
  }

  testWidgets('the browser picker switches the guide without opening a different browser', (tester) async {
    final loads = Loads();
    await seeded(tester, '$iphone CriOS/140.0', overrides: [loads.override]);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    await tapText(tester, '畫面不一樣？');
    expect(find.text('Samsung Internet'), findsNothing);
    expect(find.text('只切換教學，不會替你開啟另一個瀏覽器'), findsOneWidget);
    await tapText(tester, 'Safari');
    expect(find.text(iosSteps.first), findsOneWidget);
    expect(find.text('點網址列旁的分享圖示'), findsNothing);
    expect(loads.pages, isEmpty);
  });

  for (final ua in [line, '$iphone [FBAN/FBIOS]', '$iphone Instagram 350.0', '$iphone EdgiOS/140.0']) {
    testWidgets('iOS embedded or unsupported browser copies the church guide: $ua', (tester) async {
      final out = captureOutbox(tester);
      await seeded(tester, ua);
      await tapText(tester, card);
      expect(find.text('先用 Safari 開啟'), findsOneWidget);
      expect(find.text('點 Safari 的分享圖示'), findsNothing, reason: 'do not show Safari controls inside another app');
      await tapText(tester, '複製教會網址');
      expect(out.copied, ['${churchUrl('grace')}?to=%2Fadd-to-home']);
      expect(find.text('已複製，請開啟 Safari，貼到網址列'), findsOneWidget);
    });
  }

  testWidgets('a refused clipboard offers the church link to copy by hand', (tester) async {
    captureOutbox(tester, blocked: true);
    await seeded(tester, line);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    await tapText(tester, '複製教會網址');
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data, '${churchUrl('grace')}?to=%2Fadd-to-home');
    expect(find.text('已複製，請開啟 Safari，貼到網址列'), findsNothing);
  });

  testWidgets('Chrome iOS troubleshooting offers Safari without claiming to install', (tester) async {
    final out = captureOutbox(tester);
    await seeded(tester, '$iphone CriOS/140.0');
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    expect(find.text('複製教會網址'), findsNothing);
    await tapText(tester, '找不到「加入主畫面」？');
    await tapText(tester, '複製教會網址');
    expect(out.copied, ['${churchUrl('grace')}?to=%2Fadd-to-home']);
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(container.read(addToHomeHiddenProvider), isFalse);
  });

  for (final (suffix, title) in [
    ('', '點 Chrome 的選單'),
    (' Firefox/140.0', '點 Firefox 的選單'),
  ]) {
    testWidgets('Android browser has its own menu: $title', (tester) async {
      await seeded(tester, '$android$suffix');
      routerOf(tester).go('/add-to-home');
      await settle(tester);
      expect(find.text(title), findsOneWidget);
      expect(find.text('點網址列旁的分享圖示'), findsNothing);
    });
  }

  testWidgets('Android embedded browser opens Chrome instead of offering installation', (tester) async {
    final offer = FakeOffer(offered: true);
    final out = captureOutbox(tester);
    await seeded(tester, '$android Line/14.16.0', overrides: [installOfferProvider.overrideWith(() => offer)]);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    expect(find.text('先用 Chrome 開啟'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '加入主畫面'), findsNothing);
    await tapText(tester, '複製教會網址');
    expect(out.copied, ['${churchUrl('grace')}?to=%2Fadd-to-home']);
    expect(offer.shown, 0);
  });

  testWidgets('choosing another guide cannot use the current browser’s install offer', (tester) async {
    final offer = FakeOffer(offered: true);
    await seeded(tester, android, overrides: [installOfferProvider.overrideWith(() => offer)]);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    await tapText(tester, '畫面不一樣？');
    await tapText(tester, 'Samsung Internet');
    expect(find.widgetWithText(FilledButton, '加入主畫面'), findsNothing);
    expect(find.text('先用 Chrome 開啟'), findsOneWidget);
    expect(offer.shown, 0);
  });

  for (final suffix in [' EdgA/140.0', ' SamsungBrowser/28.0', ' OPR/80.0']) {
    testWidgets('unverified Android menus offer a safe fallback: $suffix', (tester) async {
      await seeded(tester, '$android$suffix');
      routerOf(tester).go('/add-to-home');
      await settle(tester);
      expect(find.text('先用 Chrome 開啟'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing, reason: 'do not invent Chrome menus in other browsers');
    });
  }

  testWidgets('Samsung can use an actual install offer despite unknown manual menu layout', (tester) async {
    final offer = FakeOffer(offered: true);
    await seeded(tester, '$android SamsungBrowser/28.0', overrides: [installOfferProvider.overrideWith(() => offer)]);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '加入主畫面'));
    await settle(tester);
    expect(offer.shown, 1);
  });

  testWidgets('iOS Firefox uses its own share entry rather than Safari’s more menu', (tester) async {
    await seeded(tester, '$iphone FxiOS/140.0');
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    expect(find.text('點網址列的分享圖示'), findsOneWidget);
    expect(find.text('若只看到「⋯」，先點它，再選「分享」'), findsNothing);
  });

  testWidgets('iPad Safari opens share before More, including a desktop user agent', (tester) async {
    await seeded(tester, mac, overrides: [touchPointsProvider.overrideWithValue(5)]);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    expect(find.text('iPad · Safari 教學'), findsOneWidget);
    expect(find.text('點 Safari 的分享圖示'), findsOneWidget);
    expect(find.text('若只看到「⋯」，先點它，再選「分享」'), findsNothing);
    expect(find.textContaining('先點分享面板中的「更多」'), findsOneWidget);
  });

  testWidgets('Safari shows Chinese captured menus, including View More before Add to Home Screen', (tester) async {
    await seeded(tester, iphone);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    final screenshots = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>();
    expect(
      screenshots.map((image) => image.assetName),
      containsAll([
        'assets/add_to_home/safari_more.png',
        'assets/add_to_home/safari_share.png',
        'assets/add_to_home/safari_share_more.png',
        'assets/add_to_home/safari_add.png',
      ]),
    );
    expect(find.textContaining('若只看到一排圖示，先點「檢視較多」；舊版可往下滑'), findsOneWidget);
    expect(find.text('Safari · iOS 26.5 · 繁中模擬器畫面'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPhone Safari can choose the visible toolbar without changing browser or settings', (tester) async {
    final loads = Loads();
    await seeded(tester, iphone, overrides: [loads.override]);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    await tapText(tester, '畫面不一樣？');
    expect(find.text('Safari 畫面'), findsOneWidget);
    expect(find.text('我看到「⋯」'), findsOneWidget);
    expect(find.text('我看到分享圖示'), findsOneWidget);
    expect(
      tester
          .widgetList<ListRow>(find.byType(ListRow))
          .where((row) => row.title.startsWith('我看到'))
          .map((row) => row.selected),
      [false, false],
      reason: 'the page cannot detect Safari layout; neither choice is guessed',
    );
    expect(find.text('請依工具列上的按鈕選擇，不需要更改 Safari 設定'), findsOneWidget);
    await tapText(tester, '我看到分享圖示');

    expect(routerOf(tester).routeInformationProvider.value.uri.path, '/add-to-home');
    expect(find.text('點 Safari 的分享圖示'), findsOneWidget);
    expect(find.text('網址列在上或下都可以，請找「方框向上箭頭」'), findsOneWidget);
    expect(find.text('若只看到「⋯」，先點它，再選「分享」'), findsNothing);
    final images = tester.widgetList<Image>(find.byType(Image)).map((image) => image.image).whereType<AssetImage>();
    expect(images.map((image) => image.assetName), contains('assets/add_to_home/safari_direct_share.png'));
    expect(images.map((image) => image.assetName), isNot(contains('assets/add_to_home/safari_more.png')));
    expect(images.map((image) => image.assetName), isNot(contains('assets/add_to_home/safari_share.png')));
    expect(
      images.map((image) => image.assetName),
      containsAll([
        'assets/add_to_home/safari_share_more.png',
        'assets/add_to_home/safari_add.png',
      ]),
    );
    expect(loads.pages, isEmpty);

    await tapText(tester, '畫面不一樣？');
    await tapText(tester, '我看到「⋯」');
    expect(find.text('點「⋯」，再選「分享」'), findsOneWidget);
    final compact = tester.widgetList<Image>(find.byType(Image)).map((image) => image.image).whereType<AssetImage>();
    expect(compact.map((image) => image.assetName), contains('assets/add_to_home/safari_more.png'));
    expect(compact.map((image) => image.assetName), isNot(contains('assets/add_to_home/safari_direct_share.png')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Safari toolbar choice survives switching guide and never leaks into Chrome', (tester) async {
    await seeded(tester, iphone);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    await tapText(tester, '畫面不一樣？');
    await tapText(tester, '我看到分享圖示');
    await tapText(tester, '畫面不一樣？');
    await tapText(tester, 'Chrome');
    expect(find.text('點網址列旁的分享圖示'), findsOneWidget);
    expect(find.text('網址列在上或下都可以，請找「方框向上箭頭」'), findsNothing);
    await tapText(tester, '畫面不一樣？');
    expect(find.text('Safari 畫面'), findsNothing);
    await tapText(tester, 'Safari');
    expect(find.text('網址列在上或下都可以，請找「方框向上箭頭」'), findsOneWidget);
  });

  testWidgets('iPad Safari keeps its own share order instead of iPhone layout choices', (tester) async {
    await seeded(tester, mac, overrides: [touchPointsProvider.overrideWithValue(5)]);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    await tapText(tester, '畫面不一樣？');
    expect(find.text('Safari 畫面'), findsNothing);
    expect(find.text('我看到「⋯」'), findsNothing);
    await tapText(tester, 'Safari');
    expect(find.text('點 Safari 的分享圖示'), findsOneWidget);
    expect(find.textContaining('先點分享面板中的「更多」'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('Safari layout choices and direct guide fit large text: $brightness', (tester) async {
      await pumpApp(
        tester,
        seededChurch(),
        brightness: brightness,
        textScale: 2,
        overrides: [userAgentProvider.overrideWithValue(iphone), pageChurchProvider.overrideWithValue('grace')],
      );
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      routerOf(tester).go('/add-to-home');
      await settle(tester);
      await tapText(tester, '畫面不一樣？');
      expect(tester.takeException(), isNull);
      await tapText(tester, '我看到分享圖示');
      expect(tester.takeException(), isNull);
      await tapText(tester, '稍後再說');
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  }

  testWidgets('Chrome does not show Safari screenshots or claim the old Android capture is current', (tester) async {
    await seeded(tester, '$iphone CriOS/140.0');
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    final iosImages = tester.widgetList<Image>(find.byType(Image)).map((image) => image.image).whereType<AssetImage>();
    expect(
      iosImages.map((image) => image.assetName),
      containsAll(['assets/add_to_home/chrome_ios_share.png', 'assets/add_to_home/chrome_ios_add.png']),
    );
    expect(iosImages.map((image) => image.assetName), everyElement(isNot(contains('safari'))));
    expect(find.text('Chrome 155 · iOS 27.2 · iPhone 13 真機畫面'), findsNWidgets(2));
    expect(find.textContaining('看不到時，先將分享面板展開，再往下滑'), findsOneWidget);
    expect(find.text('按鈕示意，請點瀏覽器上的按鈕'), findsNothing);
    expect(find.text('點網址列旁的分享圖示'), findsOneWidget);

    await seeded(tester, android);
    routerOf(tester).go('/add-to-home');
    await settle(tester);
    expect(find.text('Chrome 113 · Android 14 · 繁中模擬器畫面（舊版選單）'), findsNWidgets(2));
    final screenshots = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>();
    expect(
      screenshots.map((image) => image.assetName),
      containsAll([
        'assets/add_to_home/chrome_android_more.png',
        'assets/add_to_home/chrome_android_add.png',
      ]),
    );
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
