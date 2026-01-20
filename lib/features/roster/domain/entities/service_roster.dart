enum ServiceType {
  sundayService, // 主日
  youth,         // 青崇
  children       // 兒主
}

extension ServiceTypeExtension on ServiceType {
  String get label {
    switch (this) {
      case ServiceType.sundayService:
        return '主日';
      case ServiceType.youth:
        return '青崇';
      case ServiceType.children:
        return '兒主';
    }
  }
}

class RosterEntry {
  final String role;
  final String personName;

  RosterEntry({required this.role, required this.personName});
}

class ServiceRoster {
  final String id;
  final DateTime date;
  final ServiceType type; // 新增類別
  final String serviceName;
  final List<RosterEntry> duties;

  ServiceRoster({
    required this.id,
    required this.date,
    required this.type, // Required
    required this.serviceName,
    required this.duties,
  });
}