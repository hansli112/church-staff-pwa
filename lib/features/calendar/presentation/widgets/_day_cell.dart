import 'package:flutter/material.dart';

import '_calendar_models.dart';
import '_event_segment_bar.dart';

/// A single day cell in the monthly calendar grid.
///
/// Renders the day number, up to [maxVisibleEvents] event bars, and an
/// overflow indicator when there are more events than can be shown.
class DayCell extends StatelessWidget {
  const DayCell({
    super.key,
    required this.dayNumber,
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.segments,
    required this.maxVisibleEvents,
    required this.cellWidth,
    required this.onTap,
    required this.onEventTap,
  });

  final int dayNumber;
  final DateTime date;
  final bool isSelected;
  final bool isToday;
  final List<DayEventSegment> segments;
  final int maxVisibleEvents;
  final double cellWidth;
  final VoidCallback onTap;
  final void Function(CalendarEvent event) onEventTap;

  static const int _maxLinesPerEvent = 2;

  @override
  Widget build(BuildContext context) {
    final visibleEvents = segments.take(maxVisibleEvents).toList();
    final overflowCount = segments.length - visibleEvents.length;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : isToday
              ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '$dayNumber',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: visibleEvents
                    .map(
                      (segment) => EventSegmentBar(
                        segment: segment,
                        maxLines: _maxLinesPerEvent,
                        cellWidth: cellWidth,
                        onTap: () => onEventTap(segment.event),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (overflowCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+$overflowCount',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
