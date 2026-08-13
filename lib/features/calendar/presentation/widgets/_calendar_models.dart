import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// CalendarEvent
// ---------------------------------------------------------------------------

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

  String get identity => '$id|${startTime.toIso8601String()}';

  DateTime get startDay => DateUtils.dateOnly(startTime);

  DateTime get endDay {
    final normalizedEnd = endTime.isBefore(startTime) ? startTime : endTime;
    final adjustedEnd = normalizedEnd.subtract(const Duration(microseconds: 1));
    final endDayOnly = DateUtils.dateOnly(adjustedEnd);
    return endDayOnly.isBefore(startDay) ? startDay : endDayOnly;
  }

  bool get spansMultipleDays => endDay.isAfter(startDay);

  bool occursOnDate(DateTime date) {
    final day = DateUtils.dateOnly(date);
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

// ---------------------------------------------------------------------------
// DayEventSegment  — one event bar rendered inside a single calendar cell
// ---------------------------------------------------------------------------

class DayEventSegment {
  final CalendarEvent event;
  final int lane;
  final bool showTitle;
  final int titleShiftDays;
  final double startTextInset;
  final bool continuesLeft;
  final bool continuesRight;

  const DayEventSegment({
    required this.event,
    required this.lane,
    required this.showTitle,
    required this.titleShiftDays,
    required this.startTextInset,
    required this.continuesLeft,
    required this.continuesRight,
  });
}

// ---------------------------------------------------------------------------
// WeekEventSegment  — internal layout helper for a single week row
// ---------------------------------------------------------------------------

class WeekEventSegment {
  final CalendarEvent event;
  final int startIndex;
  final int endIndex;

  const WeekEventSegment({
    required this.event,
    required this.startIndex,
    required this.endIndex,
  });
}
