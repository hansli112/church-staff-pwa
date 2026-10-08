import 'day.dart';
import 'models.dart';

/// One event's bar within a week of the month: from column [from] to [to]
/// (0–6, both included) on lane [lane], the first lane being 0.
class MonthBar {
  const MonthBar({
    required this.event,
    required this.from,
    required this.to,
    required this.lane,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  final CalendarEvent event;
  final int from;
  final int to;
  final int lane;

  /// Whether the event began before this bar (an earlier week or month).
  final bool continuesBefore;

  /// Whether the event goes on after this bar (a later week or month).
  final bool continuesAfter;
}

/// A week of the month on screen: its bars on the first [lanes] lanes, and
/// per column how many events did not fit.
class MonthWeek {
  const MonthWeek({required this.start, required this.bars, required this.hidden});

  /// The day in column 0, which may fall in the month before.
  final Day start;
  final List<MonthBar> bars;

  /// Column → events on that day not drawn; 「+N」 takes the day's last lane.
  final Map<int, int> hidden;

  bool get hasHidden => hidden.isNotEmpty;
}

/// The weeks of [month]'s calendar page, each starting on [firstWeekday]
/// (0 = Sunday … 6 = Saturday), with [events] laid out as bars on at most
/// [lanes] lanes. Bars stay inside the month: days of the months either
/// side are left empty.
///
/// A day with more events than lanes keeps its last lane for 「+N」, as
/// Google Calendar and Apple's Calendar do, so a week is always the same
/// height. Within a week, earlier and longer events go first, each on the
/// top lane free for all its days. An event with no such lane is split: it
/// is drawn on the days that have a lane free and counted as hidden only on
/// the days that have none, so a 「+N」 always stands for something not
/// drawn.
List<MonthWeek> monthWeeks(
  Iterable<CalendarEvent> events, {
  required Day month,
  required int firstWeekday,
  required int lanes,
}) {
  final first = month.firstOfMonth;
  final last = month.lastOfMonth;
  final weeks = <MonthWeek>[];
  for (
    var start = first.addDays(-((first.weekday % 7 - firstWeekday + 7) % 7));
    !start.isAfter(last);
    start = start.addDays(7)
  ) {
    final from = start.isBefore(first) ? first : start;
    final end = start.addDays(6);
    final pieces =
        [
          for (final e in events)
            if (e.daysWithin(from, end.isAfter(last) ? last : end) case final days?)
              (event: e, from: start.daysUntil(days.first), to: start.daysUntil(days.last)),
        ]..sort((a, b) {
          final byStart = a.from.compareTo(b.from);
          if (byStart != 0) return byStart;
          final byLength = (b.to - b.from).compareTo(a.to - a.from);
          if (byLength != 0) return byLength;
          return a.event.start.compareTo(b.event.start);
        });

    final taken = [for (var l = 0; l < lanes; l++) List.filled(7, false)];
    if (lanes > 0) {
      for (var c = 0; c < 7; c++) {
        if (pieces.where((p) => p.from <= c && c <= p.to).length > lanes) taken[lanes - 1][c] = true;
      }
    }
    bool free(int lane, int from, int to) => !taken[lane].sublist(from, to + 1).contains(true);
    final bars = <MonthBar>[];
    final hidden = <int, int>{};
    void place(CalendarEvent event, int lane, int from, int to) {
      for (var c = from; c <= to; c++) {
        taken[lane][c] = true;
      }
      bars.add(
        MonthBar(
          event: event,
          from: from,
          to: to,
          lane: lane,
          continuesBefore: event.day.isBefore(start.addDays(from)),
          continuesAfter: event.lastDay.isAfter(start.addDays(to)),
        ),
      );
    }

    for (final p in pieces) {
      final whole = [for (var l = 0; l < lanes; l++) l].where((l) => free(l, p.from, p.to)).firstOrNull;
      if (whole != null) {
        place(p.event, whole, p.from, p.to);
        continue;
      }
      // Day by day: runs of days on the same free lane become bars.
      int? runLane;
      var runFrom = p.from;
      for (var c = p.from; c <= p.to + 1; c++) {
        final lane = c > p.to ? null : [for (var l = 0; l < lanes; l++) l].where((l) => !taken[l][c]).firstOrNull;
        if (lane != runLane || c > p.to) {
          if (runLane != null) place(p.event, runLane, runFrom, c - 1);
          runLane = lane;
          runFrom = c;
        }
        if (c <= p.to && lane == null) hidden[c] = (hidden[c] ?? 0) + 1;
      }
    }
    weeks.add(MonthWeek(start: start, bars: bars, hidden: hidden));
  }
  return weeks;
}
