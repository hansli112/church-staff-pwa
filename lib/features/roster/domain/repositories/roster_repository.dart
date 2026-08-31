import '../entities/event_option.dart';
import '../entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';

abstract class RosterRepository {
  Future<List<ServiceRoster>> getUpcomingRosters();

  /// 從本地 IndexedDB cache 讀取，不打網路。
  /// 若 cache 尚未建立（首次開啟或 cache 已清除），回傳空 list。
  Future<List<ServiceRoster>> getUpcomingRostersFromCache();

  /// 確保「本季 + 下季」的預定 roster 都在 Firestore 內（missing 的補寫），
  /// 範圍限制在 [allowedTypes] 這幾個聚會別。
  ///
  /// [allowedTypes] 是必填而不是預設全部：batch 是原子的，只要裡面混進一筆呼叫
  /// 者無權寫入的聚會別，整批都會被 rules 打回，連他自己那本也補不出來。
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes);

  Future<void> updateRoster(ServiceRoster roster);

  /// 以單一 batch 寫入多筆服事表：全部成功，或全部不寫。
  ///
  /// 服事交換一定要走這裡。兩筆各寫各的話，一邊成功一邊失敗會留下「一個人被
  /// 排兩天、另一個人的那天空著」—— 而那正是交換本身要避免的狀態。
  ///
  /// JSON 匯入刻意不走這裡：那邊寧可部分成功，把失敗的日期報出來讓人重試，
  /// 也不要因為其中一天壞掉就整季都不寫（見 [ServiceRoster] 的批次匯入路徑）。
  Future<void> updateRostersAtomically(List<ServiceRoster> rosters);
  Future<Map<ServiceType, List<String>>> getServiceTemplates();
  Future<void> updateServiceTemplates(Map<ServiceType, List<String>> templates);
  Future<Map<ServiceType, List<EventOption>>> getEventOptions();
  Future<void> updateEventOptions(Map<ServiceType, List<EventOption>> options);
}
