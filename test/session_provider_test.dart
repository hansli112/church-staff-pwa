import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/auth_repository.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';

// ── Fake AuthRepository ────────────────────────────────────────────────────

class _FakeAuthRepository implements AuthRepository {
  /// 若不為 null，`login` 回傳此 user（模擬成功）。
  /// 若為 null，`login` 回傳 null（模擬帳密錯誤）。
  User? loginResult;

  /// 若不為 null，`login` 會 throw 此例外。
  Object? loginException;

  /// `getCurrentUser` 回傳值（模擬 session restore）。
  User? currentUserResult;

  bool logoutCalled = false;

  @override
  Future<User?> login(String username, String password) async {
    if (loginException != null) throw loginException!;
    return loginResult;
  }

  @override
  Future<User?> getCurrentUser() async => currentUserResult;

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }

  @override
  Future<List<User>> getUsers() async => [];

  @override
  Future<void> addUser(User user, String password) async {}

  @override
  Future<void> updateUser(User user, {String? password}) async {}

  @override
  Future<void> deleteUser(String id) async {}
}

// ── 測試用 User helper ──────────────────────────────────────────────────────

const _userAlpha = User(
  id: 'uid-alpha',
  name: 'Alpha User',
  email: 'alpha@example.com',
  username: 'alpha',
  role: UserRole.admin,
);

const _userBeta = User(
  id: 'uid-beta',
  name: 'Beta User',
  email: 'beta@example.com',
  username: 'beta',
  role: UserRole.staff,
);

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('SessionProvider', () {
    late _FakeAuthRepository repo;

    setUp(() {
      repo = _FakeAuthRepository();
    });

    // 等 _restoreSession 完成的輔助方法
    Future<SessionProvider> createAndWait({User? currentUser}) async {
      repo.currentUserResult = currentUser;
      final provider = SessionProvider(repo);
      // _restoreSession 是 async；等一個 microtask cycle 讓它跑完
      await Future.microtask(() {});
      return provider;
    }

    // ── _restoreSession ──────────────────────────────────────────────────

    test('constructor 觸發 _restoreSession；完成後 isRestoring 變 false', () async {
      final provider = await createAndWait();
      expect(provider.isRestoring, false);
    });

    test('_restoreSession 成功時 currentUser 對應 repository 回傳值', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      expect(provider.currentUser, _userAlpha);
      expect(provider.isAuthenticated, true);
    });

    test('_restoreSession：repository 回傳 null 時 currentUser 為 null', () async {
      final provider = await createAndWait();
      expect(provider.currentUser, isNull);
      expect(provider.isAuthenticated, false);
    });

    // ── login 成功 ────────────────────────────────────────────────────────

    test('login 成功 → isAuthenticated true、currentUser 不為 null、error 為 null', () async {
      repo.loginResult = _userAlpha;
      final provider = await createAndWait();

      final result = await provider.login('alpha', 'password123');

      expect(result, true);
      expect(provider.isAuthenticated, true);
      expect(provider.currentUser, _userAlpha);
      expect(provider.error, isNull);
    });

    test('login 成功後 isLoading 回到 false', () async {
      repo.loginResult = _userAlpha;
      final provider = await createAndWait();
      await provider.login('alpha', 'pass');
      expect(provider.isLoading, false);
    });

    // ── login 失敗（repository 回傳 null）────────────────────────────────

    test('login 失敗（repository 回傳 null）→ error 為「帳號或密碼錯誤」', () async {
      repo.loginResult = null;
      final provider = await createAndWait();

      final result = await provider.login('wrong', 'wrongpass');

      expect(result, false);
      expect(provider.error, '帳號或密碼錯誤');
      expect(provider.isAuthenticated, false);
    });

    test('login 失敗後 isLoading 回到 false', () async {
      repo.loginResult = null;
      final provider = await createAndWait();
      await provider.login('wrong', 'wrong');
      expect(provider.isLoading, false);
    });

    // ── login 拋出例外 ────────────────────────────────────────────────────

    test('login 拋 Exception → error 含「登入失敗:」前綴', () async {
      repo.loginException = Exception('Network error');
      final provider = await createAndWait();

      final result = await provider.login('user', 'pass');

      expect(result, false);
      expect(provider.error, startsWith('登入失敗:'));
      expect(provider.isAuthenticated, false);
    });

    test('login 拋例外後 isLoading 回到 false', () async {
      repo.loginException = Exception('timeout');
      final provider = await createAndWait();
      await provider.login('u', 'p');
      expect(provider.isLoading, false);
    });

    // ── logout ────────────────────────────────────────────────────────────

    test('logout → currentUser 為 null', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      await provider.logout();
      expect(provider.currentUser, isNull);
      expect(provider.isAuthenticated, false);
    });

    test('logout → 呼叫了 repository.logout', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      await provider.logout();
      expect(repo.logoutCalled, true);
    });

    test('logout 後 isLoading 回到 false', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      await provider.logout();
      expect(provider.isLoading, false);
    });

    test('logout 後 isRestoring 為 false', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      await provider.logout();
      expect(provider.isRestoring, false);
    });

    // ── refreshCurrentUser ────────────────────────────────────────────────

    test('refreshCurrentUser：id 相符時更新 currentUser', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      final updatedAlpha = _userAlpha.copyWith(name: 'Alpha Updated');
      provider.refreshCurrentUser(updatedAlpha);
      expect(provider.currentUser?.name, 'Alpha Updated');
    });

    test('refreshCurrentUser：id 不符時 currentUser 不變', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      provider.refreshCurrentUser(_userBeta);
      // _userBeta.id != _userAlpha.id，不應更新
      expect(provider.currentUser, _userAlpha);
    });

    test('refreshCurrentUser：currentUser 為 null 時呼叫不崩潰', () async {
      final provider = await createAndWait(); // currentUser = null
      expect(() => provider.refreshCurrentUser(_userAlpha), returnsNormally);
      expect(provider.currentUser, isNull);
    });

    // ── isAdmin ───────────────────────────────────────────────────────────

    test('isAdmin：user role 為 admin 時回傳 true', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      expect(provider.isAdmin, true);
    });

    test('isAdmin：user role 非 admin 時回傳 false', () async {
      final provider = await createAndWait(currentUser: _userBeta);
      expect(provider.isAdmin, false);
    });

    test('isAdmin：未登入時回傳 false', () async {
      final provider = await createAndWait();
      expect(provider.isAdmin, false);
    });
  });
}
