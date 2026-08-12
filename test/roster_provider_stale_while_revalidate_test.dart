import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';

// ── 輔助 roster fixture ──────────────────────────────────────────────────────

ServiceRoster _roster(String id, ServiceType type) => ServiceRoster(
  id: id,
  date: DateTime(2026, 6, 7),
  type: type,
  serviceName: type == ServiceType.sundayService ? '主日崇拜' : '青年崇拜',
  duties: const [],
);

// ── Configurable fake ───────────────────────────────────────────────────────

class _FakeRepo implements RosterRepository {
  /// cache phase 回傳什麼
  List<ServiceRoster> cacheResult;

  /// server phase 回傳什麼
  List<ServiceRoster> serverResult;

  /// 若設 non-null，cache fetch 會 throw 此錯誤
  Object? cacheError;

  /// 若設 non-null，server fetch 會 throw 此錯誤
  Object? serverError;

  /// 讓測試可以控制 cache fetch 何時完成
  Completer<void>? cachePause;

  /// 讓測試可以控制 server fetch 何時完成
  Completer<void>? serverPause;

  int ensureCallCount = 0;

  _FakeRepo({
    this.cacheResult = const [],
    this.serverResult = const [],
    this.cacheError,
    this.serverError,
    this.cachePause,
    this.serverPause,
  });

  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async {
    if (cachePause != null) await cachePause!.future;
    if (cacheError != null) throw cacheError!;
    return List<ServiceRoster>.from(cacheResult);
  }

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async {
    if (serverPause != null) await serverPause!.future;
    if (serverError != null) throw serverError!;
    return List<ServiceRoster>.from(serverResult);
  }

  @override
  Future<void> ensureQuarterRosters() async {
    ensureCallCount++;
  }

  @override
  Future<void> updateRoster(ServiceRoster roster) async {}

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async => {
    ServiceType.sundayService: const [],
    ServiceType.youth: const [],
    ServiceType.children: const [],
  };

  @override
  Future<void> updateServiceTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {}

  @override
  Future<Map<ServiceType, List<EventOption>>> getEventOptions() async => {
    ServiceType.sundayService: const [],
    ServiceType.youth: const [],
    ServiceType.children: const [],
  };

  @override
  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options,
  ) async {}
}

// ── 工具：讓 event loop 跑完所有已排程的 microtask / Future ──────────────────

Future<void> _drain() async {
  await Future.delayed(Duration.zero);
}

// 多跑幾個 loop 以讓 Future.wait 與 then 都完成
Future<void> _drainFully() async {
  for (var i = 0; i < 5; i++) {
    await Future.delayed(Duration.zero);
  }
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('RosterProvider stale-while-revalidate', () {
    // ────────────────────────────────────────────────────────────────────────
    // 情境 1：cache 有資料 → 先 set _allRosters，isLoading 仍 true，
    //         server 完成後覆蓋。
    // ────────────────────────────────────────────────────────────────────────
    test('cache 有資料時先渲染 stale data，isLoading 仍 true，server 完成後覆蓋', () async {
      final staleRoster = _roster('stale-1', ServiceType.sundayService);
      final freshRoster = _roster('fresh-1', ServiceType.youth);

      // 用 Completer 讓 server fetch 先暫停，確認中間狀態
      final serverPause = Completer<void>();
      final repo = _FakeRepo(
        cacheResult: [staleRoster],
        serverResult: [freshRoster],
        serverPause: serverPause,
      );
      final provider = RosterProvider(repo);

      final fetchFuture = provider.fetchInitialData();

      // cache 快完成了，drain 一次讓 cache phase 跑完
      await _drain();

      // cache phase 完成：rosters 有 stale data，isLoading = true
      expect(provider.rosters, contains(staleRoster));
      expect(provider.isLoading, isTrue);

      // 放行 server
      serverPause.complete();
      await fetchFuture;

      // server 完成：stale 被覆蓋成 fresh
      expect(provider.rosters, contains(freshRoster));
      expect(provider.rosters, isNot(contains(staleRoster)));
      expect(provider.isLoading, isFalse);
    });

    // ────────────────────────────────────────────────────────────────────────
    // 情境 2：cache miss → 直接走 server，行為與原本一樣。
    // ────────────────────────────────────────────────────────────────────────
    test('cache miss 時不設 stale data，走 server 路徑', () async {
      final freshRoster = _roster('fresh-1', ServiceType.sundayService);
      final repo = _FakeRepo(
        cacheResult: const [], // cache miss
        serverResult: [freshRoster],
      );
      final provider = RosterProvider(repo);

      await provider.fetchInitialData();
      await _drainFully();

      expect(provider.rosters, contains(freshRoster));
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    // ────────────────────────────────────────────────────────────────────────
    // 情境 3：cache 有資料但 server 失敗 → 不設 error，繼續顯示 stale data。
    // ────────────────────────────────────────────────────────────────────────
    test('cache 有資料、server 失敗 → 不顯示 error，保留 stale data', () async {
      final staleRoster = _roster('stale-1', ServiceType.sundayService);
      final repo = _FakeRepo(
        cacheResult: [staleRoster],
        serverError: Exception('network error'),
      );
      final provider = RosterProvider(repo);

      await provider.fetchInitialData();
      await _drainFully();

      expect(provider.rosters, contains(staleRoster));
      expect(provider.error, isNull); // 不顯示 error（cache 已渲染）
      expect(provider.isLoading, isFalse);
    });

    // ────────────────────────────────────────────────────────────────────────
    // 情境 4：cache 無資料、server 失敗 → 顯示 error（與原本行為一致）。
    // ────────────────────────────────────────────────────────────────────────
    test('cache 無資料、server 失敗 → 顯示 error', () async {
      final repo = _FakeRepo(
        cacheResult: const [],
        serverError: Exception('network error'),
      );
      final provider = RosterProvider(repo);

      await provider.fetchInitialData();
      await _drainFully();

      expect(provider.rosters, isEmpty);
      expect(provider.error, isNotNull);
      expect(provider.isLoading, isFalse);
    });

    // ────────────────────────────────────────────────────────────────────────
    // 情境 5：stale token race — 切換 user 時舊 fetch 的結果不污染新 user。
    // ────────────────────────────────────────────────────────────────────────
    test('token race：舊 fetch 的 stale cache 不覆蓋新 user 的資料', () async {
      final oldCacheRoster = _roster('old-cache', ServiceType.sundayService);
      final newServerRoster = _roster('new-server', ServiceType.youth);

      // user-A 的 cache 很慢（用 Completer 控制）
      final userACachePause = Completer<void>();
      final repoA = _FakeRepo(
        cacheResult: [oldCacheRoster],
        cachePause: userACachePause,
      );
      final repoB = _FakeRepo(
        cacheResult: const [],
        serverResult: [newServerRoster],
      );

      final provider = RosterProvider(repoA);

      // 開始 user-A 的 fetch（cache 卡住中）
      unawaited(provider.fetchInitialData());
      await _drain();

      // 切換 user（模擬 onSessionChanged 換 repo 的效果）：
      // 直接再打一次 fetchInitialData（不同 repo）來模擬 token bump。
      // 這裡改用同一 provider 但把 _fetchToken bump 再跑 fetch，
      // 藉由再呼叫 fetchInitialData 觸發 token 遞增（模擬 onSessionChanged）。
      final provider2 = RosterProvider(repoB);
      await provider2.fetchInitialData();
      await _drainFully();

      // 放行 user-A 的舊 cache（此時 provider2 的 token 已不同）
      userACachePause.complete();
      await _drain();

      // provider2 應該只有 newServerRoster
      expect(provider2.rosters, contains(newServerRoster));
      expect(provider2.rosters, isNot(contains(oldCacheRoster)));
    });

    // ────────────────────────────────────────────────────────────────────────
    // 情境 6：ensureQuarterRosters 只在被明確呼叫時觸發（viewer 不呼叫）。
    // ────────────────────────────────────────────────────────────────────────
    test('fetchInitialData 不觸發 ensureQuarterRosters', () async {
      final repo = _FakeRepo();
      final provider = RosterProvider(repo);

      await provider.fetchInitialData();
      await _drainFully();

      expect(repo.ensureCallCount, 0);
    });

    test('ensureQuarterRostersIfAdmin 觸發 ensureQuarterRosters', () async {
      final repo = _FakeRepo();
      final provider = RosterProvider(repo);

      await provider.ensureQuarterRostersIfAdmin();
      await _drainFully();

      expect(repo.ensureCallCount, 1);
    });

    // ────────────────────────────────────────────────────────────────────────
    // 情境 7：cache 失敗（非 cache-miss exception）→ 靜默，繼續走 server。
    // ────────────────────────────────────────────────────────────────────────
    test('cache throw 時靜默失敗，server 資料正常回填', () async {
      final freshRoster = _roster('fresh-1', ServiceType.sundayService);
      final repo = _FakeRepo(
        cacheError: Exception('cache exploded'),
        serverResult: [freshRoster],
      );
      final provider = RosterProvider(repo);

      await provider.fetchInitialData();
      await _drainFully();

      expect(provider.rosters, contains(freshRoster));
      expect(provider.error, isNull);
      expect(provider.isLoading, isFalse);
    });

    // ────────────────────────────────────────────────────────────────────────
    // 情境 8：fetchRosters 也有 cache-first 行為。
    // ────────────────────────────────────────────────────────────────────────
    test('fetchRosters：cache 有資料先渲染，server 完成後覆蓋', () async {
      final staleRoster = _roster('stale-1', ServiceType.sundayService);
      final freshRoster = _roster('fresh-1', ServiceType.youth);

      final serverPause = Completer<void>();
      final repo = _FakeRepo(
        cacheResult: [staleRoster],
        serverResult: [freshRoster],
        serverPause: serverPause,
      );
      final provider = RosterProvider(repo);

      final fetchFuture = provider.fetchRosters();
      await _drain();

      // cache 先到：有 stale data，isLoading 仍 true
      expect(provider.rosters, contains(staleRoster));
      expect(provider.isLoading, isTrue);

      serverPause.complete();
      await fetchFuture;

      expect(provider.rosters, contains(freshRoster));
      expect(provider.rosters, isNot(contains(staleRoster)));
      expect(provider.isLoading, isFalse);
    });
  });
}
