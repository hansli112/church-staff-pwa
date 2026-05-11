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
