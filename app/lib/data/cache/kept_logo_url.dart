import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A church logo's download URL for its [version] (the church's
/// logoVersion): kept on this device from the last time, so opening the app
/// does not wait on Storage for it again; looked up with [lookUp] and kept
/// when there is none, or one for another version.
Future<String> keptLogoUrl(
  Future<SharedPreferences> prefs, {
  required String churchId,
  required String version,
  required Future<String> Function() lookUp,
}) async {
  final key = 'church_logo_url_$churchId';
  SharedPreferences? kept;
  try {
    kept = await prefs;
    final saved = jsonDecode(kept.getString(key) ?? 'null');
    if (saved is Map && saved['version'] == version && saved['url'] is String) return saved['url'] as String;
  } catch (_) {
    // Nothing kept, or unreadable: look it up.
  }
  final url = await lookUp();
  unawaited(kept?.setString(key, jsonEncode({'version': version, 'url': url})));
  return url;
}
