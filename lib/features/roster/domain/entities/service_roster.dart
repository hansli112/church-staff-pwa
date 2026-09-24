import 'package:church_staff_pwa/core/types/service_type.dart';

class RosterEntry {
  final String role;

  /// 這一天排到的人，照同工排序（`StaffOrder`）排好。
  final List<String> people;
  final Map<String, String> personIdsByName;

  RosterEntry({
    required this.role,
    required this.people,
    this.personIdsByName = const {},
  });

  RosterEntry copyWith({
    String? role,
    List<String>? people,
    Map<String, String>? personIdsByName,
  }) {
    return RosterEntry(
      role: role ?? this.role,
      people: people ?? this.people,
      personIdsByName: personIdsByName ?? this.personIdsByName,
    );
  }
}

class ServiceRoster {
  final String id;
  final DateTime date;
  final ServiceType type; // 新增類別
  final String serviceName;
  final List<RosterEntry> duties;
  final List<String> specialEvents;
  final Map<String, int> customEventColors; // key: event name, value: ARGB int

  ServiceRoster({
    required this.id,
    required this.date,
    required this.type, // Required
    required this.serviceName,
    required this.duties,
    this.specialEvents = const [],
    this.customEventColors = const {},
  });

  ServiceRoster copyWith({
    String? id,
    DateTime? date,
    ServiceType? type,
    String? serviceName,
    List<RosterEntry>? duties,
    List<String>? specialEvents,
    Map<String, int>? customEventColors,
  }) {
    return ServiceRoster(
      id: id ?? this.id,
      date: date ?? this.date,
      type: type ?? this.type,
      serviceName: serviceName ?? this.serviceName,
      duties: duties ?? this.duties,
      specialEvents: specialEvents ?? this.specialEvents,
      customEventColors: customEventColors ?? this.customEventColors,
    );
  }
}
