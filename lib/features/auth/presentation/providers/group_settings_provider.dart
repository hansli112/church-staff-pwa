import 'package:flutter/material.dart';
import '../../../roster/domain/entities/service_roster.dart';
import '../../domain/repositories/group_settings_repository.dart';

class GroupSettingsProvider extends ChangeNotifier {
  final GroupSettingsRepository _repository;

  Map<ServiceType, List<String>> _templates = {
    ServiceType.sundayService: [],
    ServiceType.youth: [],
    ServiceType.children: [],
  };
  bool _isLoading = false;
  String? _error;

  GroupSettingsProvider(this._repository) {
    fetchTemplates();
  }

  Map<ServiceType, List<String>> get templates => _templates;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchTemplates() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.getSmallGroupTemplates();
      _templates = result.isEmpty
          ? {
              ServiceType.sundayService: [],
              ServiceType.youth: [],
              ServiceType.children: [],
            }
          : result;
    } catch (e) {
      _error = '無法取得小組設定';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateTemplates(Map<ServiceType, List<String>> newTemplates) async {
    try {
      await _repository.updateSmallGroupTemplates(newTemplates);
      _templates = Map.from(newTemplates);
      notifyListeners();
    } catch (e) {
      _error = '更新小組設定失敗: $e';
      notifyListeners();
    }
  }
}
