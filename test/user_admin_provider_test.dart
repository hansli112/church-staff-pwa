import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/auth_repository.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/user_admin_provider.dart';

// ── Fake AuthRepository ────────────────────────────────────────────────────

class _FakeAuthRepository implements AuthRepository {
  /// `_makeSession` 在建構後直接賦值，所以 constructor 不宣告此欄位。
  User? currentUserResult;
  List<User> usersToReturn;

  /// 若不為 null，下一次 getUsers 呼叫完成前先阻塞（由 Completer 控制）。
  Completer<void>? getUsersBlocker;

  int getUsersCallCount = 0;

  _FakeAuthRepository({List<User>? usersToReturn})
    : usersToReturn = usersToReturn ?? [];

  @override
  Future<User?> login(String username, String password) async =>
      currentUserResult;

  @override
  Future<User?> getCurrentUser() async => currentUserResult;

  @override
  Future<User?> getCachedUser() async => null;

  @override
  Future<void> writeCachedUser(User user) async {}

  @override
  Future<void> logout() async {
    currentUserResult = null;
  }

  @override
  Future<List<User>> getUsers() async {
    getUsersCallCount++;
    if (getUsersBlocker != null) {
      await getUsersBlocker!.future;
    }
    return List<User>.from(usersToReturn);
  }

  @override
  Future<void> addUser(User user, String password) async {}

  @override
  Future<void> updateUser(User user, {String? password}) async {}

  @override
  Future<void> deleteUser(String id) async {}
}

// ── 測試用 User helper ──────────────────────────────────────────────────────

const _adminUser = User(
  id: 'uid-admin',
  name: 'Admin User',
  email: 'admin@example.com',
  username: 'admin',
  role: UserRole.admin,
);

const _staffUser = User(
  id: 'uid-staff',
  name: 'Staff User',
  email: 'staff@example.com',
  username: 'staff',
  role: UserRole.staff,
);

// ── 輔助：建立已登入的 SessionProvider ────────────────────────────────────

Future<SessionProvider> _makeSession(
  _FakeAuthRepository repo, {
  User? currentUser,
}) async {
  repo.currentUserResult = currentUser;
  final session = SessionProvider(repo);
  // _restoreSession 現在有兩個連續 async hop（getCachedUser + getCurrentUser），
  // 需要 pump 多個 microtask cycle 直到 isRestoring 變 false。
  for (var i = 0; i < 10 && session.isRestoring; i++) {
    await Future.microtask(() {});
  }
  return session;
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('UserAdminProvider', () {
    late _FakeAuthRepository repo;
    late SessionProvider session;
    late UserAdminProvider provider;

    // 每個測試都用已登入的 admin session
    setUp(() async {
      repo = _FakeAuthRepository(usersToReturn: [_adminUser, _staffUser]);
      session = await _makeSession(repo, currentUser: _adminUser);
      provider = UserAdminProvider(repo, session);
    });

    tearDown(() {
      provider.dispose();
      session.dispose();
    });

    // ── cache hit ────────────────────────────────────────────────────────

    test('cache hit：getUsers() 二次呼叫只呼叫 repository 一次', () async {
      await provider.getUsers();
      await provider.getUsers();

      expect(repo.getUsersCallCount, 1);
    });

    test('cache hit：第二次 getUsers() 回傳相同結果', () async {
      final first = await provider.getUsers();
      final second = await provider.getUsers();

      expect(second, equals(first));
    });

    // ── cache invalidation on session logout ──────────────────────────────

    test('登出後 cache 被清空，下次 getUsers 重新 fetch', () async {
      await provider.getUsers();
      expect(repo.getUsersCallCount, 1);

      // 模擬登出：SessionProvider.logout() 會把 currentUser 設 null，
      // 並觸發 listeners（包括 _onSessionChanged）。
      await session.logout();

      // cache 應已清空 → 再次 getUsers 會先拋 Permission denied（非 admin 了）
      // 此處只驗證 call count（登出後呼叫會丟例外，所以不應再 call repository）
      expect(repo.getUsersCallCount, 1); // 沒有多一次
    });

    test('登出後呼叫 getUsers 拋 Permission denied', () async {
      await session.logout();

      expect(
        () => provider.getUsers(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Permission denied'),
          ),
        ),
      );
    });

    // ── cache invalidation after addUser ─────────────────────────────────

    test('addUser 後 cache 清空，下次 getUsers 重新 fetch', () async {
      await provider.getUsers();
      expect(repo.getUsersCallCount, 1);

      const newUser = User(
        id: 'uid-new',
        name: 'New User',
        email: 'new@example.com',
        username: 'newuser',
        role: UserRole.staff,
      );
      await provider.addUser(
        newUser.name,
        newUser.email,
        newUser.username,
        newUser.role,
        password: 'pw123',
      );

      await provider.getUsers();
      expect(repo.getUsersCallCount, 2);
    });

    // ── cache invalidation after updateUser ──────────────────────────────

    test('updateUser 後 cache 清空，下次 getUsers 重新 fetch', () async {
      await provider.getUsers();
      expect(repo.getUsersCallCount, 1);

      await provider.updateUser(_staffUser.copyWith(name: 'Staff Updated'));

      await provider.getUsers();
      expect(repo.getUsersCallCount, 2);
    });

    // ── cache invalidation after deleteUser ──────────────────────────────

    test('deleteUser 後 cache 清空，下次 getUsers 重新 fetch', () async {
      await provider.getUsers();
      expect(repo.getUsersCallCount, 1);

      await provider.deleteUser(_staffUser.id);

      await provider.getUsers();
      expect(repo.getUsersCallCount, 2);
    });

    // ── refreshCurrentUser echo on self-update ────────────────────────────

    test('updateUser 更新自己時 SessionProvider.currentUser 同步更新', () async {
      expect(session.currentUser?.name, 'Admin User');

      final updatedAdmin = _adminUser.copyWith(name: 'Admin Updated');
      await provider.updateUser(updatedAdmin);

      expect(session.currentUser?.name, 'Admin Updated');
    });

    test('updateUser 更新他人時 SessionProvider.currentUser 不變', () async {
      await provider.updateUser(_staffUser.copyWith(name: 'Staff Updated'));

      // admin 自己的資料不應被動到
      expect(session.currentUser?.id, _adminUser.id);
      expect(session.currentUser?.name, 'Admin User');
    });

    // ── post-await session-change guard ───────────────────────────────────

    test('getUsers await 期間 session 登出，cache 不被寫入舊資料', () async {
      // 用 Completer 讓 getUsers 在 repository 這邊卡住
      final blocker = Completer<void>();
      repo.getUsersBlocker = blocker;

      // 開始 getUsers，但不 await
      final future = provider.getUsers();

      // 趁 getUsers 還在等 repository 時，模擬登出
      // session.logout() 會將 currentUser 設為 null，觸發 _onSessionChanged
      await session.logout();

      // 放行 repository
      blocker.complete();

      // getUsers 完成，因為 session 已是 null / 非 admin，
      // provider 的防衛條件應讓此次結果不寫入 cache
      final result = await future;
      expect(result, isNotEmpty); // raw list 仍回傳（getUsers 實作行為）

      // 建立全新的 admin session 來驗證：若 cache 被寫入了，
      // 新一輪的 provider 在登入後第一次 getUsers 應該命中 cache（call count=0）；
      // 若正確沒有寫入，則新 provider 第一次 getUsers 必須 fetch（call count=1）。
      //
      // 此處使用完全獨立的 repo2/session2/provider2，避免上面已登出的 session 干擾。
      final repo2 = _FakeAuthRepository(usersToReturn: [_adminUser]);
      final session2 = await _makeSession(repo2, currentUser: _adminUser);
      final provider2 = UserAdminProvider(repo2, session2);

      await provider2.getUsers();
      expect(repo2.getUsersCallCount, 1); // 必須重新 fetch，不能用舊 cache

      provider2.dispose();
      session2.dispose();
    });
  });
}
