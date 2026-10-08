import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/calendar.dart';
import '../../state/providers.dart';

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
              switch (e) {
                _ when e.allDay && e.lastDay == e.day => '${fmt.format(e.start)} ${l10n.calAllDay}',
                _ when e.allDay =>
                  '${fmt.format(e.start)} – ${fmt.format(DateTime(e.lastDay.year, e.lastDay.month, e.lastDay.day))}',
                _ when e.lastDay == e.day => '${fmt.format(e.start)} ${time.format(e.start)}–${time.format(e.end)}',
                _ => '${fmt.format(e.start)} ${time.format(e.start)} – ${fmt.format(e.end)} ${time.format(e.end)}',
              },
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
/// backend. A new event starts on [day] when one is picked, else today in
/// this month or the month's first. Deleting offers 復原, which creates the
/// event again.
Future<void> editEvent(
  BuildContext context,
  WidgetRef ref,
  CalendarEvent? event, {
  required DateTime month,
  Day? day,
}) async {
  final l10n = L10n.of(context);
  final today = ref.read(todayProvider);
  final initialDay =
      event?.start ??
      (day != null
          ? DateTime(day.year, day.month, day.day)
          : month.year == today.year && month.month == today.month
          ? DateTime(today.year, today.month, today.day)
          : month);
  final result = await showAppSheet<_EditResult>(
    context,
    expand: true,
    builder: (_) => _EventEditor(event: event, initialDay: initialDay, thisYear: today.year),
  );
  if (result == null || !context.mounted) return;
  final calendar = ref.read(calendarActionsProvider);
  try {
    if (result.delete && event != null) {
      final undo = await calendar.delete(event);
      if (!context.mounted) return;
      showToast(context, l10n.calDeleted(event.title), onUndo: () => undo().ignore());
    } else if (result.event != null) {
      await calendar.save(result.event!, previous: event);
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
  const _EventEditor({required this.event, required this.initialDay, required this.thisYear});

  final CalendarEvent? event;
  final DateTime initialDay;

  /// Dates in this year are shown without it.
  final int thisYear;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _location = TextEditingController(text: widget.event?.location ?? '');
  late bool _allDay = widget.event?.allDay ?? false;

  // The first and last day, both included, and the times when not all day.
  // An all-day event keeps the usual times for when it is switched to one
  // with times.
  late DateTime _startDay = _dateOf(widget.event?.start ?? widget.initialDay);
  late DateTime _endDay = switch (widget.event) {
    null => _startDay,
    final e when e.allDay => _dateOf(DateTime(e.lastDay.year, e.lastDay.month, e.lastDay.day)),
    final e => _dateOf(e.end),
  };
  late TimeOfDay _startTime = widget.event == null || widget.event!.allDay
      ? const TimeOfDay(hour: 19, minute: 30)
      : TimeOfDay.fromDateTime(widget.event!.start);
  late TimeOfDay _endTime = widget.event == null || widget.event!.allDay
      ? const TimeOfDay(hour: 21, minute: 0)
      : TimeOfDay.fromDateTime(widget.event!.end);

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  static DateTime _dateOf(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _at(DateTime day, TimeOfDay t) => DateTime(day.year, day.month, day.day, t.hour, t.minute);

  DateTime get _start => _allDay ? _startDay : _at(_startDay, _startTime);

  /// Exclusive, as the calendar keeps it: the day after the last for an
  /// all-day event.
  DateTime get _end => _allDay ? DateTime(_endDay.year, _endDay.month, _endDay.day + 1) : _at(_endDay, _endTime);

  bool get _valid => _end.isAfter(_start);

  /// Moves the start; the end moves with it, so the event keeps its length.
  void _moveStart(DateTime day, TimeOfDay time) {
    final days = _endDay.difference(_startDay).inDays;
    final length = _at(_endDay, _endTime).difference(_at(_startDay, _startTime));
    setState(() {
      _startDay = day;
      _startTime = time;
      if (_allDay) {
        _endDay = DateTime(day.year, day.month, day.day + (days < 0 ? 0 : days));
      } else {
        final end = _at(day, time).add(length > Duration.zero ? length : const Duration(hours: 1));
        _endDay = _dateOf(end);
        _endTime = TimeOfDay.fromDateTime(end);
      }
    });
  }

  Future<DateTime?> _pickDay(DateTime day) => showDatePicker(
    context: context,
    initialDate: day,
    firstDate: DateTime(day.year - 1),
    lastDate: DateTime(day.year + 2),
  );

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty || !_valid) return;
    Navigator.pop(
      context,
      _EditResult(
        event: CalendarEvent(
          id: widget.event?.id,
          title: title,
          start: _start,
          end: _end,
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.s, 0),
          child: Row(
            children: [
              Expanded(child: Text(widget.event == null ? l10n.calNewEvent : l10n.calEditEvent, style: AppText.title3)),
              SecondaryButton(
                label: l10n.save,
                onPressed: _title.text.trim().isEmpty || !_valid ? null : _save,
              ),
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
                  _WhenRow(
                    title: l10n.calStart,
                    thisYear: widget.thisYear,
                    day: _startDay,
                    time: _allDay ? null : _startTime,
                    onDay: () async {
                      final d = await _pickDay(_startDay);
                      if (d != null) _moveStart(d, _startTime);
                    },
                    onTime: () async {
                      final t = await showTimePicker(context: context, initialTime: _startTime);
                      if (t != null) _moveStart(_startDay, t);
                    },
                  ),
                  _WhenRow(
                    title: l10n.calEnd,
                    thisYear: widget.thisYear,
                    day: _endDay,
                    time: _allDay ? null : _endTime,
                    wrong: !_valid,
                    onDay: () async {
                      final d = await _pickDay(_endDay);
                      if (d != null) setState(() => _endDay = d);
                    },
                    onTime: () async {
                      final t = await showTimePicker(context: context, initialTime: _endTime);
                      if (t != null) setState(() => _endTime = t);
                    },
                  ),
                ],
              ),
              if (!_valid)
                Padding(
                  // In line with the rows above.
                  padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  child: Text(
                    l10n.calEndBeforeStart,
                    style: AppText.footnote.copyWith(color: AppColors.of(context).destructive),
                  ),
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

/// 開始 or 結束: its day, and its time unless the event is all day, each
/// tapped to change. [wrong] marks an end that is not after the start.
class _WhenRow extends StatelessWidget {
  const _WhenRow({
    required this.title,
    required this.thisYear,
    required this.day,
    required this.time,
    required this.onDay,
    required this.onTime,
    this.wrong = false,
  });

  final String title;
  final int thisYear;
  final DateTime day;
  final TimeOfDay? time;
  final VoidCallback onDay;
  final VoidCallback onTime;
  final bool wrong;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = AppText.body.copyWith(
      color: wrong ? c.destructive : c.label,
      decoration: wrong ? TextDecoration.lineThrough : null,
    );
    final date = (day.year == thisYear ? DateFormat.MMMEd('zh_TW') : DateFormat.yMMMEd('zh_TW')).format(day);
    Widget chip(String text, VoidCallback onTap) => Material(
      color: c.fill,
      borderRadius: BorderRadius.circular(Radii.s),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.s),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: Space.minTap(Theme.of(context).platform)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s),
            child: Center(widthFactor: 1, child: Text(text, style: style)),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
      child: Row(
        children: [
          Text(title, style: AppText.body),
          const SizedBox(width: Space.s),
          // With large text the time goes under the day.
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [chip(date, onDay), if (time != null) chip(time!.format(context), onTime)],
            ),
          ),
        ],
      ),
    );
  }
}
