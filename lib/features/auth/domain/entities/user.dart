import '../../../roster/domain/entities/service_roster.dart';

enum UserRole {
  admin,
  leader,
  staff,
  member;

  String get label {
    switch (this) {
      case UserRole.admin:
        return '管理員';
      case UserRole.leader:
        return '小組長';
      case UserRole.staff:
        return '同工';
      case UserRole.member:
        return '組員';
    }
  }
}

class UserZoneInfo {
  final ServiceType serviceType;
  final List<String> smallGroups;
  final List<String> ministries;

  const UserZoneInfo({
    required this.serviceType,
    this.smallGroups = const [],
    this.ministries = const [],
  });

  factory UserZoneInfo.fromJson(Map<String, dynamic> json) {
    return UserZoneInfo(
      serviceType: ServiceType.values.firstWhere(
        (e) => e.toString().split('.').last == json['serviceType'],
        orElse: () => ServiceType.sundayService,
      ),
      smallGroups: List<String>.from(json['smallGroups'] ?? []),
      ministries: List<String>.from(json['ministries'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serviceType': serviceType.toString().split('.').last,
      'smallGroups': smallGroups,
      'ministries': ministries,
    };
  }

  UserZoneInfo copyWith({
    ServiceType? serviceType,
    List<String>? smallGroups,
    List<String>? ministries,
  }) {
    return UserZoneInfo(
      serviceType: serviceType ?? this.serviceType,
      smallGroups: smallGroups ?? this.smallGroups,
      ministries: ministries ?? this.ministries,
    );
  }
}

class User {
  final String id;
  final String name;
  final String email;
  final String username;
  final UserRole role;
  final List<UserZoneInfo> zones;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.username,
    required this.role,
    this.zones = const [],
  });

  bool get isAdmin => role == UserRole.admin;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String? ?? '',
      username: json['username'] as String,
      role: UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == json['role'],
        orElse: () => UserRole.member,
      ),
      zones: (json['zones'] as List<dynamic>?)
              ?.map((e) => UserZoneInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'username': username,
      'role': role.toString().split('.').last,
      'zones': zones.map((e) => e.toJson()).toList(),
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? username,
    UserRole? role,
    List<UserZoneInfo>? zones,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      username: username ?? this.username,
      role: role ?? this.role,
      zones: zones ?? this.zones,
    );
  }
}