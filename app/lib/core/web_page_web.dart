import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Takes down the page's loading screen (web/index.html, filled in by
/// functions/src/churchPage.ts), which covers the app until then.
void hideSplash() => web.document.getElementById('splash')?.remove();

/// The browser's user agent, which tells an app's built-in browser apart.
String userAgent() => web.window.navigator.userAgent;

/// Opened from the home screen: Android's display mode, or iOS's own flag.
bool isStandalone() =>
    web.window.matchMedia('(display-mode: standalone)').matches ||
    (web.window.navigator as _Navigator).standalone == true;

/// How many fingers the screen takes: an iPad says it is a Mac, but a Mac
/// has no touch screen.
int touchPoints() => web.window.navigator.maxTouchPoints;

/// Chrome's offer to install the page (`beforeinstallprompt`), kept by
/// web/index.html until used: it fires before the app starts.
@JS('marthaInstallPrompt')
external JSObject? _installPrompt;

/// Whether Chrome has offered to install the page.
bool installOffered() => _installPrompt != null;

/// Shows Chrome's install dialog; true when it was installed. An offer
/// works once.
Future<bool> showInstall() async {
  final offer = _installPrompt as _InstallPrompt?;
  if (offer == null) return false;
  _installPrompt = null;
  await offer.prompt().toDart;
  return (await offer.userChoice.toDart).outcome == 'accepted';
}

extension type _Navigator._(JSObject _) implements JSObject {
  external bool? get standalone;
}

extension type _InstallPrompt._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> prompt();
  external JSPromise<_Choice> get userChoice;
}

extension type _Choice._(JSObject _) implements JSObject {
  external String get outcome;
}
