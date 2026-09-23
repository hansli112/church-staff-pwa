import '../../domain/entities/calendar_event.dart';

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
