import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/time/church_time.dart';
import '../../../core/types/service_type.dart';
import '../domain/entities/service_roster.dart';

Map<String, dynamic> rosterToFirestore(ServiceRoster roster) => {
  'date': Timestamp.fromDate(
    roster.storedDate ?? ChurchTime.atDate(roster.date),
  ),
  'dateKey': ChurchTime.dateKey(roster.date),
  'type': roster.type.name,
  'serviceName': roster.serviceName,
  'specialEvents': roster.specialEvents,
  'customEventColors': Map<String, dynamic>.from(roster.customEventColors),
  'duties': roster.duties
      .map(
        (duty) => {
          'role': duty.role,
          'people': duty.people,
          'personIdsByName': duty.personIdsByName,
        },
      )
      .toList(),
};

ServiceRoster rosterFromFirestore(Map<String, dynamic> data, String id) {
  final storedDate = (data['date'] as Timestamp).toDate();
  final key = data['dateKey'];
  // 舊 ID 本來就記錄了排表的日期。不要用現在的裝置或教會時區重新解讀，
  // 否則出國或修改部署時區會把已排好的服事移到另一日。
  final idDate = RegExp(r'^(\d{4})(\d{2})(\d{2})_').firstMatch(id);
  final date = key is String
      ? ChurchTime.parseDate(key)
      : idDate != null
      ? ChurchTime.parseDate('${idDate[1]}-${idDate[2]}-${idDate[3]}')
      : ChurchTime.dateOnly(ChurchTime.inZone(storedDate));
  final typeName = data['type'];
  if (typeName is! String || typeName.isEmpty) {
    throw const FormatException('服事表缺少聚會 ID');
  }
  final colors = data['customEventColors'];
  return ServiceRoster(
    id: id,
    date: date,
    storedDate: storedDate,
    type: ServiceType.fromName(typeName),
    serviceName: data['serviceName'] as String? ?? '',
    specialEvents: List<String>.from(data['specialEvents'] ?? const []),
    customEventColors: colors is Map
        ? Map<String, int>.fromEntries(
            colors.entries
                .where((e) => e.key is String && e.value is num)
                .map(
                  (e) => MapEntry(e.key as String, (e.value as num).toInt()),
                ),
          )
        : const {},
    duties:
        (data['duties'] as List<dynamic>?)?.map((item) {
          final duty = item as Map<String, dynamic>;
          return RosterEntry(
            role: duty['role'] as String,
            people: List<String>.from(duty['people'] ?? []),
            personIdsByName: _personIds(duty['personIdsByName']),
          );
        }).toList() ??
        [],
  );
}

Map<String, String> _personIds(dynamic raw) {
  if (raw is! Map) return const {};
  final result = <String, String>{};
  raw.forEach((key, value) {
    if (key is! String || value is! String) return;
    final name = key.trim();
    final uid = value.trim();
    if (name.isNotEmpty && uid.isNotEmpty) result[name] = uid;
  });
  return result;
}
