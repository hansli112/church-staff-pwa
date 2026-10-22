import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Google sign-in in the browser, on a phone without a Google account, opens
/// a Custom Tab only when Android lets the app see the browsers that offer
/// one; otherwise it opens Chrome itself, which stays behind on "missing
/// initial state" after the app has signed in.
void main() {
  test('the app can see the browsers and their Custom Tabs', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final queries = RegExp(r'<queries>([\s\S]*?)</queries>').firstMatch(manifest)![1]!;
    expect(queries, contains('<action android:name="android.support.customtabs.action.CustomTabsService"/>'));
    expect(queries, contains('<action android:name="android.intent.action.VIEW"/>'));
    expect(queries, contains('<data android:scheme="https"/>'));
  });
}
