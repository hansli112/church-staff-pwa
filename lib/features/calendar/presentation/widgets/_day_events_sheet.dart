import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '_calendar_models.dart';
import '_event_detail_sheet.dart';

/// Bottom sheet that lists all events on a given [day].
///
/// Tapping an event row closes this sheet then opens [showEventDetailSheet].
/// Call via [showDayEventsSheet].
Future<void> showDayEventsSheet(
  BuildContext context, {
  required DateTime day,
  required List<CalendarEvent> events,
  required void Function(DateTime selectedDay) onSelectDay,
}) async {
  final title = DateFormat('yyyy/MM/dd (E)', 'zh_TW').format(day);
  final colorScheme = Theme.of(context).colorScheme;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '當天活動 ${events.length} 筆',
                style: TextStyle(fontSize: 13, color: colorScheme.primary),
              ),
              const SizedBox(height: 12),
              if (events.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('當天沒有活動'),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: events.length,
                    separatorBuilder: (_, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return Material(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.32,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            onSelectDay(event.startDay);
                            await showEventDetailSheet(context, event);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatEventTimeSummary(event),
                                  style: const TextStyle(fontSize: 13),
                                ),
                                if (event.location != null &&
                                    event.location!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    event.location!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

String _formatEventTimeSummary(CalendarEvent event) {
  if (event.isAllDay) {
    return event.spansMultipleDays ? '全天，多日活動' : '全天';
  }

  final sameDay = DateUtils.isSameDay(event.startTime, event.endTime);
  if (sameDay) {
    final startText = DateFormat('HH:mm', 'zh_TW').format(event.startTime);
    final endText = DateFormat('HH:mm', 'zh_TW').format(event.endTime);
    return '$startText - $endText';
  }

  final startText = DateFormat('MM/dd HH:mm', 'zh_TW').format(event.startTime);
  final endText = DateFormat('MM/dd HH:mm', 'zh_TW').format(event.endTime);
  return '$startText - $endText';
}
