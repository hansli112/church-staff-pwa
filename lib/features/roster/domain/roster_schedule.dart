import '../../../core/time/church_time.dart';
import '../../../core/types/service_type.dart';
import 'entities/service_roster.dart';
import 'staff_directory.dart';

/// 月份到最後一個月才顯示並產生下季，保留目前編輯頁的範圍。
DateTime rosterQuarterEnd(DateTime now) {
  final startMonth = ((now.month - 1) ~/ 3) * 3 + 1;
  final endMonth = now.month == startMonth + 2
      ? startMonth + 5
      : startMonth + 2;
  return DateTime.utc(now.year, endMonth + 1, 0);
}

/// 一種聚會每週一場；修改星期後，已排過的週次不補第二場，也不搬動原日期。
/// 日期使用純年月日運算，不以 24 小時當成教會時區的一天。
List<ServiceRoster> planQuarterRosters({
  required DateTime now,
  required List<ServiceType> types,
  required Map<ServiceType, List<String>> templates,
  required Iterable<ServiceRoster> existing,
}) {
  final today = ChurchTime.dateOnly(now);
  final end = rosterQuarterEnd(today);
  final occupied = existing.map((r) => _weekKey(r.type, r.date)).toSet();
  final result = <ServiceRoster>[];
  for (final type in types.toSet()) {
    if (!type.enabled) continue;
    var date = today.add(
      Duration(days: (type.weekday - today.weekday + 7) % 7),
    );
    while (!date.isAfter(end)) {
      if (occupied.add(_weekKey(type, date))) {
        result.add(
          ServiceRoster(
            id: rosterDocumentId(type, date),
            date: date,
            type: type,
            serviceName: type.serviceName,
            duties: (templates[type] ?? [])
                .map(
                  (role) =>
                      RosterEntry(role: role, people: [placeholderPerson]),
                )
                .toList(),
          ),
        );
      }
      date = date.add(const Duration(days: 7));
    }
  }
  result.sort((a, b) {
    final dateOrder = a.date.compareTo(b.date);
    return dateOrder == 0 ? a.type.index.compareTo(b.type.index) : dateOrder;
  });
  return result;
}

String rosterDocumentId(ServiceType type, DateTime date) =>
    '${ChurchTime.dateKey(date).replaceAll('-', '')}_${type.name}';

/// Transaction 必須讀相同的七個文件，不只讀目標日期；不同星期的客戶端才會
/// 在同一週互相衝突並重試，而不是各自成功建立不同日期的服事表。
List<String> rosterWeekDocumentIds(ServiceType type, DateTime date) {
  final monday = _weekStart(date);
  return [
    for (var day = 0; day < 7; day++)
      rosterDocumentId(type, monday.add(Duration(days: day))),
  ];
}

DateTime _weekStart(DateTime value) {
  final date = ChurchTime.dateOnly(value);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

String _weekKey(ServiceType type, DateTime value) =>
    '${type.name}/${ChurchTime.dateKey(_weekStart(value))}';
