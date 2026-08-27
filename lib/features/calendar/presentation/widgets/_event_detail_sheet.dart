import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '_calendar_models.dart';

final _dateFormat = DateFormat('yyyy/MM/dd (E)', 'zh_TW');
final _dateTimeFormat = DateFormat('yyyy/MM/dd (E) HH:mm', 'zh_TW');
final _timeFormat = DateFormat('HH:mm', 'zh_TW');

/// Bottom sheet content for a single calendar event's detail view.
///
/// Call via [showEventDetailSheet] which wraps [showModalBottomSheet].
///
/// [onEdit] and [onDelete] are supplied for admins only; without them this is
/// the read-only view every member sees.
Future<void> showEventDetailSheet(
  BuildContext context,
  CalendarEvent event, {
  Future<void> Function(CalendarEvent event)? onEdit,
  Future<void> Function(CalendarEvent event)? onDelete,
}) async {
  final colorScheme = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              EventDetailRow(
                icon: Icons.schedule,
                label: '時間',
                value: formatEventDateTime(event),
              ),
              if (event.location != null && event.location!.isNotEmpty) ...[
                const SizedBox(height: 12),
                EventDetailRow(
                  icon: Icons.place_outlined,
                  label: '地點',
                  value: event.location!,
                ),
              ],
              if (event.description != null &&
                  event.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '說明',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    event.description!,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ),
              ],
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onDelete != null)
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await onDelete(event);
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('刪除'),
                        style: TextButton.styleFrom(
                          foregroundColor: colorScheme.error,
                        ),
                      ),
                    if (onEdit != null) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await onEdit(event);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('編輯'),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Formats a full date-time string for the detail view.
String formatEventDateTime(CalendarEvent event) {
  if (event.isAllDay) {
    final startText = _dateFormat.format(event.startDay);
    if (!event.spansMultipleDays) {
      return '全天 | $startText';
    }
    final endText = _dateFormat.format(event.endDay);
    return '全天 | $startText - $endText';
  }

  final sameDay = DateUtils.isSameDay(event.startTime, event.endTime);
  final startText = _dateTimeFormat.format(event.startTime);
  if (sameDay) {
    final endText = _timeFormat.format(event.endTime);
    return '$startText - $endText';
  }

  final endText = _dateTimeFormat.format(event.endTime);
  return '$startText - $endText';
}

// ---------------------------------------------------------------------------
// EventDetailRow  — icon + label + value layout widget
// ---------------------------------------------------------------------------

class EventDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const EventDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}
