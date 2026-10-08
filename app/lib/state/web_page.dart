import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/web_page.dart' as page;

/// Takes down the web page's loading screen; nothing elsewhere.
final hideSplashProvider = Provider<void Function()>((_) => page.hideSplash);

/// The browser's user agent; empty off the web.
final userAgentProvider = Provider<String>((_) => page.userAgent());
