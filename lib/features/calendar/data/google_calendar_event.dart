import '../domain/entities/calendar_event.dart';

/// Parses one entry of the Google Calendar API's `items` array.
///
/// Shared by the month listing and by the create/edit response, which returns
/// the raw Google item on purpose: if the two paths parsed separately, an event
/// could render one way when it is saved and another way after a reload.
///
/// Returns null for entries with nothing to show — cancelled events, and
/// entries with no usable start. Throws on a malformed date, which the month
/// listing catches per item so one bad entry cannot blank out the month.
///
/// [fallbackIndex] only feeds the synthetic id used when Google omits one; it
/// keeps two id-less events in the same response from colliding.
CalendarEvent? calendarEventFromGoogleItem(
  Map<String, dynamic> raw, {
  int fallbackIndex = 0,
}) {
  if (raw['status'] == 'cancelled') return null;

  final start = raw['start'] as Map<String, dynamic>?;
  final end = raw['end'] as Map<String, dynamic>?;
  final startRaw = start?['dateTime'] ?? start?['date'];
  if (startRaw is! String) return null;

  final endRaw = end?['dateTime'] ?? end?['date'];
  final startTime = DateTime.parse(startRaw).toLocal();
  final endTime = endRaw is String
      ? DateTime.parse(endRaw).toLocal()
      : startTime;

  // An all-day event carries `date` on both ends and never `dateTime`.
  final isAllDay =
      start?['dateTime'] == null &&
      start?['date'] is String &&
      end?['dateTime'] == null;

  final title = (raw['summary'] as String?)?.trim();
  final location = (raw['location'] as String?)?.trim();
  final description = (raw['description'] as String?)?.trim();
  final eventId = (raw['id'] as String?)?.trim();

  return CalendarEvent(
    id: eventId == null || eventId.isEmpty
        ? 'fallback_${fallbackIndex}_${startTime.toIso8601String()}_${title ?? ''}'
        : eventId,
    startTime: startTime,
    endTime: endTime,
    isAllDay: isAllDay,
    title: title == null || title.isEmpty ? '未命名活動' : title,
    location: location == null || location.isEmpty ? null : location,
    description: description == null || description.isEmpty
        ? null
        : description,
  );
}
