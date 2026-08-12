import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../domain/repositories/group_settings_repository.dart';
import '../../../../core/utils/error_messages.dart';

class GroupSettingsProvider extends ChangeNotifier {
  final GroupSettingsRepository _repository;

  Map<ServiceType, List<String>> _templates = {
    ServiceType.sundayService: [],
    ServiceType.youth: [],
    ServiceType.children: [],
  };
  bool _isLoading = false;
  String? _error;

  // 追蹤上一次 session userId，用來判斷帳號是否真的換了。
  String? _lastSessionUserId;

  // Fetch generation counter：每次 session 變動時遞增，讓過期 fetch 的結果被丟棄。
  int _fetchToken = 0;

  GroupSettingsProvider(this._repository);

  /// 故意回傳 raw reference（不做 defensive copy），讓消費端可以用 `identical()`
  /// 廉價偵測「templates 是否真的換過一份」— 例如 user_management_screen 用這個
  /// 判斷要不要重新排序。改成 `Map.from(_templates)` 會讓 identical 永遠 false，
  /// 默默退化使用端的優化。
  Map<ServiceType, List<String>> get templates => _templates;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchTemplates() async {
    final token = ++_fetchToken;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.getSmallGroupTemplates();
      if (token != _fetchToken) return; // stale fetch，丟棄結果
      _templates = result.isEmpty
          ? {
              ServiceType.sundayService: [],
              ServiceType.youth: [],
              ServiceType.children: [],
            }
          : result;
    } catch (e, st) {
      if (token != _fetchToken) return; // stale fetch，丟棄錯誤
      log('載入小組設定失敗', error: e, stackTrace: st);
      _error = '載入失敗:${mapErrorToUserMessage(e)}';
    } finally {
      if (token == _fetchToken) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 由 ChangeNotifierProxyProvider 在 SessionProvider.currentUser 變動時呼叫。
  /// 當 userId 真的改變，清掉 cache 並重抓資料。
  void onSessionChanged(String? userId) {
    if (userId == _lastSessionUserId) return;
    _lastSessionUserId = userId;

    _fetchToken++; // 讓進行中的 fetch 過期
    _templates = {
      ServiceType.sundayService: [],
      ServiceType.youth: [],
      ServiceType.children: [],
    };
    _error = null;

    if (userId != null) {
      fetchTemplates();
    } else {
      notifyListeners();
    }
  }

  Future<void> updateTemplates(
    Map<ServiceType, List<String>> newTemplates,
  ) async {
    try {
      await _repository.updateSmallGroupTemplates(newTemplates);
      _templates = Map.from(newTemplates);
      notifyListeners();
    } catch (e, st) {
      log('更新小組設定失敗', error: e, stackTrace: st);
      _error = '更新失敗:${mapErrorToUserMessage(e)}';
      notifyListeners();
    }
  }
}
