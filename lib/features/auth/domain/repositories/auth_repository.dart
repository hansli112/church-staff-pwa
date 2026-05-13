import '../entities/user.dart';

abstract class AuthRepository {
  Future<User?> login(String username, String password);

  /// Fetch the current user.  Makes network calls (Firebase Auth stream +
  /// Firestore profile fetch).  Use [getCachedUser] for an instant, no-network
  /// read on startup.
  Future<User?> getCurrentUser();

  /// Returns the last successfully fetched [User] from local storage without
  /// any network calls (~10 ms).  Returns `null` if there is no local cache —
  /// e.g. on a fresh install or after logout.
  ///
  /// Callers MUST still call [getCurrentUser] in the background to verify the
  /// Firebase Auth session is still valid and to pick up any profile changes.
  Future<User?> getCachedUser();

  Future<void> logout();
  Future<List<User>> getUsers();
  Future<void> addUser(User user, String password);
  Future<void> updateUser(User user, {String? password});
  Future<void> deleteUser(String id);
}
