import 'package:flutter/foundation.dart';

/// Signs in with the platform's own Google sheet, or, when the device cannot
/// (no Google account on it, Play services too old for Credential Manager),
/// with the browser flow. [useBrowser] picks the errors that mean "the device
/// cannot"; any other error, such as closing the sheet, comes through.
Future<T> nativeOrBrowser<T>({
  required Future<T> Function() native,
  required Future<T> Function() browser,
  required bool Function(Object error) useBrowser,
}) async {
  try {
    return await native();
  } catch (e) {
    if (!useBrowser(e)) rethrow;
    debugPrint('Native Google sign-in failed, using the browser: $e');
    return browser();
  }
}
