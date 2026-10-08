/// Only the web page has a loading screen (web/index.html).
void hideSplash() {}

/// Only a browser has a user agent.
String userAgent() => '';

/// Only a web page can be opened from the home screen.
bool isStandalone() => false;

/// Only a browser counts touch points.
int touchPoints() => 0;

/// Only Chrome offers to install a web page.
bool installOffered() => false;

/// Only Chrome offers to install a web page.
Future<bool> showInstall() async => false;
