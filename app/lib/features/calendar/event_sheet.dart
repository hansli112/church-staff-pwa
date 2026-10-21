import 'package:flutter/cupertino.dart';
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

  /// The picker open under 開始 or 結束, at most one, as in the iPhone's
  /// Calendar: it opens in place, with the keyboard put away.
  _Picker? _open;

  /// One key each: one shared would carry a picker's turned wheels over to
  /// the next one opened.
  final _pickerKeys = {for (final p in _Picker.values) p: GlobalKey()};

  /// Whether the event was under a day long when the end's wheels opened:
  /// then the end time picks its day by the start. Decided once, so turning
  /// a two-day event's end past the start's time does not cut it to one.
  bool _endWithinDay = true;

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

  /// Opens [picker], or closes it when open. The keyboard goes, so the
  /// picker and the rows below it stay in sight.
  void _toggle(_Picker picker) {
    FocusScope.of(context).unfocus();
    setState(() {
      _open = _open == picker ? null : picker;
      if (_open == _Picker.endTime) _endWithinDay = _end.difference(_start) < const Duration(days: 1);
    });
    // Scrolled up into sight when it opens below the fold.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final opened = _pickerKeys[_open]?.currentContext;
      if (opened == null || !mounted) return;
      Scrollable.ensureVisible(
        opened,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  /// A field being typed in closes the picker.
  void _closePicker() {
    if (_open != null) setState(() => _open = null);
  }

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

  /// Sets the end time. For an event under a day long, the end is the
  /// first such time after the start: the next day for one not after the
  /// start time, the start day again for one after it. A longer event keeps
  /// its end day.
  void _setEndTime(TimeOfDay t) => setState(() {
    _endTime = t;
    if (_endWithinDay) {
      _endDay = _at(_startDay, t).isAfter(_start)
          ? _startDay
          : DateTime.utc(_startDay.year, _startDay.month, _startDay.day + 1);
    }
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
                  onTap: _closePicker,
                  decoration: InputDecoration(hintText: l10n.calTitle),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m),
                child: TextField(
                  controller: _location,
                  onTap: _closePicker,
                  decoration: InputDecoration(hintText: l10n.calLocation),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                child: TextField(
                  controller: _description,
                  onTap: _closePicker,
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
                  SwitchRow(
                    title: l10n.calAllDay,
                    value: _allDay,
                    onChanged: (v) => setState(() {
                      _allDay = v;
                      if (v && (_open == _Picker.startTime || _open == _Picker.endTime)) _open = null;
                    }),
                  ),
                  _WhenRow(
                    title: l10n.calStart,
                    thisYear: widget.thisYear,
                    day: _startDay,
                    time: _allDay ? null : _startTime,
                    dayOpen: _open == _Picker.startDay,
                    timeOpen: _open == _Picker.startTime,
                    onDay: () => _toggle(_Picker.startDay),
                    onTime: () => _toggle(_Picker.startTime),
                  ),
                  if (_open == _Picker.startDay)
                    _DayPicker(
                      opened: _pickerKeys[_Picker.startDay]!,
                      key: const ValueKey(_Picker.startDay),
                      day: _startDay,
                      first: DateTime.utc(_startDay.year - 1),
                      onPicked: (d) {
                        _moveStart(d, _startTime);
                        setState(() => _open = null);
                      },
                    ),
                  if (_open == _Picker.startTime)
                    _TimeWheels(
                      opened: _pickerKeys[_Picker.startTime]!,
                      key: const ValueKey(_Picker.startTime),
                      time: _startTime,
                      onChanged: (t) => _moveStart(_startDay, t),
                    ),
                  _WhenRow(
                    title: l10n.calEnd,
                    thisYear: widget.thisYear,
                    day: _endDay,
                    time: _allDay ? null : _endTime,
                    note: _allDay ? null : _length(l10n, _end.difference(_start)),
                    dayOpen: _open == _Picker.endDay,
                    timeOpen: _open == _Picker.endTime,
                    onDay: () => _toggle(_Picker.endDay),
                    onTime: () => _toggle(_Picker.endTime),
                  ),
                  if (_open == _Picker.endDay)
                    _DayPicker(
                      opened: _pickerKeys[_Picker.endDay]!,
                      key: const ValueKey(_Picker.endDay),
                      day: _endDay,
                      first: _startDay,
                      onPicked: (d) {
                        _moveEndDay(d);
                        setState(() => _open = null);
                      },
                    ),
                  if (_open == _Picker.endTime)
                    _TimeWheels(
                      opened: _pickerKeys[_Picker.endTime]!,
                      key: const ValueKey(_Picker.endTime),
                      time: _endTime,
                      onChanged: _setEndTime,
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
    required this.dayOpen,
    required this.timeOpen,
    required this.onDay,
    required this.onTime,
    this.note,
  });

  final String title;
  final int thisYear;
  final DateTime day;
  final TimeOfDay? time;

  /// Whose picker is open under the row: that one is in the accent color.
  final bool dayOpen;
  final bool timeOpen;
  final VoidCallback onDay;
  final VoidCallback onTime;

  /// Under the title: how long the event is, on 結束.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = AppText.body.copyWith(color: c.label);
    final date = (day.year == thisYear ? DateFormat.MMMEd() : DateFormat.yMMMEd()).format(day);
    Widget chip(String text, bool open, VoidCallback onTap) => Material(
      color: c.fill,
      borderRadius: BorderRadius.circular(Radii.s),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.s),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: Space.minTap(Theme.of(context).platform)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s),
            child: Center(
              widthFactor: 1,
              child: Text(text, style: open ? style.copyWith(color: c.accent) : style),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.body),
              if (note != null) Text(note!, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
            ],
          ),
          const SizedBox(width: Space.s),
          // With large text the time goes under the day.
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [chip(date, dayOpen, onDay), if (time != null) chip(time!.format(context), timeOpen, onTime)],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Picker { startDay, startTime, endDay, endTime }

/// How long an event is, on 結束.
String _length(L10n l10n, Duration x) {
  final h = x.inHours;
  final m = x.inMinutes % 60;
  return h == 0
      ? l10n.calLengthMinutes(m)
      : m == 0
      ? l10n.calLengthHours(h)
      : l10n.calLengthHoursMinutes(h, m);
}

/// A month to pick a day from, in place under its row: one tap picks it.
/// Typing a date is not offered: 10/18/2026 reads the other way in some
/// places.
class _DayPicker extends StatelessWidget {
  const _DayPicker({super.key, required this.opened, required this.day, required this.first, required this.onPicked});

  /// Where the editor finds the open picker, to scroll it into sight.
  final GlobalKey opened;
  final DateTime day;

  /// The first day that can be picked: for 結束, the start day.
  final DateTime first;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) => DayCalendar(
    key: opened,
    initial: day,
    first: first,
    last: DateTime.utc(day.year + 2, 12, 31),
    onPicked: onPicked,
  );
}

/// Wheels for the hour and minute, in place under their row, as on the
/// iPhone; the time changes as they turn. Minutes go in fives, unless the
/// time was between them when the wheels opened: decided once, as the wheel
/// keeps its place, not its minute, when the step changes.
class _TimeWheels extends StatefulWidget {
  const _TimeWheels({super.key, required this.opened, required this.time, required this.onChanged});

  /// Where the editor finds the open picker, to scroll it into sight.
  final GlobalKey opened;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  State<_TimeWheels> createState() => _TimeWheelsState();
}

class _TimeWheelsState extends State<_TimeWheels> {
  late final _step = widget.time.minute % 5 == 0 ? 5 : 1;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: widget.opened,
    // The iPhone's own wheels' height.
    height: 216,
    child: CupertinoDatePicker(
      mode: CupertinoDatePickerMode.time,
      initialDateTime: DateTime(2000, 1, 1, widget.time.hour, widget.time.minute),
      minuteInterval: _step,
      use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      onDateTimeChanged: (d) => widget.onChanged(TimeOfDay(hour: d.hour, minute: d.minute)),
    ),
  );
}
