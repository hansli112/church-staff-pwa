import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import 'calendar_screen.dart';

/// Read-only details, for people who cannot edit the calendar.
Future<void> showEventDetail(BuildContext context, CalendarEvent e) {
  final l10n = L10n.of(context);
  final fmt = DateFormat.MMMEd('zh_TW');
  final time = DateFormat.Hm('zh_TW');
  return showAppSheet<void>(
    context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.title, style: AppText.title3),
            const SizedBox(height: Space.s),
            Text(
              e.allDay
                  ? '${fmt.format(e.start)} ${l10n.calAllDay}'
                  : '${fmt.format(e.start)} ${time.format(e.start)}–${time.format(e.end)}',
              style: AppText.body,
            ),
            if (e.location != null && e.location!.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(e.location!, style: AppText.body.copyWith(color: AppColors.of(context).secondaryLabel)),
            ],
            if (e.description != null && e.description!.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Text(e.description!, style: AppText.callout),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Opens the editor for [event] (null for a new one) and saves through the
/// backend. Deleting offers 復原, which creates the event again.
Future<void> editEvent(BuildContext context, WidgetRef ref, CalendarEvent? event, {required DateTime month}) async {
  final l10n = L10n.of(context);
  final church = ref.read(churchDataProvider)!;
  final today = ref.read(todayProvider);
  final initialDay =
      event?.start ??
      (month.year == today.year && month.month == today.month ? DateTime(today.year, today.month, today.day) : month);
  final result = await showAppSheet<_EditResult>(
    context,
    expand: true,
    builder: (_) => _EventEditor(event: event, initialDay: initialDay),
  );
  if (result == null || !context.mounted) return;
  void refresh(CalendarEvent e) => ref.invalidate(calendarEventsProvider(monthKey(e.start)));
  try {
    if (result.delete && event != null) {
      await church.calendarDelete(event);
      refresh(event);
      if (!context.mounted) return;
      showToast(
        context,
        l10n.calDeleted(event.title),
        onUndo: () async {
          final again = CalendarEvent(
            title: event.title,
            start: event.start,
            end: event.end,
            allDay: event.allDay,
            location: event.location,
            description: event.description,
          );
          await church.calendarSave(again);
          refresh(again);
        },
      );
    } else if (result.event != null) {
      await church.calendarSave(result.event!, previous: event);
      refresh(result.event!);
      if (event != null && monthKey(event.start) != monthKey(result.event!.start)) refresh(event);
      if (context.mounted) showToast(context, l10n.calSaved);
    }
  } catch (_) {
    if (context.mounted) showToast(context, l10n.saveFailed);
  }
}

class _EditResult {
  const _EditResult({this.event, this.delete = false});

  final CalendarEvent? event;
  final bool delete;
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({required this.event, required this.initialDay});

  final CalendarEvent? event;
  final DateTime initialDay;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _location = TextEditingController(text: widget.event?.location ?? '');
  late bool _allDay = widget.event?.allDay ?? false;
  late DateTime _day = DateTime(widget.initialDay.year, widget.initialDay.month, widget.initialDay.day);
  late TimeOfDay _start = widget.event == null
      ? const TimeOfDay(hour: 19, minute: 30)
      : TimeOfDay.fromDateTime(widget.event!.start);
  late TimeOfDay _end = widget.event == null
      ? const TimeOfDay(hour: 21, minute: 0)
      : TimeOfDay.fromDateTime(widget.event!.end);

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  /// How many days the event spans, kept when editing so changing a title
  /// does not cut a three-day camp to one day. All-day: days covered (end
  /// is exclusive); timed: days between start and end (1 past midnight).
  late final int _span = widget.event == null
      ? 0
      : DateTime(
          widget.event!.end.year,
          widget.event!.end.month,
          widget.event!.end.day,
        ).difference(DateTime(widget.event!.start.year, widget.event!.start.month, widget.event!.start.day)).inDays;

  DateTime _at(TimeOfDay t, [int plusDays = 0]) =>
      DateTime(_day.year, _day.month, _day.day + plusDays, t.hour, t.minute);

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final start = _allDay ? _day : _at(_start);
    final keep = widget.event != null && widget.event!.allDay == _allDay;
    var end = _allDay
        ? DateTime(_day.year, _day.month, _day.day + (keep && _span > 1 ? _span : 1))
        : _at(_end, keep ? _span : 0);
    if (!end.isAfter(start)) end = start.add(const Duration(hours: 1));
    Navigator.pop(
      context,
      _EditResult(
        event: CalendarEvent(
          id: widget.event?.id,
          title: title,
          start: start,
          end: end,
          allDay: _allDay,
          location: _location.text.trim().isEmpty ? null : _location.text.trim(),
          description: widget.event?.description,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final date = DateFormat.yMMMEd('zh_TW');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.s, 0),
          child: Row(
            children: [
              Expanded(child: Text(widget.event == null ? l10n.calNewEvent : l10n.calEditEvent, style: AppText.title3)),
              SecondaryButton(label: l10n.save, onPressed: _title.text.trim().isEmpty ? null : _save),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + Space.l),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                child: TextField(
                  controller: _title,
                  autofocus: widget.event == null,
                  decoration: InputDecoration(hintText: l10n.calTitle),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m),
                child: TextField(
                  controller: _location,
                  decoration: InputDecoration(hintText: l10n.calLocation),
                ),
              ),
              ListSection(
                children: [
                  SwitchRow(title: l10n.calAllDay, value: _allDay, onChanged: (v) => setState(() => _allDay = v)),
                  ListRow(
                    title: l10n.calDate,
                    value: date.format(_day),
                    chevron: false,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _day,
                        firstDate: DateTime(_day.year - 1),
                        lastDate: DateTime(_day.year + 2),
                      );
                      if (picked != null) setState(() => _day = picked);
                    },
                  ),
                  if (!_allDay) ...[
                    ListRow(
                      title: l10n.calStart,
                      value: _start.format(context),
                      chevron: false,
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: _start);
                        if (t != null) setState(() => _start = t);
                      },
                    ),
                    ListRow(
                      title: l10n.calEnd,
                      value: _end.format(context),
                      chevron: false,
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: _end);
                        if (t != null) setState(() => _end = t);
                      },
                    ),
                  ],
                ],
              ),
              if (widget.event != null)
                ListSection(
                  children: [
                    ListRow(
                      title: l10n.calDelete,
                      destructive: true,
                      onTap: () => Navigator.pop(context, const _EditResult(delete: true)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
