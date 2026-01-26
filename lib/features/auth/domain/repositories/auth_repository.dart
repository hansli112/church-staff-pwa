import '../entities/user.dart';

abstract class AuthRepository {
  Future<User?> login(String username, String password);
  Future<User?> getCurrentUser();
  Future<void> logout();
  Future<List<User>> getUsers();
  Future<void> addUser(User user, String password);
  Future<void> updateUser(User user, {String? password});
  Future<void> deleteUser(String id);
}
