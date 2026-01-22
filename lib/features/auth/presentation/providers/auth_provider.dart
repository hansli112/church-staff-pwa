import 'package:flutter/material.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _repository;
  
  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  AuthProvider(this._repository);

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

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
    // For mock purposes, setting a default password
    await _repository.addUser(newUser, '${username}123');
    notifyListeners(); // Notify to update user lists if listening
  }

  Future<void> updateUser(User user) async {
    if (!isAdmin) throw Exception('Permission denied');
    await _repository.updateUser(user);
    
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
}