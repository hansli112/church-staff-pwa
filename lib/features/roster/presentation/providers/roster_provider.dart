import 'dart:developer';

import 'package:flutter/material.dart';
import '../../domain/entities/event_option.dart';
import '../../domain/entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../domain/repositories/roster_repository.dart';
import '../../../../core/utils/error_messages.dart';

class RosterProvider with ChangeNotifier {
  final RosterRepository _repository;

  List<ServiceRoster> _allRosters = []; // 儲存所有原始資料
  Map<ServiceType, List<String>> _templates = {};
  Map<ServiceType, List<EventOption>> _eventOptionsByType = {};
  bool _isLoading = false;
  bool _isEditMode = false;
  String? _error;

  // 追蹤上一次 session userId，用來判斷帳號是否真的換了。
  String? _lastSessionUserId;

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

  /// 由 ChangeNotifierProxyProvider 在 SessionProvider.currentUser 變動時呼叫。
  /// 當 userId 真的改變（含登出 → null 或切換帳號），清掉全部 cache 並重抓資料。
  void onSessionChanged(String? userId) {
    if (userId == _lastSessionUserId) return;
    _lastSessionUserId = userId;

    _allRosters = [];
    _templates = {};
    _eventOptionsByType = {};
    _error = null;
    _isEditMode = false;

    if (userId != null) {
      // 有新使用者，重抓資料。
      fetchInitialData();
    } else {
      // 登出，僅清除並通知 UI。
      notifyListeners();
    }
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
    } catch (e, st) {
      log('載入服事表資料失敗', error: e, stackTrace: st);
      _error = '載入失敗:${mapErrorToUserMessage(e)}';
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
    } catch (e, st) {
      log('載入服事表失敗', error: e, stackTrace: st);
      _error = '載入失敗:${mapErrorToUserMessage(e)}';
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
    } catch (e, st) {
      log('更新 roster 失敗', error: e, stackTrace: st);
      _error = '更新失敗:${mapErrorToUserMessage(e)}';
      notifyListeners();
    }
  }

  /// Batch-update rosters in parallel. On partial failure we still sync the
  /// successful writes into local state (so the UI matches Firestore truth)
  /// and then throw a summary so the caller can surface the partial error
  /// and offer "retry only failed". Plain `Future.wait` would also have
  /// written the same rows to Firestore but left local state empty,
  /// drifting the UI from the server.
  Future<void> updateRosters(List<ServiceRoster> rosters) async {
    if (rosters.isEmpty) return;
    final results = await Future.wait(
      rosters.map((roster) async {
        try {
          await _repository.updateRoster(roster);
          return (
            roster: roster,
            error: null as Object?,
            stackTrace: null as StackTrace?,
          );
        } catch (e, st) {
          return (
            roster: roster,
            error: e as Object?,
            stackTrace: st as StackTrace?,
          );
        }
      }),
    );

    final successes = results.where((r) => r.error == null).toList();
    for (final r in successes) {
      final index = _allRosters.indexWhere((x) => x.id == r.roster.id);
      if (index != -1) {
        _allRosters[index] = r.roster;
      }
    }
    notifyListeners();

    final failures = results.where((r) => r.error != null).toList();
    if (failures.isNotEmpty) {
      throw PartialUpdateException(
        successCount: successes.length,
        failureCount: failures.length,
        failedRosters: failures.map((r) => r.roster).toList(),
        cause: failures.first.error!,
        causeStackTrace: failures.first.stackTrace,
      );
    }
  }

  Future<void> updateTemplates(
    Map<ServiceType, List<String>> newTemplates, {
    Map<ServiceType, Map<String, String>> renamedRolesByType = const {},
  }) async {
    try {
      await _repository.updateServiceTemplates(newTemplates);
      _templates = Map.from(newTemplates);

      if (renamedRolesByType.isNotEmpty) {
        final updatedRosters = <ServiceRoster>[];
        for (final roster in _allRosters) {
          final renameMap = renamedRolesByType[roster.type];
          if (renameMap == null || renameMap.isEmpty) {
            continue;
          }

          var hasChanges = false;
          final updatedDuties = roster.duties.map((duty) {
            final renamedRole = renameMap[duty.role];
            if (renamedRole == null || renamedRole == duty.role) {
              return duty;
            }
            hasChanges = true;
            return duty.copyWith(role: renamedRole);
          }).toList();

          if (!hasChanges) {
            continue;
          }

          final updated = roster.copyWith(duties: updatedDuties);
          updatedRosters.add(updated);
        }

        if (updatedRosters.isNotEmpty) {
          await Future.wait(
            updatedRosters.map((roster) => _repository.updateRoster(roster)),
          );

          final updatedById = {
            for (final roster in updatedRosters) roster.id: roster,
          };
          _allRosters = _allRosters
              .map((roster) => updatedById[roster.id] ?? roster)
              .toList();
        }
      }

      notifyListeners();
    } catch (e, st) {
      log('更新服事表樣板失敗', error: e, stackTrace: st);
      _error = '更新失敗:${mapErrorToUserMessage(e)}';
      notifyListeners();
    }
  }

  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options, {
    Map<ServiceType, Map<String, String>> renamedEventsByType = const {},
  }) async {
    try {
      await _repository.updateEventOptions(options);
      _eventOptionsByType = Map.fromEntries(
        options.entries.map(
          (entry) => MapEntry(entry.key, List<EventOption>.from(entry.value)),
        ),
      );

      if (renamedEventsByType.isNotEmpty) {
        final updatedRosters = <ServiceRoster>[];
        for (final roster in _allRosters) {
          final renameMap = renamedEventsByType[roster.type];
          if (renameMap == null || renameMap.isEmpty) {
            continue;
          }

          var hasChanges = false;
          final updatedEvents = roster.specialEvents.map((event) {
            final renamedEvent = renameMap[event];
            if (renamedEvent == null || renamedEvent == event) {
              return event;
            }
            hasChanges = true;
            return renamedEvent;
          }).toList();

          final newColors = Map<String, int>.from(roster.customEventColors);
          for (final entry in renameMap.entries) {
            final oldName = entry.key;
            final newName = entry.value;
            if (oldName == newName) continue;
            if (newColors.containsKey(oldName)) {
              newColors[newName] = newColors.remove(oldName)!;
              hasChanges = true;
            }
          }

          if (!hasChanges) {
            continue;
          }

          final updated = roster.copyWith(
            specialEvents: updatedEvents,
            customEventColors: newColors,
          );
          updatedRosters.add(updated);
        }

        if (updatedRosters.isNotEmpty) {
          await Future.wait(
            updatedRosters.map((roster) => _repository.updateRoster(roster)),
          );

          final updatedById = {
            for (final roster in updatedRosters) roster.id: roster,
          };
          _allRosters = _allRosters
              .map((roster) => updatedById[roster.id] ?? roster)
              .toList();
        }
      }

      notifyListeners();
    } catch (e, st) {
      log('更新事件選項失敗', error: e, stackTrace: st);
      _error = '更新失敗:${mapErrorToUserMessage(e)}';
      notifyListeners();
    }
  }
}

class PartialUpdateException implements Exception {
  final int successCount;
  final int failureCount;
  final List<ServiceRoster> failedRosters;
  final Object cause;
  final StackTrace? causeStackTrace;

  PartialUpdateException({
    required this.successCount,
    required this.failureCount,
    required this.failedRosters,
    required this.cause,
    this.causeStackTrace,
  });

  @override
  String toString() =>
      '$successCount 筆寫入成功，$failureCount 筆失敗（首個錯誤：$cause）';
}
