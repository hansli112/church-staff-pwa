import 'package:flutter/material.dart';
import '../../domain/entities/service_roster.dart';
import '../../domain/repositories/roster_repository.dart';

class RosterProvider with ChangeNotifier {
  final RosterRepository _repository;

  List<ServiceRoster> _allRosters = []; // 儲存所有原始資料
  Map<ServiceType, List<String>> _templates = {};
  bool _isLoading = false;
  bool _isEditMode = false;
  String? _error;

  RosterProvider(this._repository);

  bool get isLoading => _isLoading;
  bool get isEditMode => _isEditMode;
  String? get error => _error;
  Map<ServiceType, List<String>> get templates => _templates;

  void toggleEditMode() {
    _isEditMode = !_isEditMode;
    notifyListeners();
  }

  // 取得特定類別的服事表
  List<ServiceRoster> getRostersByType(ServiceType type) {
    return _allRosters.where((r) => r.type == type).toList();
  }
  
  // 為了相容性，如果有人直接 call rosters (雖然目前沒人用)，回傳全部
  List<ServiceRoster> get rosters => _allRosters;

  Future<void> fetchInitialData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.getUpcomingRosters(),
        _repository.getServiceTemplates(),
      ]);
      _allRosters = results[0] as List<ServiceRoster>;
      _templates = results[1] as Map<ServiceType, List<String>>;
      await _seedEmptyRostersFromTemplates();
    } catch (e) {
      _error = '無法取得資料，請稍後再試';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchRosters() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _allRosters = await _repository.getUpcomingRosters();
    } catch (e) {
      _error = '無法取得服事表，請稍後再試';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateRoster(ServiceRoster roster) async {
    try {
      await _repository.updateRoster(roster);
      // Update local state
      final index = _allRosters.indexWhere((r) => r.id == roster.id);
      if (index != -1) {
        _allRosters[index] = roster;
        notifyListeners();
      }
    } catch (e) {
      _error = '更新失敗: $e';
      notifyListeners();
    }
  }

  Future<void> updateTemplates(Map<ServiceType, List<String>> newTemplates) async {
    try {
      await _repository.updateServiceTemplates(newTemplates);
      _templates = Map.from(newTemplates);
      await _seedEmptyRostersFromTemplates();
      notifyListeners();
    } catch (e) {
      _error = '更新設定失敗: $e';
      notifyListeners();
    }
  }

  Future<void> _seedEmptyRostersFromTemplates() async {
    if (_templates.isEmpty || _allRosters.isEmpty) return;

    final List<ServiceRoster> updates = [];
    for (final roster in _allRosters) {
      final roles = _templates[roster.type] ?? [];
      if (roles.isEmpty) continue;
      final normalized = _normalizeDuties(roster.duties, roles);
      if (_dutiesEqual(roster.duties, normalized)) continue;
      updates.add(roster.copyWith(duties: normalized));
    }

    if (updates.isEmpty) return;

    for (final updated in updates) {
      final index = _allRosters.indexWhere((r) => r.id == updated.id);
      if (index != -1) {
        _allRosters[index] = updated;
      }
    }
    notifyListeners();

    for (final updated in updates) {
      try {
        await _repository.updateRoster(updated);
      } catch (e) {
        _error = '更新失敗: $e';
      }
    }
    if (_error != null) {
      notifyListeners();
    }
  }

  List<RosterEntry> _normalizeDuties(List<RosterEntry> duties, List<String> roles) {
    final Map<String, List<String>> existing = {
      for (final duty in duties) duty.role: List<String>.from(duty.people),
    };

    final List<RosterEntry> normalized = [];
    for (final role in roles) {
      final people = existing.remove(role) ?? [];
      normalized.add(RosterEntry(
        role: role,
        people: people.isEmpty ? ['待定'] : people,
      ));
    }

    return normalized;
  }

  bool _dutiesEqual(List<RosterEntry> a, List<RosterEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final dutyA = a[i];
      final dutyB = b[i];
      if (dutyA.role != dutyB.role) return false;
      if (dutyA.people.length != dutyB.people.length) return false;
      for (var j = 0; j < dutyA.people.length; j++) {
        if (dutyA.people[j] != dutyB.people[j]) return false;
      }
    }
    return true;
  }
}
