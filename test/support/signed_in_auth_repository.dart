import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/auth_repository.dart';

/// 測試共用的 [AuthRepository]：[user] 已經登入，什麼都不寫。
///
/// 給只需要「有人登入」的 widget 測試 —— SessionProvider 要還原出一個使用者，
/// UserAdminProvider.getUsers() 才過得了權限檢查。要模擬登入失敗、阻塞或計數
/// 的測試各自有自己的 fake（session_provider_test、user_admin_provider_test）。
class SignedInAuthRepository implements AuthRepository {
  SignedInAuthRepository(this.user, {List<User>? users})
    : users = users ?? [?user];

  final User? user;

  /// [getUsers] 回傳的同工名單。預設只有登入的那個人。
  final List<User> users;

  @override
  Future<User?> getCachedUser() async => user;
  @override
  Future<User?> getCurrentUser() async => user;
  @override
  Future<void> writeCachedUser(User user) async {}
  @override
  Future<User?> login(String username, String password) async => user;
  @override
  Future<void> logout() async {}
  @override
  Future<List<User>> getUsers() async => users;
  @override
  Future<void> addUser(User user, String password) async {}
  @override
  Future<void> updateUser(User user, {String? password}) async {}
  @override
  Future<void> deleteUser(String id) async {}
}
