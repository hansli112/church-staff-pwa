import '../auth/in_app_browser.dart';

/// The phone's platform, including embedded browsers that need an external one.
enum AddToHome { ios, android }

enum HomeBrowser { safari, chrome, edge, firefox, samsung, inApp, other }

/// A complete manual guide variant; the UI supplies its text and illustrations.
enum HomeGuide { safariIphone, safariIpad, chromeIos, chromeAndroid, firefoxIos, firefoxAndroid }

/// No guide is needed in a store app, on a computer, or when already installed.
AddToHome? addToHomeFor(String userAgent, {required bool standalone, required int touchPoints}) {
  if (standalone) return null;
  if (RegExp('iPhone|iPad|iPod').hasMatch(userAgent)) return AddToHome.ios;
  // An iPad asks for the desktop site, as a Mac with a touch screen.
  if (isHomeIpad(userAgent, touchPoints: touchPoints)) return AddToHome.ios;
  if (userAgent.contains('Android')) return AddToHome.android;
  return null;
}

bool isHomeIpad(String userAgent, {required int touchPoints}) =>
    userAgent.contains('iPad') || (userAgent.contains('Macintosh') && touchPoints > 1);

/// Check branded browsers before Chrome/Safari, whose tokens they also carry.
/// This is a best effort; the guide also lets the reader choose a browser.
HomeBrowser homeBrowserFor(String userAgent, AddToHome platform) {
  if (inAppBrowser(userAgent) != null || RegExp(r';\s*wv\b').hasMatch(userAgent)) return HomeBrowser.inApp;
  if (RegExp(r'EdgiOS/|EdgA/|Edg/').hasMatch(userAgent)) return HomeBrowser.edge;
  if (RegExp(r'FxiOS/|Firefox/').hasMatch(userAgent)) return HomeBrowser.firefox;
  if (platform == AddToHome.android && userAgent.contains('SamsungBrowser/')) return HomeBrowser.samsung;
  // Do not mistake other Chromium/WebKit browsers for Chrome or Safari.
  if (RegExp(r'OPR/|OPiOS/|DuckDuckGo/|GSA/|Vivaldi/|YaBrowser/|HuaweiBrowser/').hasMatch(userAgent)) {
    return HomeBrowser.other;
  }
  if (platform == AddToHome.ios && userAgent.contains('CriOS/')) return HomeBrowser.chrome;
  if (platform == AddToHome.android && userAgent.contains('Chrome/')) return HomeBrowser.chrome;
  if (platform == AddToHome.ios && userAgent.contains('Version/') && userAgent.contains('Safari/')) {
    return HomeBrowser.safari;
  }
  return HomeBrowser.other;
}

List<HomeBrowser> homeBrowsersFor(AddToHome platform) => [
  if (platform == AddToHome.ios) HomeBrowser.safari,
  HomeBrowser.chrome,
  HomeBrowser.edge,
  HomeBrowser.firefox,
  if (platform == AddToHome.android) HomeBrowser.samsung,
  HomeBrowser.inApp,
  HomeBrowser.other,
];

/// Null means there is no verified manual guide: use an external browser.
/// This does not rule out an actual install offer from an Android browser.
HomeGuide? homeGuideFor(AddToHome? platform, HomeBrowser browser, {required bool ipad}) =>
    switch ((platform, browser)) {
      (AddToHome.ios, HomeBrowser.safari) => ipad ? HomeGuide.safariIpad : HomeGuide.safariIphone,
      (AddToHome.ios, HomeBrowser.chrome) => HomeGuide.chromeIos,
      (AddToHome.ios, HomeBrowser.firefox) => HomeGuide.firefoxIos,
      (AddToHome.android, HomeBrowser.chrome) => HomeGuide.chromeAndroid,
      (AddToHome.android, HomeBrowser.firefox) => HomeGuide.firefoxAndroid,
      _ => null,
    };
