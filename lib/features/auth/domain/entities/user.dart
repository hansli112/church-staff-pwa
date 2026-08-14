import 'package:church_staff_pwa/core/types/service_type.dart';

/// 身分，不是權限。
///
/// 編輯權限走 [UserGroup]，不看這個欄位 —— 唯一的例外是 [UserRole.admin]，
/// 它等同 root，隱含所有 group。這樣「他是誰」跟「他能改什麼」可以各自變動：
/// 不是每個小組長都要能編服事表，也不是每個能編行事曆的人都是小組長。
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

/// 編輯權限，比照 Linux 的 group：一個人可以同時屬於多個，彼此正交 —— 可以只
/// 給行事曆不給服事表。管理員等同 root，不必列在任何 group 裡就擁有全部。
///
/// 存進 Firestore 的是 [name]（字串），所以這些字串是資料格式的一部分，改名
/// 等於要遷移資料。三個強制點共用同一組名稱：這裡、`firestore.rules` 的
/// `inGroup()`、`worker/google_calendar.js` 的 `CALENDAR_GROUP`。
enum UserGroup {
  rosterEditors('roster-editors', '服事表編輯', '服事表'),
  calendarEditors('calendar-editors', '行事曆編輯', '行事曆');

  const UserGroup(this.name, this.label, this.shortLabel);

  /// 寫進 Firestore 的值。
  final String name;

  /// 勾選框用的完整名稱。
  final String label;

  /// 使用者列表的副標只有一行，會被 ellipsis 切掉，所以那裡用短名。
  final String shortLabel;

  static UserGroup? byName(String name) {
    for (final group in UserGroup.values) {
      if (group.name == name) return group;
    }
    return null;
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

  /// 這個人被授予的編輯 group。admin 不需要列在裡面就擁有全部。
  final Set<UserGroup> groups;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.username,
    required this.role,
    this.zones = const [],
    this.groups = const {},
  });

  bool get isAdmin => role == UserRole.admin;

  /// admin 等同 root：隱含所有 group，不必個別授予。
  ///
  /// UI 用這個決定顯不顯示編輯入口，真正的強制點在 `firestore.rules` 與
  /// `worker/google_calendar.js` —— 前端擋不住直接打 Firestore 的人。
  bool inGroup(UserGroup group) => isAdmin || groups.contains(group);

  bool get canEditRoster => inGroup(UserGroup.rosterEditors);
  bool get canEditCalendar => inGroup(UserGroup.calendarEditors);

  /// 認不得的東西一律丟掉，絕不拋例外。
  ///
  /// `hasValidGroups()` 只擋得住經過 App 的寫入 —— Firebase console 手改、
  /// Admin SDK 腳本、遷移程式都繞得過去。而 [User.fromJson] 是整份名單共用的
  /// 解析路徑（`getUsers()` 對整個 snapshot 逐筆 map），所以一份格式壞掉的
  /// 文件若在這裡拋 `_TypeError`，倒的不是那一個人，是所有人的帳號管理與服事
  /// 表人員選擇器 —— 連管理員要去修那個欄位的畫面都打不開。
  ///
  /// 隔壁的 role 也是同樣的取捨（`orElse: () => UserRole.member`）。
  static Set<UserGroup> _parseGroups(dynamic raw) {
    if (raw is! List) return const {};
    return raw
        .map((e) => e is String ? UserGroup.byName(e) : null)
        .nonNulls
        .toSet();
  }

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
      zones:
          (json['zones'] as List<dynamic>?)
              ?.map((e) => UserZoneInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      groups: _parseGroups(json['groups']),
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
      // 順序固定，否則每次存檔都會產生一筆沒有實質變化的 Firestore 寫入。
      'groups': [
        for (final group in UserGroup.values)
          if (groups.contains(group)) group.name,
      ],
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? username,
    UserRole? role,
    List<UserZoneInfo>? zones,
    Set<UserGroup>? groups,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      username: username ?? this.username,
      role: role ?? this.role,
      zones: zones ?? this.zones,
      groups: groups ?? this.groups,
    );
  }
}
