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
    final intents = [for (final m in RegExp(r'<intent>([\s\S]*?)</intent>').allMatches(queries)) m[1]!];
    expect(
      intents.where((i) => i.contains('android.intent.action.VIEW') && i.contains('android:scheme="https"')),
      hasLength(1),
      reason: 'the browsers',
    );
    expect(
      intents.where((i) => i.contains('android.support.customtabs.action.CustomTabsService')),
      hasLength(1),
      reason: 'their Custom Tabs',
    );
  });
}
