@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/web_page.dart';

/// Chrome's install offer, as web/index.html keeps it.
JSObject offer(String outcome) {
  final o = JSObject();
  var prompted = 0;
  o['prompt'] = (() {
    prompted++;
    return Future<JSAny?>.value().toJS;
  }).toJS;
  o['userChoice'] = Future.value(({'outcome': outcome}).jsify()).toJS;
  o['prompted'] = (() => prompted).toJS;
  return o;
}

void main() {
  tearDown(() => globalContext['marthaInstallPrompt'] = null);

  test('a page in a browser tab is not opened from the home screen', () {
    expect(isStandalone(), isFalse);
    expect(touchPoints(), isA<int>());
  });

  test('Chrome’s install offer is shown once, and says whether it was taken', () async {
    expect(installOffered(), isFalse);
    expect(await showInstall(), isFalse, reason: 'nothing offered');

    final o = offer('accepted');
    globalContext['marthaInstallPrompt'] = o;
    expect(installOffered(), isTrue);
    expect(await showInstall(), isTrue);
    expect((o.callMethod<JSNumber>('prompted'.toJS)).toDartInt, 1);
    expect(installOffered(), isFalse, reason: 'an offer works once');

    globalContext['marthaInstallPrompt'] = offer('dismissed');
    expect(await showInstall(), isFalse);
  });
}
