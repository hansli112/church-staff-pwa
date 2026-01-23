import '../entities/user.dart';

abstract class AuthRepository {
  Future<User?> login(String username, String password);
  Future<void> logout();
  Future<List<User>> getUsers();
  Future<void> addUser(User user, String password);
  Future<void> updateUser(User user);
  Future<void> deleteUser(String id);
}
