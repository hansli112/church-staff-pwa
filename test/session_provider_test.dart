import 'dart:async';

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

  /// 若不為 null，`getCurrentUser` 會 throw 此例外。
  Object? getCurrentUserException;

  /// `getCachedUser` 回傳值（模擬快取 user）。
  User? cachedUserResult;

  /// 若 true，`getCurrentUser` 會永不完成（用於測試 optimistic path）。
  bool getCurrentUserBlocks = false;

  bool logoutCalled = false;

  /// 若不為 null，`logout` 會 throw 此例外。
  Object? logoutException;

  /// Records every user passed to [writeCachedUser] in call order.
  final List<User> writeCachedUserCalls = [];

  /// When non-null, [getCurrentUser] waits for this completer before
  /// returning [currentUserResult].  Allows tests to control exactly when the
  /// background fetch resolves.
  Completer<void>? getCurrentUserCompleter;

  @override
  Future<User?> login(String username, String password) async {
    if (loginException != null) throw loginException!;
    return loginResult;
  }

  @override
  Future<User?> getCurrentUser() async {
    if (getCurrentUserBlocks) {
      // Never completes — simulates a slow/hanging network call.
      await Completer<void>().future;
    }
    if (getCurrentUserCompleter != null) {
      await getCurrentUserCompleter!.future;
    }
    if (getCurrentUserException != null) throw getCurrentUserException!;
    return currentUserResult;
  }

  @override
  Future<User?> getCachedUser() async => cachedUserResult;

  @override
  Future<void> writeCachedUser(User user) async {
    writeCachedUserCalls.add(user);
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
    if (logoutException != null) throw logoutException!;
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

// 只被授予行事曆 group 的一般同工：權限跟 role 沒有關係，這是整個模型的重點。
const _userCalendarEditor = User(
  id: 'uid-cal',
  name: 'Calendar Editor',
  email: 'cal@example.com',
  username: 'cal',
  role: UserRole.staff,
  groups: {UserGroup.calendarEditors},
);

// 反過來的例子：身分是小組長，但沒有被授予任何 group。
const _userPlainLeader = User(
  id: 'uid-leader',
  name: 'Leader User',
  email: 'leader@example.com',
  username: 'leader',
  role: UserRole.leader,
);

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('SessionProvider', () {
    late _FakeAuthRepository repo;

    setUp(() {
      repo = _FakeAuthRepository();
    });

    // 等 _restoreSession Phase 1 完成（isRestoring 變 false）的輔助方法。
    //
    // 無 cache 路徑需要兩個連續 async hop（getCachedUser + getCurrentUser），
    // 所以等多個 microtask cycle 直到 isRestoring 變 false。
    Future<SessionProvider> createAndWait({User? currentUser}) async {
      repo.currentUserResult = currentUser;
      final provider = SessionProvider(repo);
      // pump microtasks until isRestoring is false (up to a reasonable limit)
      for (var i = 0; i < 10 && provider.isRestoring; i++) {
        await Future.microtask(() {});
      }
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

    test(
      'login 成功 → isAuthenticated true、currentUser 不為 null、error 為 null',
      () async {
        repo.loginResult = _userAlpha;
        final provider = await createAndWait();

        final result = await provider.login('alpha', 'password123');

        expect(result, true);
        expect(provider.isAuthenticated, true);
        expect(provider.currentUser, _userAlpha);
        expect(provider.error, isNull);
      },
    );

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

    test('logout 失敗時保留登入狀態並回報錯誤，且不卡在 isLoading', () async {
      // 登出失敗卻清掉 currentUser 的話，App 會跳回登入畫面、使用者以為已經
      // 登出，但 Firebase Auth session 還活著 —— 共用裝置上下一個人重開就直接
      // 進到前一個人的帳號。所以失敗時必須維持登入狀態。
      final provider = await createAndWait(currentUser: _userAlpha);
      repo.logoutException = Exception('signOut failed');

      await provider.logout();

      expect(provider.currentUser, isNotNull);
      expect(provider.isAuthenticated, true);
      expect(provider.isLoading, false);
      expect(provider.error, isNotNull);
    });

    test('clearError 清掉登出失敗留下的錯誤，避免殘留到登入畫面', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      repo.logoutException = Exception('signOut failed');
      await provider.logout();
      expect(provider.error, isNotNull);

      provider.clearError();

      expect(provider.error, isNull);
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

    // ── 編輯權限（group）────────────────────────────────────────────────
    //
    // 這組測試釘的是「權限不看 role」：小組長沒有 group 就不能編，同工有
    // group 就能編。把 canEditCalendar 寫回 role 判斷會整組變紅。

    test('admin 隱含所有 group', () async {
      final provider = await createAndWait(currentUser: _userAlpha);
      expect(provider.canEditRoster, true);
      expect(provider.canEditCalendar, true);
    });

    test('被授予行事曆 group 的同工可以編行事曆，但不能編服事表', () async {
      final provider = await createAndWait(currentUser: _userCalendarEditor);
      expect(provider.canEditCalendar, true);
      expect(provider.canEditRoster, false);
      expect(provider.isAdmin, false);
    });

    test('身分是小組長但沒有任何 group：兩項都不能編', () async {
      final provider = await createAndWait(currentUser: _userPlainLeader);
      expect(provider.canEditCalendar, false);
      expect(provider.canEditRoster, false);
    });

    test('未登入時兩項都是 false', () async {
      final provider = await createAndWait();
      expect(provider.canEditCalendar, false);
      expect(provider.canEditRoster, false);
    });

    // ── Level 2: getCachedUser optimistic path ─────────────────────────────

    test('cache 有資料 → isRestoring 立刻變 false，currentUser 為 cached user'
        '（即使 getCurrentUser 永不完成）', () async {
      // Arrange: cache 有 alpha；getCurrentUser 永遠卡住不回來
      repo.cachedUserResult = _userAlpha;
      repo.getCurrentUserBlocks = true;

      final provider = SessionProvider(repo);

      // Phase 1 只需要 getCachedUser() 的 async hop（trivial），
      // pump 直到 isRestoring 變 false（Phase 2 永不完成，不會干擾）。
      for (var i = 0; i < 10 && provider.isRestoring; i++) {
        await Future.microtask(() {});
      }

      // Phase 1 應已完成：isRestoring = false，currentUser = cached
      expect(provider.isRestoring, false);
      expect(provider.currentUser, _userAlpha);
    });

    // 等背景 Phase 2 完成的輔助：pump microtask 直到 currentUser 更新或達上限。
    Future<void> pumpUntilPhase2Done(
      SessionProvider provider,
      User? expected,
    ) async {
      for (var i = 0; i < 10; i++) {
        await Future.microtask(() {});
        if (provider.currentUser == expected) break;
      }
    }

    test('背景 fetch 成功（同 id）→ currentUser 更新為 fresh user', () async {
      // Arrange: cache 有 alpha；background getCurrentUser 也回傳 alpha（可有欄位更新）
      final freshAlpha = _userAlpha.copyWith(name: 'Alpha Fresh');
      repo.cachedUserResult = _userAlpha;
      repo.currentUserResult = freshAlpha;

      final provider = SessionProvider(repo);

      // 等 Phase 1（cache read）完成
      for (var i = 0; i < 10 && provider.isRestoring; i++) {
        await Future.microtask(() {});
      }
      expect(provider.currentUser, _userAlpha); // 先是 cached

      // 等 Phase 2（background getCurrentUser）完成
      await pumpUntilPhase2Done(provider, freshAlpha);

      expect(provider.currentUser, freshAlpha);
    });

    test('背景 fetch 回 null → currentUser 變 null（session 失效）', () async {
      // Arrange: cache 有 alpha；background fetch 回 null（帳號被刪）
      repo.cachedUserResult = _userAlpha;
      repo.currentUserResult = null;

      final provider = SessionProvider(repo);

      // Phase 1
      for (var i = 0; i < 10 && provider.isRestoring; i++) {
        await Future.microtask(() {});
      }
      expect(provider.currentUser, _userAlpha);

      // Phase 2
      await pumpUntilPhase2Done(provider, null);

      expect(provider.currentUser, isNull);
      expect(provider.isAuthenticated, false);
    });

    test('背景 fetch throw → 保留 cached user，不爆 error、不登出', () async {
      // Arrange: cache 有 alpha；background fetch 拋例外（例如網路斷線）
      repo.cachedUserResult = _userAlpha;
      repo.getCurrentUserException = Exception('network error');

      final provider = SessionProvider(repo);

      // Phase 1
      for (var i = 0; i < 10 && provider.isRestoring; i++) {
        await Future.microtask(() {});
      }
      expect(provider.currentUser, _userAlpha);

      // Phase 2 (background throws, should be swallowed)
      // pump a few microtasks to let the background Future run and throw
      for (var i = 0; i < 5; i++) {
        await Future.microtask(() {});
      }

      // Cached user must still be present; error field must be null
      expect(provider.currentUser, _userAlpha);
      expect(provider.error, isNull);
      expect(provider.isAuthenticated, true);
    });

    // ── user-switch race (#1 / #4) ────────────────────────────────────────

    test(
      '背景 fetch 進行中 logout → late-arriving fresh 不覆蓋 null（expectedId guard）',
      () async {
        // Arrange: cache 有 alpha；background fetch 用 Completer 卡住。
        final completer = Completer<void>();
        repo.cachedUserResult = _userAlpha;
        repo.getCurrentUserCompleter = completer;
        // fresh result that will eventually come back — should be discarded
        repo.currentUserResult = _userAlpha.copyWith(name: 'Alpha Stale Fresh');

        final provider = SessionProvider(repo);

        // Phase 1 完成
        for (var i = 0; i < 10 && provider.isRestoring; i++) {
          await Future.microtask(() {});
        }
        expect(provider.currentUser, _userAlpha);

        // 使用者在 background fetch 完成前登出
        await provider.logout();
        expect(provider.currentUser, isNull);

        // 放行 background fetch（late-arriving）
        completer.complete();
        // pump 讓背景 Future 執行完畢
        for (var i = 0; i < 10; i++) {
          await Future.microtask(() {});
        }

        // late-arriving fetch 不應把 currentUser 從 null 改回 alpha
        expect(provider.currentUser, isNull);
        expect(provider.isAuthenticated, false);
      },
    );

    test('背景 fetch 進行中切換帳號（login B）→ late-arriving A fresh 不覆蓋 B', () async {
      // Arrange: cache 有 alpha；background fetch 用 Completer 卡住。
      final completer = Completer<void>();
      repo.cachedUserResult = _userAlpha;
      repo.getCurrentUserCompleter = completer;
      repo.currentUserResult = _userAlpha.copyWith(name: 'Alpha Stale Fresh');

      final provider = SessionProvider(repo);

      // Phase 1 完成
      for (var i = 0; i < 10 && provider.isRestoring; i++) {
        await Future.microtask(() {});
      }
      expect(provider.currentUser, _userAlpha);

      // 帳號切換：先登出，再登入 beta
      await provider.logout();
      // 停止卡住後的 getCurrentUser 直接回傳（不再卡）
      repo.getCurrentUserCompleter = null;
      repo.loginResult = _userBeta;
      await provider.login('beta', 'pass');
      expect(provider.currentUser, _userBeta);

      // 放行原本卡住的 alpha background fetch
      completer.complete();
      for (var i = 0; i < 10; i++) {
        await Future.microtask(() {});
      }

      // currentUser 應仍是 beta，不被 alpha stale data 覆蓋
      expect(provider.currentUser, _userBeta);
      expect(provider.currentUser?.id, 'uid-beta');
    });

    test('背景 fetch 進行中切換帳號 → stale A 的 writeCachedUser 不被呼叫', () async {
      // Arrange: cache 有 alpha；background fetch 用 Completer 卡住。
      final completer = Completer<void>();
      repo.cachedUserResult = _userAlpha;
      repo.getCurrentUserCompleter = completer;
      repo.currentUserResult = _userAlpha.copyWith(name: 'Alpha Stale Fresh');

      final provider = SessionProvider(repo);

      // Phase 1 完成
      for (var i = 0; i < 10 && provider.isRestoring; i++) {
        await Future.microtask(() {});
      }

      // 登出，切換到 beta
      await provider.logout();
      repo.getCurrentUserCompleter = null;
      repo.loginResult = _userBeta;
      await provider.login('beta', 'pass');

      // 清除 login 產生的 writeCachedUser 紀錄（login 直接寫 cache 是正確的）
      // 注意：login 走 repository.login → _cachedUserStorage.write 那條，
      // 不走 writeCachedUser，所以 writeCachedUserCalls 此時應仍為空。
      expect(repo.writeCachedUserCalls, isEmpty);

      // 放行 stale alpha fetch
      completer.complete();
      for (var i = 0; i < 10; i++) {
        await Future.microtask(() {});
      }

      // stale alpha 的 writeCachedUser 不應被呼叫（guard 擋住了）
      expect(repo.writeCachedUserCalls, isEmpty);
    });

    test('背景 fetch 正常完成（無切換）→ writeCachedUser 被呼叫一次且帶 fresh user', () async {
      // Arrange: cache 有 alpha；background fetch 正常回傳 freshAlpha
      final freshAlpha = _userAlpha.copyWith(name: 'Alpha Fresh');
      repo.cachedUserResult = _userAlpha;
      repo.currentUserResult = freshAlpha;

      final provider = SessionProvider(repo);

      // Phase 1
      for (var i = 0; i < 10 && provider.isRestoring; i++) {
        await Future.microtask(() {});
      }

      // Phase 2
      await pumpUntilPhase2Done(provider, freshAlpha);

      expect(provider.currentUser, freshAlpha);
      // writeCachedUser 應被呼叫一次，帶 freshAlpha
      expect(repo.writeCachedUserCalls.length, 1);
      expect(repo.writeCachedUserCalls.first, freshAlpha);
    });
  });
}
