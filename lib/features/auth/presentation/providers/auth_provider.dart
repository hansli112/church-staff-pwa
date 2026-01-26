import 'package:flutter/material.dart';
import '../../domain/entities/user.dart';
import '../../../roster/domain/entities/service_roster.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _repository;
  
  User? _currentUser;
  bool _isLoading = false;
  bool _isRestoring = true;
  String? _error;

  AuthProvider(this._repository) {
    _restoreSession();
  }

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isRestoring => _isRestoring;
  String? get error => _error;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  Future<void> _restoreSession() async {
    try {
      _currentUser = await _repository.getCurrentUser();
    } catch (e) {
      _error = '讀取登入狀態失敗: $e';
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _repository.login(username, password);
      if (user != null) {
        _currentUser = user;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = '帳號或密碼錯誤';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = '登入失敗: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    await _repository.logout();
    _currentUser = null;
    _isRestoring = false;
    
    _isLoading = false;
    notifyListeners();
  }

  // Admin features
  Future<List<User>> getUsers() async {
    if (!isAdmin) throw Exception('Permission denied');
    return await _repository.getUsers();
  }

  Future<void> addUser(
    String name, 
    String email,
    String username, 
    UserRole role, {
    required String password,
    List<UserZoneInfo> zones = const [],
  }) async {
    if (!isAdmin) throw Exception('Permission denied');
    
    final newUser = User(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      email: email,
      username: username,
      role: role,
      zones: zones,
    );
    await _repository.addUser(newUser, password);
    notifyListeners(); // Notify to update user lists if listening
  }

  Future<void> updateUser(User user, {String? password}) async {
    if (!isAdmin) throw Exception('Permission denied');
    await _repository.updateUser(user, password: password);
    
    // If updating self, refresh local user data
    if (_currentUser?.id == user.id) {
      _currentUser = user;
    }
    notifyListeners();
  }

  Future<void> deleteUser(String id) async {
    if (!isAdmin) throw Exception('Permission denied');
    await _repository.deleteUser(id);
    notifyListeners();
  }

  Future<void> cleanupUserMinistries(
    Map<ServiceType, List<String>> templates,
  ) async {
    if (!isAdmin) throw Exception('Permission denied');

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

    notifyListeners();
  }

  Future<void> cleanupUserGroups(
    Map<ServiceType, List<String>> templates,
  ) async {
    if (!isAdmin) throw Exception('Permission denied');

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

    notifyListeners();
  }
}
