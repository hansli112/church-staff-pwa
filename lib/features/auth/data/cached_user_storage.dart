import 'dart:convert';
import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/user.dart';

/// Persists the last successfully fetched [User] profile to SharedPreferences
/// so the app can restore a full user object on cold start without waiting for
/// a Firestore round-trip.
///
/// The cache is intentionally kept simple — no encryption, no TTL.
/// SharedPreferences on Flutter Web is origin-isolated (stored per-origin in
/// the browser's localStorage), so it is not accessible to other origins.
/// Firestore Security Rules remain the authoritative access-control layer.
class CachedUserStorage {
  static const _key = 'cached_current_user_v1';

  /// Returns the cached [User], or `null` if there is no cache entry or the
  /// stored JSON is corrupt (corrupt entries are removed automatically).
  Future<User?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return null;
    try {
      return User.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      log('CachedUserStorage: corrupt cache, discarding. error=$e');
      await prefs.remove(_key);
      return null;
    }
  }

  /// Persists [user] to SharedPreferences, replacing any previous entry.
  Future<void> write(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(user.toJson()));
  }

  /// Removes the cached user entry.  Call this on logout.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
