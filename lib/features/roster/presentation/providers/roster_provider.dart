import 'package:flutter/material.dart';
import '../../domain/entities/event_option.dart';
import '../../domain/entities/service_roster.dart';
import '../../domain/repositories/roster_repository.dart';

class RosterProvider with ChangeNotifier {
  final RosterRepository _repository;

  List<ServiceRoster> _allRosters = []; // 儲存所有原始資料
  Map<ServiceType, List<String>> _templates = {};
  Map<ServiceType, List<EventOption>> _eventOptionsByType = {};
  bool _isLoading = false;
  bool _isEditMode = false;
  String? _error;

  RosterProvider(this._repository);

  bool get isLoading => _isLoading;
  bool get isEditMode => _isEditMode;
  String? get error => _error;
  Map<ServiceType, List<String>> get templates => _templates;
  Map<ServiceType, List<EventOption>> get eventOptionsByType => Map.fromEntries(
    _eventOptionsByType.entries.map(
      (entry) => MapEntry(entry.key, List<EventOption>.from(entry.value)),
    ),
  );
  List<EventOption> eventOptionsFor(ServiceType type) =>
      List.unmodifiable(_eventOptionsByType[type] ?? const <EventOption>[]);
  int eventColorFor(ServiceType type, String name) {
    final options = _eventOptionsByType[type] ?? const <EventOption>[];
    final direct = options.firstWhere(
      (e) => e.name == name,
      orElse: () => const EventOption(name: '', color: 0xFFF39C12),
    );
    if (direct.name.isNotEmpty) return direct.color;
    for (final list in _eventOptionsByType.values) {
      final found = list.firstWhere(
        (e) => e.name == name,
        orElse: () => const EventOption(name: '', color: 0xFFF39C12),
      );
      if (found.name.isNotEmpty) return found.color;
    }
    return 0xFFF39C12;
  }

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
        _repository.getEventOptions(),
      ]);
      _allRosters = results[0] as List<ServiceRoster>;
      _templates = results[1] as Map<ServiceType, List<String>>;
      _eventOptionsByType = results[2] as Map<ServiceType, List<EventOption>>;
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

  Future<void> updateTemplates(
    Map<ServiceType, List<String>> newTemplates,
  ) async {
    try {
      await _repository.updateServiceTemplates(newTemplates);
      _templates = Map.from(newTemplates);
      notifyListeners();
    } catch (e) {
      _error = '更新設定失敗: $e';
      notifyListeners();
    }
  }

  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options,
  ) async {
    try {
      await _repository.updateEventOptions(options);
      _eventOptionsByType = Map.fromEntries(
        options.entries.map(
          (entry) => MapEntry(entry.key, List<EventOption>.from(entry.value)),
        ),
      );
      notifyListeners();
    } catch (e) {
      _error = '更新事件選項失敗: $e';
      notifyListeners();
    }
  }

}
