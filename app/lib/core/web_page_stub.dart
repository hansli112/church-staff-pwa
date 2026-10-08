/// Only the web page has a loading screen (web/index.html).
void hideSplash() {}

/// Only a browser has a user agent.
String userAgent() => '';

/// Only a web page can be opened from the home screen.
bool isStandalone() => false;

/// Only a browser counts touch points.
int touchPoints() => 0;

/// Only a web page has a church page behind it.
String? pageChurchId() => null;

/// Only a web page can be loaded again.
void loadPage(String location) {}

/// Only Chrome offers to install a web page.
bool installOffered() => false;

/// Shows Chrome's install dialog, which only a web page has.
Future<bool> showInstall() async => false;

/// Calls [changed] whenever Chrome's install offer comes or goes, which
/// only happens to a web page; the returned function stops it.
void Function() watchInstallOffer(void Function() changed) => () {};
