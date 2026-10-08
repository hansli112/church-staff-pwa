import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/fonts.dart';
import 'package:martha/features/auth/in_app_browser.dart';
import 'package:martha/features/church/links.dart';
import 'package:martha/state/fonts.dart';
import 'package:martha/state/web_page.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  testWidgets('the page’s loading screen comes down once the app is past loading', (tester) async {
    var hidden = 0;
    await pumpApp(tester, seededChurch(), overrides: [hideSplashProvider.overrideWithValue(() => hidden++)]);
    expect(hidden, greaterThan(0));
  });

  testWidgets('the loading screen stays until the engine has the fonts, so the first page has no boxes for text', (
    tester,
  ) async {
    var hidden = 0;
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        hideSplashProvider.overrideWithValue(() => hidden++),
        fontsReadyProvider.overrideWithValue(
          warmUpFonts(bundle: rootBundle, systemFonts: PaintingBinding.instance.systemFonts),
        ),
      ],
    );
    expect(hidden, 0);
    await sendFontsChange(tester);
    await tester.pumpAndSettle();
    expect(hidden, greaterThan(0));
  });

  testWidgets('fonts that never come hold the loading screen a few seconds at most', (
    tester,
  ) async {
    var hidden = 0;
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        hideSplashProvider.overrideWithValue(() => hidden++),
        fontsReadyProvider.overrideWithValue(Completer<void>().future),
      ],
    );
    expect(hidden, 0, reason: 'a second into the first page');
    await tester.pump(fontsWaitLimit);
    await tester.pumpAndSettle();
    expect(hidden, greaterThan(0));
  });

  test('an invite link opens outside LINE’s built-in browser, and still names its code', () {
    final link = inviteLink('grace', 'ABCDEFGH');
    expect(Uri.parse(link).queryParameters['openExternalBrowser'], '1');
    expect(Uri.parse(link).path, '/c/grace/join/ABCDEFGH');
    expect(inviteCodeIn(Uri.parse(link).path), 'ABCDEFGH');
    expect(inviteCodeIn('/c/grace/join/ABCDEFGH?openExternalBrowser=1'), 'ABCDEFGH', reason: 'as a login page’s from');
  });

  test('the built-in browsers of LINE, Facebook and Instagram are told apart from real ones', () {
    const line =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari Line/14.16.0';
    const lineAndroid =
        'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/129.0 Mobile Safari/537.36 Line/14.16.1/IAB';
    const facebook =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/480.0]';
    const instagram =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 350.0';
    const safari =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.7 Mobile/15E148 Safari/604.1';
    const chrome =
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
    expect(inAppBrowser(line), 'LINE');
    expect(inAppBrowser(lineAndroid), 'LINE');
    expect(inAppBrowser(facebook), 'Facebook');
    expect(inAppBrowser(instagram), 'Instagram');
    expect(inAppBrowser(safari), isNull);
    expect(inAppBrowser(chrome), isNull);
    expect(inAppBrowser('Mozilla/5.0 Pipeline/2.0'), isNull);
    expect(inAppBrowser(''), isNull);
  });
}
