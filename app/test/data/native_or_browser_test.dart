import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
      onFallback: (_, _) => fail('nothing to report'),
    );
    expect(user, 'native');
    expect(browser, 0);
  });

  test('the device cannot sign in natively: the browser signs in instead, and the reason is reported', () async {
    final reasons = <Object>[];
    final user = await nativeOrBrowser(
      native: () async => throw NoCredential(),
      browser: () async => 'browser',
      useBrowser: useBrowser,
      onFallback: (e, _) => reasons.add(e),
    );
    expect(user, 'browser');
    expect(reasons.single, isA<NoCredential>());
  });

  test('closing the native sheet cancels, without opening the browser', () async {
    var browser = 0;
    await expectLater(
      nativeOrBrowser(
        native: () async => throw Cancelled(),
        browser: () async => '${browser++}',
        useBrowser: useBrowser,
        onFallback: (_, _) => fail('nothing to report'),
      ),
      throwsA(isA<Cancelled>()),
    );
    expect(browser, 0);
  });

  group('which native Google errors the browser can work around', () {
    GoogleSignInException failed(GoogleSignInExceptionCode code) => GoogleSignInException(code: code);

    test('no Google account on the device, or Credential Manager missing: yes', () {
      // google_sign_in_android reports "no credential" as unknownError and
      // "Credential Manager not supported" as providerConfigurationError.
      expect(nativeGoogleUnavailable(failed(GoogleSignInExceptionCode.unknownError)), isTrue);
      expect(nativeGoogleUnavailable(failed(GoogleSignInExceptionCode.providerConfigurationError)), isTrue);
    });

    test('our own setup is wrong, or the person cancelled: no, so it shows', () {
      expect(nativeGoogleUnavailable(failed(GoogleSignInExceptionCode.clientConfigurationError)), isFalse);
      expect(nativeGoogleUnavailable(failed(GoogleSignInExceptionCode.canceled)), isFalse);
      expect(nativeGoogleUnavailable(failed(GoogleSignInExceptionCode.interrupted)), isFalse);
      expect(nativeGoogleUnavailable(failed(GoogleSignInExceptionCode.uiUnavailable)), isFalse);
    });

    test('errors from elsewhere (Firebase after the sheet): no', () {
      expect(nativeGoogleUnavailable(Exception('firebase')), isFalse);
    });
  });
}
