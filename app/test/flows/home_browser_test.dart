import 'package:flutter_test/flutter_test.dart';
import 'package:martha/features/church/home_browser.dart';

const safari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 Version/18.7 Mobile/15E148 Safari/604.1';
const chrome = 'Mozilla/5.0 (Linux; Android 14; SM-A546E) AppleWebKit/537.36 Chrome/129.0.0.0 Mobile Safari/537.36';

void main() {
  for (final (platform, ua, expected) in [
    (AddToHome.ios, safari, HomeBrowser.safari),
    (AddToHome.ios, '$safari CriOS/140.0', HomeBrowser.chrome),
    (AddToHome.ios, '$safari EdgiOS/140.0', HomeBrowser.edge),
    (AddToHome.ios, '$safari FxiOS/140.0', HomeBrowser.firefox),
    (AddToHome.ios, '$safari OPiOS/3.0', HomeBrowser.other),
    (AddToHome.ios, '$safari GSA/300.0', HomeBrowser.other),
    (AddToHome.ios, '$safari DuckDuckGo/7', HomeBrowser.other),
    (AddToHome.ios, '$safari Line/14.16.0', HomeBrowser.inApp),
    (AddToHome.ios, '$safari [FBAN/FBIOS;FBAV/500.0]', HomeBrowser.inApp),
    (AddToHome.ios, '$safari Instagram 350.0', HomeBrowser.inApp),
    (AddToHome.ios, 'AppleWebKit/605.1.15 Mobile/15E148', HomeBrowser.other),
    (AddToHome.ios, 'Mozilla/5.0 Macintosh Version/18.7 Safari/605.1.15', HomeBrowser.safari),
    (AddToHome.android, chrome, HomeBrowser.chrome),
    (AddToHome.android, '$chrome EdgA/140.0', HomeBrowser.edge),
    (AddToHome.android, 'Mozilla/5.0 Android 14 Gecko/140.0 Firefox/140.0', HomeBrowser.firefox),
    (AddToHome.android, '$chrome SamsungBrowser/28.0', HomeBrowser.samsung),
    (AddToHome.android, '$chrome OPR/80.0', HomeBrowser.other),
    (AddToHome.android, '$chrome HuaweiBrowser/15.0', HomeBrowser.other),
    (AddToHome.android, '$chrome Line/14.16.0', HomeBrowser.inApp),
    (AddToHome.android, '$chrome [FB_IAB/FB4A;FBAV/500.0]', HomeBrowser.inApp),
    (AddToHome.android, '$chrome Instagram 350.0', HomeBrowser.inApp),
    (AddToHome.android, '$chrome (Linux; Android 14; Pixel 8; wv)', HomeBrowser.inApp),
    (AddToHome.android, 'Mozilla/5.0 Android 14', HomeBrowser.other),
  ]) {
    test('${platform.name}: ${expected.name} from $ua', () {
      expect(homeBrowserFor(ua, platform), expected);
    });
  }

  const guides = {
    (AddToHome.ios, HomeBrowser.safari, false): HomeGuide.safariIphone,
    (AddToHome.ios, HomeBrowser.safari, true): HomeGuide.safariIpad,
    (AddToHome.ios, HomeBrowser.chrome, false): HomeGuide.chromeIos,
    (AddToHome.ios, HomeBrowser.chrome, true): HomeGuide.chromeIos,
    (AddToHome.ios, HomeBrowser.firefox, false): HomeGuide.firefoxIos,
    (AddToHome.ios, HomeBrowser.firefox, true): HomeGuide.firefoxIos,
    (AddToHome.android, HomeBrowser.chrome, false): HomeGuide.chromeAndroid,
    (AddToHome.android, HomeBrowser.chrome, true): HomeGuide.chromeAndroid,
    (AddToHome.android, HomeBrowser.firefox, false): HomeGuide.firefoxAndroid,
    (AddToHome.android, HomeBrowser.firefox, true): HomeGuide.firefoxAndroid,
  };
  for (final platform in [null, ...AddToHome.values]) {
    for (final browser in HomeBrowser.values) {
      for (final ipad in [false, true]) {
        final expected = guides[(platform, browser, ipad)];
        test(
          '${platform?.name ?? 'no platform'} / ${browser.name} / iPad=$ipad: ${expected?.name ?? 'external browser'}',
          () {
            expect(homeGuideFor(platform, browser, ipad: ipad), expected);
          },
        );
      }
    }
  }

  test('Safari iPads use the iPad guide, including a desktop user agent', () {
    for (final (ua, touchPoints) in [
      (safari.replaceAll('iPhone', 'iPad'), 0),
      ('Mozilla/5.0 Macintosh Version/18.7 Safari/605.1.15', 5),
    ]) {
      final platform = addToHomeFor(ua, standalone: false, touchPoints: touchPoints);
      expect(platform, AddToHome.ios);
      expect(
        homeGuideFor(platform, homeBrowserFor(ua, platform!), ipad: isHomeIpad(ua, touchPoints: touchPoints)),
        HomeGuide.safariIpad,
      );
    }
  });

  test('the manual picker offers only browsers on that platform', () {
    expect(homeBrowsersFor(AddToHome.ios), contains(HomeBrowser.safari));
    expect(homeBrowsersFor(AddToHome.ios), isNot(contains(HomeBrowser.samsung)));
    expect(homeBrowsersFor(AddToHome.android), contains(HomeBrowser.samsung));
    expect(homeBrowsersFor(AddToHome.android), isNot(contains(HomeBrowser.safari)));
    for (final platform in AddToHome.values) {
      expect(homeBrowsersFor(platform), containsAll([HomeBrowser.chrome, HomeBrowser.edge, HomeBrowser.firefox]));
      expect(homeBrowsersFor(platform), containsAll([HomeBrowser.inApp, HomeBrowser.other]));
    }
  });
}
