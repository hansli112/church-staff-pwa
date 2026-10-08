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

/// The church whose page this is: the one whose name and icon adding to
/// the home screen gives. Null for the plain app page, and off the web.
final pageChurchProvider = Provider<String?>((_) => page.pageChurchId());

/// Loads a location as a new web page, from the server.
final loadPageProvider = Provider<void Function(String location)>((_) => page.loadPage);

/// Whether Chrome is offering to install the web page right now. It can
/// come at any moment, and goes once used.
final installOfferProvider = NotifierProvider<InstallOffer, bool>(InstallOffer.new);

class InstallOffer extends Notifier<bool> {
  @override
  bool build() {
    ref.onDispose(page.watchInstallOffer(() => state = page.installOffered()));
    return page.installOffered();
  }

  /// Shows Chrome's install dialog; true when it was installed.
  Future<bool> show() async {
    final installed = await page.showInstall();
    state = page.installOffered();
    return installed;
  }
}
