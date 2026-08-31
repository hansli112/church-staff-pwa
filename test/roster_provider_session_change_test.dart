import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';

// ── Fake RosterRepository（記錄呼叫次數）──────────────────────────────────

class _TrackingRosterRepository implements RosterRepository {
  int fetchRostersCallCount = 0;
  int fetchTemplatesCallCount = 0;
  int fetchEventOptionsCallCount = 0;

  List<ServiceRoster> rostersToReturn;

  _TrackingRosterRepository({List<ServiceRoster>? rostersToReturn})
    : rostersToReturn = rostersToReturn ?? [];

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async {
    fetchRostersCallCount++;
    return List<ServiceRoster>.from(rostersToReturn);
  }

  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async => const []; // cache miss（stub 預設空）

  @override
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes) async {} // stub：no-op

  @override
  Future<void> updateRoster(ServiceRoster roster) async {}

  @override
  Future<void> updateRostersAtomically(List<ServiceRoster> rosters) async {
    for (final roster in rosters) {
      await updateRoster(roster);
    }
  }

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async {
    fetchTemplatesCallCount++;
    return {
      ServiceType.sundayService: const [],
      ServiceType.youth: const [],
      ServiceType.children: const [],
    };
  }

  @override
  Future<void> updateServiceTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {}

  @override
  Future<Map<ServiceType, List<EventOption>>> getEventOptions() async {
    fetchEventOptionsCallCount++;
    return {
      ServiceType.sundayService: const [],
      ServiceType.youth: const [],
      ServiceType.children: const [],
    };
  }

  @override
  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options,
  ) async {}

  /// 重置計數器（方便在同一 provider 上測多次呼叫）
  void resetCounts() {
    fetchRostersCallCount = 0;
    fetchTemplatesCallCount = 0;
    fetchEventOptionsCallCount = 0;
  }
}

// ── 輔助：等待 provider 的非同步 fetch 跑完 ──────────────────────────────────

Future<void> _drainAsync() async {
  // 給 Future.wait + microtask 至少一個 event loop 完成
  await Future.delayed(Duration.zero);
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('RosterProvider.onSessionChanged', () {
    late _TrackingRosterRepository repo;
    late RosterProvider provider;

    setUp(() {
      repo = _TrackingRosterRepository();
      provider = RosterProvider(repo);
    });

    test('初始呼叫 onSessionChanged(userId) → fetchInitialData 被觸發', () async {
      provider.onSessionChanged('user-A');
      await _drainAsync();

      expect(repo.fetchRostersCallCount, greaterThanOrEqualTo(1));
      expect(repo.fetchTemplatesCallCount, greaterThanOrEqualTo(1));
      expect(repo.fetchEventOptionsCallCount, greaterThanOrEqualTo(1));
    });

    test('相同 userId 重複呼叫 onSessionChanged → fetch 不重複觸發', () async {
      provider.onSessionChanged('user-A');
      await _drainAsync();
      repo.resetCounts();

      // 同一個 userId 再呼叫一次
      provider.onSessionChanged('user-A');
      await _drainAsync();

      expect(repo.fetchRostersCallCount, 0);
      expect(repo.fetchTemplatesCallCount, 0);
    });

    test('切換到不同 userId → 重新觸發 fetch', () async {
      provider.onSessionChanged('user-A');
      await _drainAsync();
      repo.resetCounts();

      provider.onSessionChanged('user-B');
      await _drainAsync();

      expect(repo.fetchRostersCallCount, greaterThanOrEqualTo(1));
    });

    test('切換帳號時舊的 rosters 先被同步清空，fetch 完成後回填 user-B 資料', () async {
      // user-A 有一筆資料
      repo.rostersToReturn = [
        ServiceRoster(
          id: 'r1',
          date: DateTime(2026, 3, 1),
          type: ServiceType.sundayService,
          serviceName: '主日崇拜',
          duties: const [],
        ),
      ];
      provider.onSessionChanged('user-A');
      await _drainAsync();
      expect(provider.rosters, isNotEmpty);

      // user-B 有不同的非空資料
      repo.rostersToReturn = [
        ServiceRoster(
          id: 'r2',
          date: DateTime(2026, 3, 8),
          type: ServiceType.youth,
          serviceName: '青年崇拜',
          duties: const [],
        ),
        ServiceRoster(
          id: 'r3',
          date: DateTime(2026, 3, 15),
          type: ServiceType.youth,
          serviceName: '青年崇拜',
          duties: const [],
        ),
      ];

      // 切換帳號後【不 await】，同步確認 cache 已被清空
      provider.onSessionChanged('user-B');
      expect(provider.rosters, isEmpty); // 同步清空，fetch 尚未完成

      // 等待 fetch 完成後，應回填 user-B 的 2 筆資料
      await _drainAsync();
      expect(provider.rosters, hasLength(2));
    });

    test('onSessionChanged(null)（登出）→ cache 清空、不觸發 fetch', () async {
      provider.onSessionChanged('user-A');
      await _drainAsync();
      repo.resetCounts();

      provider.onSessionChanged(null);
      await _drainAsync();

      expect(repo.fetchRostersCallCount, 0);
      expect(provider.rosters, isEmpty);
      expect(provider.templates, isEmpty);
    });

    test('登出後 error 被清空', () async {
      provider.onSessionChanged('user-A');
      await _drainAsync();

      provider.onSessionChanged(null);

      expect(provider.error, isNull);
    });

    test('登出後 isEditMode 被重置為 false', () async {
      provider.onSessionChanged('user-A');
      await _drainAsync();
      provider.toggleEditMode();
      expect(provider.isEditMode, true);

      provider.onSessionChanged(null);

      expect(provider.isEditMode, false);
    });

    test('切換帳號後 isEditMode 被重置為 false', () async {
      provider.onSessionChanged('user-A');
      await _drainAsync();
      provider.toggleEditMode();
      expect(provider.isEditMode, true);

      provider.onSessionChanged('user-B');
      await _drainAsync();

      expect(provider.isEditMode, false);
    });

    test('onSessionChanged(null) 後再登入（新 userId）→ 再次觸發 fetch', () async {
      provider.onSessionChanged('user-A');
      await _drainAsync();

      provider.onSessionChanged(null);
      await _drainAsync();
      repo.resetCounts();

      provider.onSessionChanged('user-A');
      await _drainAsync();

      // null -> user-A 視為 userId 改變，應重新 fetch
      expect(repo.fetchRostersCallCount, greaterThanOrEqualTo(1));
    });
  });
}
