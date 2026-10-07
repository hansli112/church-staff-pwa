import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../l10n/app_localizations.dart';
import '../rosters/format.dart';

/// A small month above the agenda: a dot under each day with an event, so
/// the free days show at a glance. Tapping a day selects it; swiping
/// sideways changes the month.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.marked,
    required this.selected,
    required this.onSelect,
    required this.onShift,
  });

  /// Any day of the month on screen.
  final Day month;
  final Day today;

  /// Days of [month] with at least one event.
  final Set<Day> marked;
  final Day? selected;
  final ValueChanged<Day> onSelect;
  final ValueChanged<int> onShift;

  static const _number = AppText.subheadline;
  static const _weekday = AppText.caption;
  static const _dot = Space.xs;

  /// Days before the first of [month] in its first week.
  static int _leading(BuildContext context, Day month) =>
      (month.firstOfMonth.weekday % 7 - MaterialLocalizations.of(context).firstDayOfWeekIndex + 7) % 7;

  static int _weeks(BuildContext context, Day month) => ((_leading(context, month) + month.lastOfMonth.day) / 7).ceil();

  static double _rowHeight(BuildContext context) {
    final number = MediaQuery.textScalerOf(context).scale(_number.fontSize!) * _number.height!;
    final content = (number > Space.xl ? number : Space.xl) + _dot;
    final tap = Space.minTap(Theme.of(context).platform);
    return content > tap ? content : tap;
  }

  /// How tall the grid for [month] is at this text size.
  static double heightOf(BuildContext context, Day month) {
    final weekday = MediaQuery.textScalerOf(context).scale(_weekday.fontSize!) * _weekday.height!;
    return weekday + Space.xs + _weeks(context, month) * _rowHeight(context) + Space.s;
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final c = AppColors.of(context);
    final l10n = L10n.of(context);
    final firstWeekday = material.firstDayOfWeekIndex; // 0 = Sunday
    final first = month.firstOfMonth;
    final length = month.lastOfMonth.day;
    final leading = _leading(context, month);
    final rowHeight = _rowHeight(context);

    Widget cell(int index) {
      final n = index - leading + 1;
      if (n < 1 || n > length) return const Expanded(child: SizedBox.shrink());
      final day = first.addDays(n - 1);
      final hasEvents = marked.contains(day);
      final label = dayLabel(l10n, day, today);
      return Expanded(
        child: _DayCell(
          number: n,
          label: hasEvents ? '$label，${l10n.calHasEvents}' : label,
          isToday: day == today,
          isSelected: day == selected,
          hasEvents: hasEvents,
          height: rowHeight,
          onTap: () => onSelect(day),
        ),
      );
    }

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
                        style: _weekday.copyWith(color: c.secondaryLabel),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),
            for (var w = 0; w < _weeks(context, month); w++)
              Row(children: [for (var i = 0; i < 7; i++) cell(w * 7 + i)]),
          ],
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
    required this.height,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool isToday;
  final bool isSelected;
  final bool hasEvents;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
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
        child: SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Very large numbers shrink to fit the day's width instead of wrapping.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: Space.xl, minHeight: Space.xl),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(Space.xl / 2)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                      child: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Text(
                          '$number',
                          style: MonthGrid._number.copyWith(
                            color: isSelected ? c.onAccent : c.label,
                            fontWeight: isToday || isSelected ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: MonthGrid._dot,
                height: MonthGrid._dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasEvents ? c.secondaryLabel : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
