import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/month_weeks.dart';
import '../../l10n/app_localizations.dart';
import '../rosters/format.dart';

/// The month grid above the agenda. Each day lists its events by name, on
/// up to [_Metrics.lanes] bars (an event over several days is one bar); a
/// day with more shows 「+N」 on its last bar. With text too large for
/// names, a dot marks the days with events instead. Tapping a day selects it; swiping sideways
/// changes the month.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.events,
    required this.selected,
    required this.onSelect,
    required this.onShift,
  });

  /// Any day of the month on screen.
  final Day month;
  final Day today;

  /// The month's events, as the agenda shows them.
  final List<CalendarEvent> events;
  final Day? selected;
  final ValueChanged<Day> onSelect;
  final ValueChanged<int> onShift;

  /// How tall the grid is for a month of six weeks, the most a month takes,
  /// at this text size. Events do not change it.
  static double tallest(BuildContext context) => _Metrics.of(context).height(weeks: 6);

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final c = AppColors.of(context);
    final m = _Metrics.of(context);
    final firstWeekday = material.firstDayOfWeekIndex; // 0 = Sunday
    final weeks = monthWeeks(events, month: month, firstWeekday: firstWeekday, lanes: m.lanes);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 200) return;
        onShift(v < 0 ? 1 : -1);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.s),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Text(
                        material.narrowWeekdays[(firstWeekday + i) % 7],
                        textAlign: TextAlign.center,
                        style: _Metrics.weekday.copyWith(color: c.secondaryLabel),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),
            for (final week in weeks) _Week(grid: this, week: week, metrics: m),
          ],
        ),
      ),
    );
  }
}

/// Every size in the grid, worked out once from the text size: whether
/// names fit, and where the number and the bars go in a week. Events never
/// change them, so loading a month never moves the grid.
class _Metrics {
  _Metrics._(this.showsNames, this._line, this._minTap);

  factory _Metrics.of(BuildContext context) {
    final text = MediaQuery.textScalerOf(context);
    final showsNames = text.scale(eventName.fontSize!) <= eventName.fontSize! * _namesUpTo;
    return _Metrics._(
      showsNames,
      (style) => text.scale(style.fontSize!) * style.height!,
      Space.minTap(Theme.of(context).platform),
    );
  }

  static const number = AppText.subheadline;
  static const weekday = AppText.caption;
  static const eventName = AppText.caption2;

  /// Names fit in a day up to this much larger text; beyond it, dots.
  static const _namesUpTo = 1.3;

  /// The thin gap between bars, and around the number when names show.
  static const hairline = 2.0;
  static const dot = Space.xs;

  final bool showsNames;
  final double Function(TextStyle) _line;
  final double _minTap;

  /// Bars a day has room for; none when it shows dots.
  int get lanes => showsNames ? 2 : 0;

  /// The day number's circle: smaller when names share the day.
  double get circle => showsNames ? Space.l : Space.xl;
  double get numberHeight => max(circle, _line(number));
  double get numberTop => showsNames ? hairline : 0;
  double get lanesTop => numberTop + numberHeight + hairline;
  double get laneHeight => _line(eventName) + hairline;

  /// 「+N」 sits on a day's last lane.
  double get moreTop => lanesTop + (lanes - 1) * laneHeight;
  double get weekHeight => max(showsNames ? lanesTop + lanes * laneHeight : numberHeight + dot, _minTap);

  double height({required int weeks}) => _line(weekday) + Space.xs + weeks * weekHeight + Space.s;
}

/// One week of the grid: the days, and over them the bars and 「+N」.
class _Week extends StatelessWidget {
  const _Week({required this.grid, required this.week, required this.metrics});

  final MonthGrid grid;
  final MonthWeek week;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final m = metrics;
    final first = grid.month.firstOfMonth;
    final last = grid.month.lastOfMonth;

    Widget day(int column) {
      final d = week.start.addDays(column);
      if (d.isBefore(first) || d.isAfter(last)) return const SizedBox.shrink();
      final titles = [
        for (final e in grid.events)
          if (e.covers(d)) e.title,
      ];
      final label = dayLabel(l10n, d, grid.today);
      return _DayCell(
        number: d.day,
        label: titles.isEmpty ? label : '$label，${titles.join('、')}',
        isToday: d == grid.today,
        isSelected: d == grid.selected,
        hasEvents: titles.isNotEmpty,
        metrics: m,
        onTap: () => grid.onSelect(d),
      );
    }

    return SizedBox(
      height: m.weekHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final column = constraints.maxWidth / 7;
          return Stack(
            fit: StackFit.expand,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var i = 0; i < 7; i++) Expanded(child: day(i))],
              ),
              if (m.showsNames) ...[
                for (final bar in week.bars)
                  Positioned(
                    left: bar.from * column + _Metrics.hairline / 2,
                    width: (bar.to - bar.from + 1) * column - _Metrics.hairline,
                    top: m.lanesTop + bar.lane * m.laneHeight,
                    height: m.laneHeight - _Metrics.hairline,
                    child: IgnorePointer(
                      child: ExcludeSemantics(child: _Bar(bar: bar)),
                    ),
                  ),
                for (final MapEntry(key: col, value: n) in week.hidden.entries)
                  Positioned(
                    left: col * column,
                    width: column,
                    top: m.moreTop,
                    height: m.laneHeight - _Metrics.hairline,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Text(
                          '+$n',
                          textAlign: TextAlign.center,
                          style: _Metrics.eventName.copyWith(color: c.secondaryLabel),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// An event's name on its days, square where it carries on into the next
/// or previous week. Bars take the surface colour, apart from today's grey.
class _Bar extends StatelessWidget {
  const _Bar({required this.bar});

  final MonthBar bar;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const round = Radius.circular(Space.xs);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.horizontal(
          left: bar.continuesBefore ? Radius.zero : round,
          right: bar.continuesAfter ? Radius.zero : round,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _Metrics.hairline),
        // One line of whole characters: the line breaks between characters
        // and only the first line shows.
        child: Text(
          bar.event.title,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: _Metrics.eventName.copyWith(color: c.label),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.number,
    required this.label,
    required this.isToday,
    required this.isSelected,
    required this.hasEvents,
    required this.metrics,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool isToday;
  final bool isSelected;
  final bool hasEvents;
  final _Metrics metrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final m = metrics;
    // The accent marks the picked day only; today stands out by weight and
    // a neutral fill.
    final fill = isSelected
        ? c.accent
        : isToday
        ? c.fill
        : null;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.s),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: m.showsNames ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            SizedBox(height: m.numberTop),
            // Very large numbers shrink to fit the day's width instead of wrapping.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: m.circle, minHeight: m.circle),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(m.circle / 2)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        '$number',
                        style: _Metrics.number.copyWith(
                          color: isSelected ? c.onAccent : c.label,
                          fontWeight: isToday || isSelected ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!m.showsNames)
              Container(
                width: _Metrics.dot,
                height: _Metrics.dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasEvents ? c.secondaryLabel : Colors.transparent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
