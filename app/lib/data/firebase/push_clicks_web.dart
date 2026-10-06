import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// App routes from notifications tapped while a tab of the app is open.
///
/// The Firebase service worker then only focuses that tab and posts it a
/// `notification-clicked` message, which neither the JS SDK nor FlutterFire
/// acts on (onMessageOpenedApp never fires on the web). With no tab open it
/// opens the notification's link instead, and the URL does the routing.
Stream<String> webNotificationClicks() {
  final out = StreamController<String>();
  void onMessage(web.MessageEvent e) {
    final m = e.data.dartify();
    if (m is! Map || m['isFirebaseMessaging'] != true || m['messageType'] != 'notification-clicked') return;
    final data = m['data'];
    final link = data is Map ? data['link'] : null;
    if (link is String) out.add(link);
  }

  final listener = onMessage.toJS;
  out.onListen = () => web.window.navigator.serviceWorker.addEventListener('message', listener);
  out.onCancel = () => web.window.navigator.serviceWorker.removeEventListener('message', listener);
  return out.stream;
}
