import 'package:web/web.dart' as web;

/// Takes down the page's loading screen (web/index.html, filled in by
/// functions/src/churchPage.ts), which covers the app until then.
void hideSplash() => web.document.getElementById('splash')?.remove();

/// The browser's user agent, which tells an app's built-in browser apart.
String userAgent() => web.window.navigator.userAgent;
