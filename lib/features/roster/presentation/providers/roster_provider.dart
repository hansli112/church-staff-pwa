import 'package:flutter/material.dart';
import '../../domain/entities/service_roster.dart';
import '../../domain/repositories/roster_repository.dart';

class RosterProvider with ChangeNotifier {
  final RosterRepository _repository;

  List<ServiceRoster> _allRosters = []; // 儲存所有原始資料
  bool _isLoading = false;
  String? _error;

  RosterProvider(this._repository);

  bool get isLoading => _isLoading;
  String? get error => _error;

  // 取得特定類別的服事表
  List<ServiceRoster> getRostersByType(ServiceType type) {
    return _allRosters.where((r) => r.type == type).toList();
  }
  
  // 為了相容性，如果有人直接 call rosters (雖然目前沒人用)，回傳全部
  List<ServiceRoster> get rosters => _allRosters;

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
}