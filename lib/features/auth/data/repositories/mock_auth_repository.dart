import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../../roster/domain/entities/service_roster.dart';

class MockAuthRepository implements AuthRepository {
  // Simulating a database
  final List<User> _users = [
    const User(
      id: '1',
      name: '管理員',
      username: 'admin',
      role: UserRole.admin,
      zones: [
        UserZoneInfo(
          serviceType: ServiceType.sundayService,
          smallGroups: ['喜樂小組'],
          ministries: ['主日領會'],
        ),
      ],
    ),
    const User(
      id: '2',
      name: '一般同工',
      username: 'staff',
      role: UserRole.staff,
      zones: [
        UserZoneInfo(
          serviceType: ServiceType.youth,
          smallGroups: ['社青小組'],
          ministries: ['敬拜團', '招待'],
        ),
      ],
    ),
  ];
  final Map<String, String> _passwords = {
    'admin': 'admin123',
    'staff': 'staff123',
  };

  @override
  Future<User?> login(String username, String password) async {
    await Future.delayed(const Duration(seconds: 1));

    try {
      final user = _users.firstWhere((u) => u.username == username);
      if (_passwords[username] == password) {
        return user;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<List<User>> getUsers() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return List.from(_users);
  }

  @override
  Future<void> addUser(User user, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _users.add(user);
    _passwords[user.username] = password;
  }

  @override
  Future<void> updateUser(User user) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final index = _users.indexWhere((u) => u.id == user.id);
    if (index != -1) {
      final oldUsername = _users[index].username;
      _users[index] = user;
      if (oldUsername != user.username) {
        final existing = _passwords.remove(oldUsername);
        if (existing != null) {
          _passwords[user.username] = existing;
        }
      }
    }
  }

  @override
  Future<void> deleteUser(String id) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final index = _users.indexWhere((u) => u.id == id);
    if (index != -1) {
      final username = _users[index].username;
      _users.removeAt(index);
      _passwords.remove(username);
    }
  }
}
