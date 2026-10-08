import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/web_page.dart' as page;

/// Takes down the web page's loading screen; nothing elsewhere.
final hideSplashProvider = Provider<void Function()>((_) => page.hideSplash);

/// The browser's user agent; empty off the web.
final userAgentProvider = Provider<String>((_) => page.userAgent());

/// The web page was opened from the home screen; false elsewhere.
final standaloneProvider = Provider<bool>((_) => page.isStandalone());

/// How many touch points the browser reports; 0 off the web.
final touchPointsProvider = Provider<int>((_) => page.touchPoints());

/// Chrome's offer to install the web page: whether it made one (asked
/// each time, since it can come at any moment), and showing it, which says
/// whether it was installed.
typedef InstallPrompt = ({bool Function() offered, Future<bool> Function() show});

final installPromptProvider = Provider<InstallPrompt>(
  (_) => (offered: page.installOffered, show: page.showInstall),
);
