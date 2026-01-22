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

  @override
  Future<User?> login(String username, String password) async {
    await Future.delayed(const Duration(seconds: 1));

    if (username == 'admin' && password == 'admin123') {
      return _users.firstWhere((u) => u.username == 'admin');
    } else if (username == 'staff' && password == 'staff123') {
      return _users.firstWhere((u) => u.username == 'staff');
    } else {
        try {
            final user = _users.firstWhere((u) => u.username == username);
            if (password == '${username}123') {
                return user;
            }
        } catch (_) {}
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
  }

  @override
  Future<void> updateUser(User user) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final index = _users.indexWhere((u) => u.id == user.id);
    if (index != -1) {
      _users[index] = user;
    }
  }

  @override
  Future<void> deleteUser(String id) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _users.removeWhere((u) => u.id == id);
  }
}
