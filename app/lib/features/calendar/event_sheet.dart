import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart' show WarmUp;
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/calendar.dart';
import '../../state/providers.dart';
import '../common/time_zones.dart';
import '../rosters/event_roster_screen.dart';

/// Read-only details, for people who cannot edit the calendar, with the
/// event's roster.
Future<void> showEventDetail(BuildContext context, CalendarEvent e) {
  final l10n = L10n.of(context);
  final screen = context;
  final fmt = DateFormat.MMMEd();
  final time = DateFormat.Hm();
  return showAppSheet<void>(
    context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
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
                    _ when e.allDay => '${fmt.format(e.start)} – ${fmt.format(e.lastDay.midnight)}',
                    _ when e.lastDay == e.day => '${fmt.format(e.start)} ${time.format(e.start)}–${time.format(e.end)}',
                    _ => '${fmt.format(e.start)} ${time.format(e.start)} – ${fmt.format(e.end)} ${time.format(e.end)}',
                  },
                  style: AppText.body,
                ),
                if (!e.allDay) const ChurchClockNotice(padding: EdgeInsets.only(top: Space.xs)),
                // A group's event says whose it is (#84); one of a group
                // since deleted, nothing.
                if (e.group != null)
                  Consumer(
                    builder: (context, ref, _) => switch (eventGroupName(ref, e.group!)) {
                      final name? => Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(
                          l10n.eventOfGroup(name),
                          style: AppText.body.copyWith(color: AppColors.of(context).secondaryLabel),
                        ),
                      ),
                      null => const SizedBox.shrink(),
                    },
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
          EventRosterRow(
            event: e,
            onOpen: () {
              Navigator.pop(context);
              openEventRoster(screen, e);
            },
          ),
        ],
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
  // Saving goes through the backend; start it while the editor is open.
  ref.read(backendProvider).warmUp(WarmUp.calendarWrite);
  final l10n = L10n.of(context);
  final today = ref.read(todayProvider);
  final initialDay =
      event?.start ??
      (day != null
          ? day.midnight
          : month.year == today.year && month.month == today.month
          ? today.midnight
          : month);
  var previous = event;
  final groups = eventGroupChoices(ref, l10n);
  final group = event == null ? groups.firstOrNull?.key : event.group;
  var result = await showAppSheet<_EditResult>(
    context,
    expand: true,
    builder: (_) => _EventEditor(
      event: event,
      initialDay: initialDay,
      thisYear: today.year,
      groups: groups,
      initialGroup: group,
    ),
  );
  if (result?.duplicate == true && context.mounted) {
    // A copy is a new draft, not a write to the original or its roster.
    previous = null;
    final draft = result!.event!;
    result = await showAppSheet<_EditResult>(
      context,
      expand: true,
      builder: (_) => _EventEditor(
        event: draft,
        initialDay: draft.start,
        thisYear: today.year,
        groups: groups,
        initialGroup: draft.group,
      ),
    );
  }
  if (result == null || !context.mounted) return;
  final calendar = ref.read(calendarActionsProvider);
  try {
    if (result.openRoster && event != null) {
      // Saved first: going to the roster keeps what was changed here.
      final edited = result.event;
      if (edited != null) await calendar.save(edited, previous: event);
      if (context.mounted) openEventRoster(context, edited ?? event);
    } else if (result.delete && event != null) {
      final undo = await calendar.delete(event);
      if (!context.mounted) return;
      showToast(context, l10n.calDeleted(event.title), onUndo: undo);
    } else if (result.event != null) {
      await calendar.save(result.event!, previous: previous);
      if (context.mounted) showToast(context, l10n.calSaved);
    }
  } catch (_) {
    if (context.mounted) showToast(context, l10n.saveFailed);
  }
}

/// Whose I may make an event (#84): admins and 行政 the church's or any
/// group's, the church's first; a 負責人 only their groups'.
List<EventGroupChoice> eventGroupChoices(WidgetRef ref, L10n l10n) {
  final me = ref.read(meProvider).value;
  if (me == null) return const [];
  final services = ref.read(servicesProvider).value?.enabled ?? const <Service>[];
  final ministries = ref.read(ministriesProvider).value?.ministries ?? const <Ministry>[];
  final smallGroups = ref.read(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
  return [
    if (me.mayWriteEvent(null, '')) (key: null, label: l10n.wholeChurch),
    for (final (key, label) in [
      for (final s in services) (ServiceGroup(s.id).key, s.name),
      for (final m in ministries) (MinistryGroup(m.id).key, m.name),
      for (final g in smallGroups) (g.group.key, g.name),
    ])
      if (me.mayWriteEvent(null, key)) (key: key, label: label),
  ];
}

/// The name of the group whose event this is ([ChurchGroup.key]), or null
/// for one no longer there.
String? eventGroupName(WidgetRef ref, String group) => switch (ChurchGroup.parse(group)) {
  ServiceGroup(:final id) => ref.watch(servicesProvider).value?.byId(id)?.name,
  MinistryGroup(:final id) => ref.watch(ministriesProvider).value?.byId(id)?.name,
  SmallGroup(:final id) => ref.watch(smallGroupsProvider).value?.byId(id)?.name,
  null => null,
};

class _EditResult {
  const _EditResult({this.event, this.delete = false, this.openRoster = false, this.duplicate = false});

  final CalendarEvent? event;
  final bool delete;
  final bool duplicate;

  /// Leave the editor for the event's roster, saving [event] first when
  /// it was changed.
  final bool openRoster;
}

/// Whose an event may be, for its editor: the church's (key null) and the
/// groups the person may give it to, each with its name.
typedef EventGroupChoice = ({String? key, String label});

class _EventEditor extends StatefulWidget {
  const _EventEditor({
    required this.event,
    required this.initialDay,
    required this.thisYear,
    required this.groups,
    required this.initialGroup,
  });

  final CalendarEvent? event;
  final DateTime initialDay;

  /// Whose it may be (#84); the row shows only with a choice to make.
  final List<EventGroupChoice> groups;
  final String? initialGroup;

  /// Dates in this year are shown without it.
  final int thisYear;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _location = TextEditingController(text: widget.event?.location ?? '');
  late final _description = TextEditingController(text: widget.event?.description ?? '');
  late bool _allDay = widget.event?.allDay ?? false;
  late String? _group = widget.initialGroup;

  // The first and last day, both included, and the times when not all day.
  // An all-day event keeps the usual times for when it is switched to one
  // with times.
  late DateTime _startDay = _dateOf(widget.event?.start ?? widget.initialDay);
  late DateTime _endDay = switch (widget.event) {
    null => _startDay,
    final e when e.allDay => e.lastDay.midnight,
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
    _description.dispose();
    super.dispose();
  }

  static DateTime _dateOf(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static DateTime _at(DateTime day, TimeOfDay t) => DateTime.utc(day.year, day.month, day.day, t.hour, t.minute);

  DateTime get _start => _allDay ? _startDay : _at(_startDay, _startTime);

  /// Exclusive, as the calendar keeps it: the day after the last for an
  /// all-day event.
  DateTime get _end => _allDay ? DateTime.utc(_endDay.year, _endDay.month, _endDay.day + 1) : _at(_endDay, _endTime);

  /// Always true from the pickers, which offer no end before the start;
  /// kept as a guard for saving.
  bool get _valid => _end.isAfter(_start);

  /// Moves the start; the end moves with it, so the event keeps its length.
  void _moveStart(DateTime day, TimeOfDay time) {
    final days = _endDay.difference(_startDay).inDays;
    final length = _at(_endDay, _endTime).difference(_at(_startDay, _startTime));
    setState(() {
      _startDay = _dateOf(day);
      _startTime = time;
      if (_allDay) {
        _endDay = DateTime.utc(day.year, day.month, day.day + (days < 0 ? 0 : days));
      } else {
        final end = _at(day, time).add(length > Duration.zero ? length : const Duration(hours: 1));
        _endDay = _dateOf(end);
        _endTime = TimeOfDay.fromDateTime(end);
      }
    });
  }

  Future<DateTime?> _pickDay(DateTime day, {DateTime? notBefore}) => showDatePicker(
    context: context,
    initialDate: day,
    firstDate: notBefore ?? DateTime.utc(day.year - 1),
    lastDate: DateTime.utc(day.year + 2),
    // Typing a date takes it as 10/18/2026 in English, which reads the
    // other way in Malaysia: the calendar only.
    initialEntryMode: DatePickerEntryMode.calendarOnly,
  );

  /// Moves the end to [day]. On the start day an end time not after the
  /// start becomes an hour after it.
  void _moveEndDay(DateTime day) => setState(() {
    _endDay = _dateOf(day);
    if (!_allDay && !_at(day, _endTime).isAfter(_start)) {
      final end = _start.add(const Duration(hours: 1));
      _endDay = _dateOf(end);
      _endTime = TimeOfDay.fromDateTime(end);
    }
  });

  /// Sets the end time. One not after the start, which only 其他時間 can
  /// give, means the next day: the end day moves there, in sight.
  void _setEndTime(TimeOfDay t) => setState(() {
    _endTime = t;
    if (!_at(_endDay, t).isAfter(_start)) _endDay = DateTime.utc(_startDay.year, _startDay.month, _startDay.day + 1);
  });

  /// The event as edited.
  CalendarEvent get _edited => CalendarEvent(
    id: widget.event?.id,
    title: _title.text.trim(),
    start: _start,
    end: _end,
    allDay: _allDay,
    location: _location.text.trim().isEmpty ? null : _location.text.trim(),
    description: _description.text.trim(),
    recurringEventId: widget.event?.recurringEventId,
    originalStart: widget.event?.originalStart,
    group: _group,
  );

  void _save() {
    if (_title.text.trim().isEmpty || !_valid) return;
    Navigator.pop(context, _EditResult(event: _edited));
  }

  /// To the roster, with what was changed here unless it cannot be saved.
  void _openRoster() {
    final e = widget.event!;
    final edited = _edited;
    final changed =
        edited.title != e.title ||
        edited.start != e.start ||
        edited.end != e.end ||
        edited.allDay != e.allDay ||
        (edited.location ?? '') != (e.location ?? '') ||
        (edited.description ?? '') != (e.description ?? '') ||
        edited.group != e.group;
    final ok = edited.title.isNotEmpty && _valid;
    Navigator.pop(context, _EditResult(event: changed && ok ? edited : null, openRoster: true));
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
              Expanded(
                child: Text(widget.event?.id == null ? l10n.calNewEvent : l10n.calEditEvent, style: AppText.title3),
              ),
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
                  autofocus: widget.event?.id == null,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                child: TextField(
                  controller: _description,
                  decoration: InputDecoration(hintText: l10n.calDescription),
                  keyboardType: TextInputType.multiline,
                  minLines: 2,
                  maxLines: 6,
                ),
              ),
              if (widget.groups.length > 1)
                ListSection(
                  children: [
                    ListRow(
                      title: l10n.eventGroup,
                      value: widget.groups.where((g) => g.key == _group).firstOrNull?.label,
                      onTap: () async {
                        final picked = await showAppSheet<EventGroupChoice>(
                          context,
                          builder: (context) => SafeArea(
                            child: SingleChildScrollView(
                              child: ListSection(
                                header: l10n.eventGroup,
                                children: [
                                  for (final g in widget.groups)
                                    ListRow(
                                      title: g.label,
                                      selected: g.key == _group,
                                      onTap: () => Navigator.pop(context, g),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                        if (picked != null) setState(() => _group = picked.key);
                      },
                    ),
                  ],
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
                    onDay: () async {
                      final d = await _pickDay(_endDay, notBefore: _startDay);
                      if (d != null) _moveEndDay(d);
                    },
                    onTime: () async {
                      final t = await showAppSheet<TimeOfDay>(
                        context,
                        builder: (_) => _EndTimeSheet(
                          start: _start,
                          endDay: _endDay,
                          selected: _endTime,
                        ),
                      );
                      if (t != null) _setEndTime(t);
                    },
                  ),
                ],
              ),
              if (!_allDay) const ChurchClockNotice(),
              if (widget.event case final e? when e.id != null) EventRosterRow(event: e, onOpen: _openRoster),
              if (widget.event?.id != null)
                ListSection(
                  children: [
                    ListRow(
                      title: l10n.calDuplicate,
                      onTap: _title.text.trim().isEmpty || !_valid
                          ? null
                          : () => Navigator.pop(context, _EditResult(event: _edited.anew, duplicate: true)),
                    ),
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
/// tapped to change.
class _WhenRow extends StatelessWidget {
  const _WhenRow({
    required this.title,
    required this.thisYear,
    required this.day,
    required this.time,
    required this.onDay,
    required this.onTime,
  });

  final String title;
  final int thisYear;
  final DateTime day;
  final TimeOfDay? time;
  final VoidCallback onDay;
  final VoidCallback onTime;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = AppText.body.copyWith(color: c.label);
    final date = (day.year == thisYear ? DateFormat.MMMEd() : DateFormat.yMMMEd()).format(day);
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

/// The end time, in steps of 15 minutes (and the one set now, when off
/// them): on the start day only times after the start, each with how long
/// the event would be. 其他時間 opens the clock for any minute.
class _EndTimeSheet extends StatefulWidget {
  const _EndTimeSheet({required this.start, required this.endDay, required this.selected});

  final DateTime start;
  final DateTime endDay;
  final TimeOfDay selected;

  @override
  State<_EndTimeSheet> createState() => _EndTimeSheetState();
}

class _EndTimeSheetState extends State<_EndTimeSheet> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _selectedKey.currentContext;
      if (row != null) Scrollable.ensureVisible(row, alignment: 0.3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final s = widget.start;
    final d = widget.endDay;
    final sameDay = d.year == s.year && d.month == s.month && d.day == s.day;
    // On the start day the steps count from the start; on a later day, from
    // midnight.
    final times = <DateTime>[
      for (
        var t = sameDay ? s.add(const Duration(minutes: 15)) : DateTime.utc(d.year, d.month, d.day);
        t.day == d.day && t.month == d.month && t.year == d.year;
        t = t.add(const Duration(minutes: 15))
      )
        t,
    ];
    final current = DateTime.utc(d.year, d.month, d.day, widget.selected.hour, widget.selected.minute);
    if (current.isAfter(s) && !times.contains(current)) times.add(current);
    times.sort();
    String length(Duration x) {
      final h = x.inHours;
      final m = x.inMinutes % 60;
      return h == 0
          ? l10n.calLengthMinutes(m)
          : m == 0
          ? l10n.calLengthHours(h)
          : l10n.calLengthHoursMinutes(h, m);
    }

    // 其他時間 stays in sight above the list, which scrolls to the time set.
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            ListSection(
              header: l10n.calEnd,
              children: [
                ListRow(
                  title: l10n.calOtherTime,
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: widget.selected);
                    if (t != null && context.mounted) Navigator.pop(context, t);
                  },
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: ListSection(
                  children: [
                    for (final t in times)
                      ListRow(
                        key: t.hour == widget.selected.hour && t.minute == widget.selected.minute ? _selectedKey : null,
                        title: TimeOfDay.fromDateTime(t).format(context),
                        subtitle: sameDay ? length(t.difference(s)) : null,
                        selected: t.hour == widget.selected.hour && t.minute == widget.selected.minute,
                        onTap: () => Navigator.pop(context, TimeOfDay.fromDateTime(t)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
