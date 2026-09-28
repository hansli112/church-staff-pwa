import 'dart:convert';
import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

import 'church_config.dart';

/// 聚會清單從哪裡來。
///
/// 部署設定（build 時寫死的 CHURCH_CONFIG_JSON）是預設值；管理員在「聚會設定」
/// 改過之後，清單存在 Firestore 的 settings/services，以那份為準。這樣新增
/// 禱告會、改星期幾都不必重新部署。
///
/// App 各處都透過 [ChurchConfig.current] 讀聚會（見 ServiceType），所以這裡只
/// 負責把 current 換成「部署設定 + 另一份聚會清單」。為了不在啟動時等網路，
/// 最後一次讀到的清單會存在本機，啟動時先套用（[applyCached]）。
class ServiceCatalog {
  ServiceCatalog._();

  static const cacheKey = 'service_catalog_v1';

  static ChurchConfig? _deployed;

  /// build 時的部署設定。第一次存取時記下，之後 current 被換掉也不受影響。
  static ChurchConfig get deployed => _deployed ??= ChurchConfig.current;

  /// 測試用：換一份部署設定，並清掉已套用的覆寫。
  static void resetForTesting(ChurchConfig config) {
    _deployed = config;
    ChurchConfig.current = config;
  }

  /// settings/services 裡的清單；格式不對就當作沒有，沿用部署設定。
  static List<ServiceDefinition>? parseDocument(Map<String, dynamic>? data) {
    if (data == null) return null;
    try {
      return ChurchConfig.parseServices(data['services']);
    } catch (e) {
      log('settings/services 格式不正確，沿用部署設定', error: e);
      return null;
    }
  }

  /// 套用 [services]（null = 回到部署設定）。回傳清單有沒有真的改變。
  static bool apply(List<ServiceDefinition>? services) {
    final next = services ?? deployed.services;
    final current = ChurchConfig.current.services;
    if (current.length == next.length &&
        Iterable.generate(current.length).every((i) => current[i] == next[i])) {
      return false;
    }
    ChurchConfig.current = deployed.withServices(next);
    return true;
  }

  /// 啟動時先用上一次讀到的清單，不等網路。
  static Future<void> applyCached() async {
    deployed;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null) return;
      apply(ChurchConfig.parseServices(jsonDecode(raw)));
    } catch (e) {
      log('讀取本機聚會清單失敗，沿用部署設定', error: e);
    }
  }

  static Future<void> remember(List<ServiceDefinition>? services) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (services == null) {
        await prefs.remove(cacheKey);
      } else {
        await prefs.setString(
          cacheKey,
          jsonEncode([for (final service in services) service.toJson()]),
        );
      }
    } catch (e) {
      log('儲存本機聚會清單失敗', error: e);
    }
  }

  /// 要寫進 settings/services 的 ids：用過的聚會 ID 永遠留著（Firestore rules
  /// 用它判斷哪些聚會存在，只能增加不能減少），加上部署設定的和這次的。
  static List<String> knownIds(
    Iterable<String> previous,
    List<ServiceDefinition> services,
  ) => {
    ...previous,
    ...deployed.services.map((service) => service.id),
    ...services.map((service) => service.id),
  }.toList();
}
