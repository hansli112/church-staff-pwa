import 'dart:async';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';

/// 測試共用的 [RosterRepository]：資料放在記憶體裡，讀寫照實做。
///
/// 以前每個測試檔各寫一份私有 fake，九份各自決定「寫入要不要真的存」「失敗
/// 怎麼丟」—— 同一個 provider 行為在不同檔案裡測的其實是不同的假設。要故意
/// 失敗、暫停或計數的，設下面對應的欄位；用不到的測試什麼都不必設。
class InMemoryRosterRepository implements RosterRepository {
  InMemoryRosterRepository({
    List<ServiceRoster> rosters = const [],
    List<ServiceRoster> cachedRosters = const [],
    Map<ServiceType, List<String>> templates = const {},
    Map<ServiceType, List<EventOption>> eventOptions = const {},
  }) : rosters = List.of(rosters),
       cachedRosters = List.of(cachedRosters),
       templates = Map.of(templates),
       eventOptions = Map.of(eventOptions);

  /// 伺服器上的服事表。寫入會改到這裡。
  List<ServiceRoster> rosters;

  /// 本地快取（IndexedDB）裡的服事表。預設是空的，也就是 cache miss。
  List<ServiceRoster> cachedRosters;

  Map<ServiceType, List<String>> templates;
  Map<ServiceType, List<EventOption>> eventOptions;

  // ── 故意出事 ──────────────────────────────────────────────────────────

  /// 讀伺服器／讀快取時丟這個。
  Object? serverError;
  Object? cacheError;

  /// 設了就等它完成才回，讓測試控制讀取落地的時機。
  Completer<void>? serverPause;
  Completer<void>? cachePause;

  /// 寫這幾張服事表時失敗（單筆與 batch 都算）。
  Set<String> failRosterIds = {};

  /// batch 整批失敗。
  bool failAtomicWrites = false;

  /// 寫樣板／活動清單時丟這個。
  Object? failTemplateWrite;
  Object? failEventOptionWrite;

  // ── 紀錄 ──────────────────────────────────────────────────────────────

  int fetchRostersCallCount = 0;
  int fetchTemplatesCallCount = 0;
  int fetchEventOptionsCallCount = 0;

  int ensureCallCount = 0;
  List<ServiceType> ensureTypes = const [];

  /// 單筆 [updateRoster] 的次數。交換不該用到這條路。
  int singleWriteCount = 0;

  /// 每次 [updateRostersAtomically] 收到的批次。
  final List<List<ServiceRoster>> atomicBatches = [];

  int eventOptionWrites = 0;

  void resetCounts() {
    fetchRostersCallCount = 0;
    fetchTemplatesCallCount = 0;
    fetchEventOptionsCallCount = 0;
  }

  // ── RosterRepository ──────────────────────────────────────────────────

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async {
    fetchRostersCallCount++;
    if (serverPause case final pause?) await pause.future;
    if (serverError case final error?) throw error;
    return List.of(rosters);
  }

  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async {
    if (cachePause case final pause?) await pause.future;
    if (cacheError case final error?) throw error;
    return List.of(cachedRosters);
  }

  @override
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes) async {
    ensureCallCount++;
    ensureTypes = allowedTypes;
  }

  @override
  Future<void> updateRoster(ServiceRoster roster) async {
    singleWriteCount++;
    if (failRosterIds.contains(roster.id)) {
      throw Exception('Firestore write failed for ${roster.id}');
    }
    _store(roster);
  }

  @override
  Future<void> updateRostersAtomically(List<ServiceRoster> batch) async {
    if (failAtomicWrites || batch.any((r) => failRosterIds.contains(r.id))) {
      throw Exception('batch commit failed');
    }
    atomicBatches.add(List.of(batch));
    batch.forEach(_store);
  }

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async {
    fetchTemplatesCallCount++;
    return Map.of(templates);
  }

  @override
  Future<void> updateServiceTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {
    if (failTemplateWrite case final error?) throw error;
    this.templates = Map.of(templates);
  }

  @override
  Future<Map<ServiceType, List<EventOption>>> getEventOptions() async {
    fetchEventOptionsCallCount++;
    return Map.of(eventOptions);
  }

  @override
  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options,
  ) async {
    if (failEventOptionWrite case final error?) throw error;
    eventOptionWrites++;
    eventOptions = Map.of(options);
  }

  void _store(ServiceRoster roster) {
    final index = rosters.indexWhere((r) => r.id == roster.id);
    if (index == -1) {
      rosters.add(roster);
    } else {
      rosters[index] = roster;
    }
  }
}

/// 三個崇拜都有、但都是空的樣板或活動清單 —— 「載入過，只是還沒設定」。
Map<ServiceType, List<T>> emptyForEveryType<T>() => {
  for (final type in ServiceType.values) type: <T>[],
};
