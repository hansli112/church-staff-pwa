import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/native_or_browser.dart';

class Cancelled implements Exception {}

class NoCredential implements Exception {}

void main() {
  bool useBrowser(Object e) => e is NoCredential;

  test('native sign-in works: the browser is not opened', () async {
    var browser = 0;
    final user = await nativeOrBrowser(
      native: () async => 'native',
      browser: () async => '${browser++}',
      useBrowser: useBrowser,
    );
    expect(user, 'native');
    expect(browser, 0);
  });

  test('the device cannot sign in natively: the browser signs in instead', () async {
    final user = await nativeOrBrowser(
      native: () async => throw NoCredential(),
      browser: () async => 'browser',
      useBrowser: useBrowser,
    );
    expect(user, 'browser');
  });

  test('closing the native sheet cancels, without opening the browser', () async {
    var browser = 0;
    await expectLater(
      nativeOrBrowser(
        native: () async => throw Cancelled(),
        browser: () async => '${browser++}',
        useBrowser: useBrowser,
      ),
      throwsA(isA<Cancelled>()),
    );
    expect(browser, 0);
  });
}
