import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get online => web.window.navigator.onLine;

Stream<bool> get changes {
  late final StreamController<bool> out;
  final on = ((web.Event _) => out.add(true)).toJS;
  final off = ((web.Event _) => out.add(false)).toJS;
  out = StreamController<bool>(
    onListen: () {
      web.window.addEventListener('online', on);
      web.window.addEventListener('offline', off);
    },
    onCancel: () {
      web.window.removeEventListener('online', on);
      web.window.removeEventListener('offline', off);
    },
  );
  return out.stream;
}
