enum ServiceType {
  sundayService, // 主日
  youth, // 青崇
  children, // 兒主
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
  final List<String> people;
  final List<String> peopleOrder;
  final Map<String, String> personIdsByName;

  RosterEntry({
    required this.role,
    required this.people,
    this.peopleOrder = const [],
    this.personIdsByName = const {},
  });

  RosterEntry copyWith({
    String? role,
    List<String>? people,
    List<String>? peopleOrder,
    Map<String, String>? personIdsByName,
  }) {
    return RosterEntry(
      role: role ?? this.role,
      people: people ?? this.people,
      peopleOrder: peopleOrder ?? this.peopleOrder,
      personIdsByName: personIdsByName ?? this.personIdsByName,
    );
  }

  List<String> get assignedUserIds {
    final seen = <String>{};
    final ids = <String>[];
    for (final id in personIdsByName.values) {
      final trimmed = id.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) continue;
      seen.add(trimmed);
      ids.add(trimmed);
    }
    return ids;
  }
}

class ServiceRoster {
  final String id;
  final DateTime date;
  final ServiceType type; // 新增類別
  final String serviceName;
  final List<RosterEntry> duties;
  final List<String> specialEvents;

  ServiceRoster({
    required this.id,
    required this.date,
    required this.type, // Required
    required this.serviceName,
    required this.duties,
    this.specialEvents = const [],
  });

  ServiceRoster copyWith({
    String? id,
    DateTime? date,
    ServiceType? type,
    String? serviceName,
    List<RosterEntry>? duties,
    List<String>? specialEvents,
  }) {
    return ServiceRoster(
      id: id ?? this.id,
      date: date ?? this.date,
      type: type ?? this.type,
      serviceName: serviceName ?? this.serviceName,
      duties: duties ?? this.duties,
      specialEvents: specialEvents ?? this.specialEvents,
    );
  }
}
