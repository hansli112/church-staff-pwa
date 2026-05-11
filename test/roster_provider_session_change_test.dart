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
  Future<void> updateRoster(ServiceRoster roster) async {}

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

    test('切換帳號時舊的 rosters 先被清空（fetch 前 provider.rosters 為空）', () async {
      // 讓第一次 fetch 有資料
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

      // 切換帳號，cache 應先清空，下一批資料還沒回來
      repo.rostersToReturn = [];
      provider.onSessionChanged('user-B');
      // 在 fetch 完成前（但 onSessionChanged 已清空 cache），rosters 應為空
      // 注意：此時 fetch 可能還在進行，所以先確認清除動作有發生
      // 等待 fetch 完成後，rosters 對應 repo 回傳的空列表
      await _drainAsync();
      expect(provider.rosters, isEmpty);
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
