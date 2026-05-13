import '../entities/event_option.dart';
import '../entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';

abstract class RosterRepository {
  Future<List<ServiceRoster>> getUpcomingRosters();

  /// 從本地 IndexedDB cache 讀取，不打網路。
  /// 若 cache 尚未建立（首次開啟或 cache 已清除），回傳空 list。
  Future<List<ServiceRoster>> getUpcomingRostersFromCache();

  /// 確保「本季 + 下季」的所有預定 roster 都在 Firestore 內（missing 的補寫）。
  /// 只有 admin 可呼叫；Firestore Rules 會擋未授權呼叫，client 端也需自行加 guard。
  Future<void> ensureQuarterRosters();

  Future<void> updateRoster(ServiceRoster roster);
  Future<Map<ServiceType, List<String>>> getServiceTemplates();
  Future<void> updateServiceTemplates(Map<ServiceType, List<String>> templates);
  Future<Map<ServiceType, List<EventOption>>> getEventOptions();
  Future<void> updateEventOptions(Map<ServiceType, List<EventOption>> options);
}
