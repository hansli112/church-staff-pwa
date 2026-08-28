import 'package:flutter_test/flutter_test.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';

/// RosterProvider 對 getRostersByType / eventColorFor 的結果做了快取。
/// 這組測試守的是「資料變了但快取沒丟」這個 bug — 那會讓畫面顯示舊資料，
/// 而且不會有任何錯誤訊息。
class _FakeRosterRepository implements RosterRepository {
  _FakeRosterRepository({
    required List<ServiceRoster> rosters,
    required Map<ServiceType, List<EventOption>> eventOptions,
  }) : _rosters = List<ServiceRoster>.from(rosters),
       _eventOptions = Map<ServiceType, List<EventOption>>.from(eventOptions);

  final List<ServiceRoster> _rosters;
  Map<ServiceType, List<EventOption>> _eventOptions;

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async =>
      List<ServiceRoster>.from(_rosters);

  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async => const [];

  @override
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes) async {}

  @override
  Future<void> updateRoster(ServiceRoster roster) async {
    final index = _rosters.indexWhere((r) => r.id == roster.id);
    if (index == -1) {
      _rosters.add(roster);
      return;
    }
    _rosters[index] = roster;
  }

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async => {
    ServiceType.sundayService: const ['領會'],
    ServiceType.youth: const ['領會'],
    ServiceType.children: const [],
  };

  @override
  Future<void> updateServiceTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {}

  @override
  Future<Map<ServiceType, List<EventOption>>> getEventOptions() async =>
      Map<ServiceType, List<EventOption>>.from(_eventOptions);

  @override
  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options,
  ) async {
    _eventOptions = Map<ServiceType, List<EventOption>>.from(options);
  }
}

ServiceRoster _roster({
  required String id,
  required ServiceType type,
  List<String> people = const ['A'],
  List<String> events = const [],
}) {
  return ServiceRoster(
    id: id,
    date: DateTime(2026, 2, 1),
    type: type,
    serviceName: '崇拜',
    duties: [RosterEntry(role: '領會', people: people)],
    specialEvents: events,
  );
}

void main() {
  group('RosterProvider 衍生資料快取', () {
    late _FakeRosterRepository repository;
    late RosterProvider provider;

    setUp(() async {
      repository = _FakeRosterRepository(
        rosters: [
          _roster(id: 'sun-1', type: ServiceType.sundayService),
          _roster(id: 'sun-2', type: ServiceType.sundayService),
          _roster(id: 'youth-1', type: ServiceType.youth),
        ],
        eventOptions: {
          ServiceType.sundayService: const [
            EventOption(name: '聖餐主日', color: 0xFFF39C12),
          ],
          ServiceType.youth: const [
            EventOption(name: '青年之夜', color: 0xFF27AE60),
          ],
          ServiceType.children: const [],
        },
      );
      provider = RosterProvider(repository);
      await provider.fetchInitialData();
    });

    test('依 type 分組結果正確', () {
      expect(
        provider
            .getRostersByType(ServiceType.sundayService)
            .map((r) => r.id)
            .toList(),
        ['sun-1', 'sun-2'],
      );
      expect(
        provider.getRostersByType(ServiceType.youth).map((r) => r.id).toList(),
        ['youth-1'],
      );
      expect(provider.getRostersByType(ServiceType.children), isEmpty);
    });

    test('連續呼叫回傳同一個 list instance（沒有每次重算）', () {
      final first = provider.getRostersByType(ServiceType.sundayService);
      final second = provider.getRostersByType(ServiceType.sundayService);
      expect(identical(first, second), isTrue);
    });

    test('updateRoster 後分組快取要失效', () async {
      final target = provider
          .getRostersByType(ServiceType.sundayService)
          .firstWhere((r) => r.id == 'sun-1');

      await provider.updateRoster(
        target.copyWith(
          duties: [
            RosterEntry(role: '領會', people: const ['新的人']),
          ],
        ),
      );

      final refreshed = provider
          .getRostersByType(ServiceType.sundayService)
          .firstWhere((r) => r.id == 'sun-1');
      expect(refreshed.duties.first.people, ['新的人']);
    });

    test('updateRosters 批次更新後分組快取要失效', () async {
      final rosters = provider.getRostersByType(ServiceType.sundayService);
      await provider.updateRosters([
        rosters[0].copyWith(
          duties: [
            RosterEntry(role: '領會', people: const ['甲']),
          ],
        ),
        rosters[1].copyWith(
          duties: [
            RosterEntry(role: '領會', people: const ['乙']),
          ],
        ),
      ]);

      final refreshed = provider.getRostersByType(ServiceType.sundayService);
      expect(refreshed[0].duties.first.people, ['甲']);
      expect(refreshed[1].duties.first.people, ['乙']);
    });

    test('重新 fetch 後分組快取要失效', () async {
      // 先讀一次把快取灌熱 —— 少了這步，測到的只是「從空快取重算」，
      // 就算把 invalidation 整個拿掉測試照樣會過。
      expect(
        provider.getRostersByType(ServiceType.sundayService),
        hasLength(2),
      );

      await repository.updateRoster(
        _roster(id: 'sun-3', type: ServiceType.sundayService),
      );
      await provider.fetchRosters();

      expect(
        provider
            .getRostersByType(ServiceType.sundayService)
            .map((r) => r.id)
            .toList(),
        ['sun-1', 'sun-2', 'sun-3'],
      );
    });

    test('登出後分組快取要清空', () {
      // 先讀一次把快取灌熱，才測得到「清除」而不是「從空快取重算」。
      expect(
        provider.getRostersByType(ServiceType.sundayService),
        hasLength(2),
      );

      // onSessionChanged 以「userId 有沒有變」為判斷依據，所以要先進入一個
      // session，登出才會真的走到清除路徑。
      provider.onSessionChanged('uid-1');
      provider.onSessionChanged(null);
      expect(provider.getRostersByType(ServiceType.sundayService), isEmpty);
    });

    test('updateRoster 後 rosters 的 identity 必須改變', () async {
      // 首頁的「本季服事」用 identical(rosters, 上次的 rosters) 判斷要不要
      // 重算。就地改寫 _allRosters 會讓 identity 不變，首頁就會一直顯示
      // 編輯前的結果 —— 這個測試守的就是那個情況。
      final before = provider.rosters;
      final target = before.firstWhere((r) => r.id == 'sun-1');

      await provider.updateRoster(
        target.copyWith(
          duties: [
            RosterEntry(role: '領會', people: const ['改過的人']),
          ],
        ),
      );

      expect(identical(provider.rosters, before), isFalse);
    });

    test('updateRosters 後 rosters 的 identity 必須改變', () async {
      final before = provider.rosters;

      await provider.updateRosters([
        before.first.copyWith(
          duties: [
            RosterEntry(role: '領會', people: const ['批次改過的人']),
          ],
        ),
      ]);

      expect(identical(provider.rosters, before), isFalse);
    });

    test('displayStrings 收齊姓名/服事項目/事件，並且去重', () {
      final strings = provider.displayStrings;
      for (final expected in ['崇拜', '領會', 'A']) {
        expect(strings, contains(expected));
      }
      // 去重：同一個字串只會出現一次（三筆 roster 的 serviceName 都是「崇拜」）
      expect(strings.toSet().length, strings.length);
    });

    test('displayStrings 連續呼叫回傳同一個 instance', () {
      // MainScaffold 用 context.select 訂閱這個 getter，比較方式是 ==（對
      // List 就是 identity）。每次都回新 list 的話，任何一次 notifyListeners
      // 都會讓 TextWarmup 以為資料換了而整批重新預熱。
      final first = provider.displayStrings;
      final second = provider.displayStrings;
      expect(identical(first, second), isTrue);
    });

    test('登出後 displayStrings 要清空', () {
      // 先讀一次灌熱快取，才測得到「清除」而不是「從空快取重算」。
      expect(provider.displayStrings, isNotEmpty);

      provider.onSessionChanged('uid-1');
      provider.onSessionChanged(null);
      expect(provider.displayStrings, isEmpty);
    });

    test('資料變更後 displayStrings 要跟著失效', () async {
      // 先讀一次灌熱快取，才測得到失效而不是「從空快取重算」。
      expect(provider.displayStrings, isNot(contains('甲')));

      final target = provider.rosters.firstWhere((r) => r.id == 'sun-1');
      await provider.updateRoster(
        target.copyWith(
          duties: [
            RosterEntry(role: '領會', people: const ['甲']),
          ],
        ),
      );

      expect(provider.displayStrings, contains('甲'));
    });

    test('eventColorFor：本 type 優先，其次跨 type，找不到給灰色', () {
      expect(
        provider.eventColorFor(ServiceType.sundayService, '聖餐主日'),
        0xFFF39C12,
      );
      // 主日沒定義「青年之夜」，落到跨 type 查找
      expect(
        provider.eventColorFor(ServiceType.sundayService, '青年之夜'),
        0xFF27AE60,
      );
      expect(
        provider.eventColorFor(ServiceType.sundayService, '不存在的事件'),
        0xFF7F8C8D,
      );
    });

    test('updateEventOptions 後顏色索引要失效', () async {
      // 先查一次把 _eventColorIndex 建起來（含跨 type 查找那條路徑），
      // 否則測到的是「索引本來就是 null」而不是「索引被丟掉」。
      expect(
        provider.eventColorFor(ServiceType.sundayService, '青年之夜'),
        0xFF27AE60,
      );

      await provider.updateEventOptions({
        ServiceType.sundayService: const [
          EventOption(name: '聖餐主日', color: 0xFF3498DB),
        ],
        ServiceType.youth: const [],
        ServiceType.children: const [],
      });

      expect(
        provider.eventColorFor(ServiceType.sundayService, '聖餐主日'),
        0xFF3498DB,
      );
      // 青年之夜已被移除 → 回退到灰色
      expect(
        provider.eventColorFor(ServiceType.sundayService, '青年之夜'),
        0xFF7F8C8D,
      );
    });
  });
}
