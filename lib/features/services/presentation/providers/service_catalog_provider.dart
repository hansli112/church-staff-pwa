import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../../../../core/config/church_config.dart';
import '../../../../core/config/service_catalog.dart';
import '../../../../core/services/app_reload_service.dart';
import '../../data/service_settings_repository.dart';

/// 登入後讀一次 settings/services；跟目前用的清單不同就套用並重新載入。
class ServiceCatalogProvider extends ChangeNotifier {
  ServiceCatalogProvider(
    this._repository, {
    Future<bool> Function(String reason) reload = reloadAppOnce,
  }) : _reload = reload;

  final ServiceSettingsRepository _repository;
  final Future<bool> Function(String reason) _reload;
  String? _userId;

  /// 設定頁要知道目前的清單是不是已經存在 Firestore。
  ServiceSettings? settings;

  void onSessionChanged(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    if (userId != null) unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      settings = await _repository.load();
      final services = settings?.services;
      await ServiceCatalog.remember(services);
      if (ServiceCatalog.apply(services)) {
        notifyListeners();
        await _reload(_fingerprint(ChurchConfig.current.services));
      }
    } catch (e, st) {
      // 讀不到就沿用現在的清單（部署設定或本機快取），不影響其他功能。
      log('讀取聚會設定失敗', error: e, stackTrace: st);
    }
  }

  /// 管理員存好新的清單：套用、記下，再重新載入讓各頁面用新清單。
  Future<void> save(List<ServiceDefinition> services) async {
    await _repository.save(services);
    await ServiceCatalog.remember(services);
    ServiceCatalog.apply(services);
    settings = await _repository.load();
    notifyListeners();
    await _reload(_fingerprint(services));
  }

  static String _fingerprint(List<ServiceDefinition> services) =>
      jsonEncode([for (final service in services) service.toJson()]);
}
