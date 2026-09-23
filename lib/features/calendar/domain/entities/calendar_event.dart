/// One occurrence on the church calendar, in device-local time.
///
/// [startDay]/[endDay] are what the month grid buckets by, so the fetch window
/// in `calendarMonthWindow` has to use the same local day boundaries.
class CalendarEvent {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String title;
  final String? location;
  final String? description;

  const CalendarEvent({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.isAllDay,
    required this.title,
    this.location,
    this.description,
  });

  // DateUtils.dateOnly without the Flutter import: the domain layer stays
  // plain Dart.
  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String get identity => '$id|${startTime.toIso8601String()}';

  DateTime get startDay => _dateOnly(startTime);

  DateTime get endDay {
    final normalizedEnd = endTime.isBefore(startTime) ? startTime : endTime;
    final adjustedEnd = normalizedEnd.subtract(const Duration(microseconds: 1));
    final endDayOnly = _dateOnly(adjustedEnd);
    return endDayOnly.isBefore(startDay) ? startDay : endDayOnly;
  }

  bool get spansMultipleDays => endDay.isAfter(startDay);

  bool occursOnDate(DateTime date) {
    final day = _dateOnly(date);
    if (day.isBefore(startDay)) return false;
    return !day.isAfter(endDay);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'isAllDay': isAllDay,
    'title': title,
    'location': location,
    'description': description,
  };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final start = DateTime.parse(json['startTime'] as String).toLocal();
    final endRaw = json['endTime'];
    final end = endRaw is String ? DateTime.parse(endRaw).toLocal() : start;
    final idRaw = json['id'];
    return CalendarEvent(
      id: idRaw is String && idRaw.isNotEmpty
          ? idRaw
          : 'legacy_${start.toIso8601String()}_${json['title'] as String? ?? ''}',
      startTime: start,
      endTime: end,
      isAllDay: json['isAllDay'] as bool? ?? false,
      title: json['title'] as String,
      location: (json['location'] as String?)?.trim(),
      description: (json['description'] as String?)?.trim(),
    );
  }
}
