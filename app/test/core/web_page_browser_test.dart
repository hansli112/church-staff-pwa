@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
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

  test('the church whose page this is comes from its manifest', () {
    final link = web.document.createElement('link')..setAttribute('rel', 'manifest');
    web.document.head!.append(link);
    addTearDown(() => link.remove());

    link.setAttribute('href', '/c/grace/manifest.json');
    expect(pageChurchId(), 'grace');
    link.setAttribute('href', 'manifest.json');
    expect(pageChurchId(), isNull, reason: 'the plain app page');
  });

  test('the app hears of Chrome’s offer coming or going', () {
    var heard = 0;
    final stop = watchInstallOffer(() => heard++);
    web.window.dispatchEvent(web.Event('martha-install-offer'));
    expect(heard, 1);
    stop();
    web.window.dispatchEvent(web.Event('martha-install-offer'));
    expect(heard, 1, reason: 'stopped');
  });
}
