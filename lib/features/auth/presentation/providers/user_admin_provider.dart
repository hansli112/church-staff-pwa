import 'package:flutter/material.dart';
import '../../domain/entities/user.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../domain/repositories/auth_repository.dart';
import 'session_provider.dart';

class UserAdminProvider extends ChangeNotifier {
  final AuthRepository _repository;
  final SessionProvider _session;

  // 同工選擇 dialog 每次開啟都要列全部使用者，避免重複打 Firestore。
  // 任何 admin 寫操作（addUser/updateUser/deleteUser）或登出後會清掉。
  List<User>? _cachedUsers;

  UserAdminProvider(this._repository, this._session) {
    // 當 session currentUser 變成 null（登出），自動清掉 cache。
    _session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (_session.currentUser == null && _cachedUsers != null) {
      _cachedUsers = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// 清除 cache（供外部在需要時呼叫，例如 ProxyProvider reset）。
  void clearCache() {
    if (_cachedUsers != null) {
      _cachedUsers = null;
      notifyListeners();
    }
  }

  Future<List<User>> getUsers({bool forceRefresh = false}) async {
    if (!_session.isAdmin) throw Exception('Permission denied');
    if (!forceRefresh && _cachedUsers != null) {
      return _cachedUsers!;
    }
    final users = await _repository.getUsers();
    _cachedUsers = users;
    return users;
  }

  Future<void> addUser(
    String name,
    String email,
    String username,
    UserRole role, {
    required String password,
    List<UserZoneInfo> zones = const [],
  }) async {
    if (!_session.isAdmin) throw Exception('Permission denied');

    final newUser = User(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      email: email,
      username: username,
      role: role,
      zones: zones,
    );
    await _repository.addUser(newUser, password);
    _cachedUsers = null;
    notifyListeners();
  }

  Future<void> updateUser(User user, {String? password}) async {
    if (!_session.isAdmin) throw Exception('Permission denied');
    await _repository.updateUser(user, password: password);

    // 若是管理員在修改自己的資料，通知 SessionProvider 更新 currentUser。
    _session.refreshCurrentUser(user);

    _cachedUsers = null;
    notifyListeners();
  }

  Future<void> deleteUser(String id) async {
    if (!_session.isAdmin) throw Exception('Permission denied');
    await _repository.deleteUser(id);
    _cachedUsers = null;
    notifyListeners();
  }

  Future<void> cleanupUserMinistries(
    Map<ServiceType, List<String>> templates,
  ) async {
    if (!_session.isAdmin) throw Exception('Permission denied');

    final users = await _repository.getUsers();
    for (final user in users) {
      bool changed = false;
      final updatedZones = user.zones.map((zone) {
        final allowed = templates[zone.serviceType] ?? const <String>[];
        final filtered = zone.ministries.where(allowed.contains).toList();
        if (filtered.length != zone.ministries.length) {
          changed = true;
        }
        return zone.copyWith(ministries: filtered);
      }).toList();

      if (changed) {
        await _repository.updateUser(user.copyWith(zones: updatedZones));
      }
    }

    _cachedUsers = null;
    notifyListeners();
  }

  Future<void> cleanupUserGroups(
    Map<ServiceType, List<String>> templates,
  ) async {
    if (!_session.isAdmin) throw Exception('Permission denied');

    final users = await _repository.getUsers();
    for (final user in users) {
      bool changed = false;
      final updatedZones = user.zones.map((zone) {
        final allowed = templates[zone.serviceType] ?? const <String>[];
        final filtered = zone.smallGroups.where(allowed.contains).toList();
        if (filtered.length != zone.smallGroups.length) {
          changed = true;
        }
        return zone.copyWith(smallGroups: filtered);
      }).toList();

      if (changed) {
        await _repository.updateUser(user.copyWith(zones: updatedZones));
      }
    }

    _cachedUsers = null;
    notifyListeners();
  }
}
