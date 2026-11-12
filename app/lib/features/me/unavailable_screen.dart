import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../rosters/format.dart';
import '../rosters/rosters_screen.dart' show selectedServiceProvider;
import '../rosters/swap_asking.dart';
import '../../state/session.dart';

/// How many months from this one the page lays out.
const _months = 12;

/// 不能服事的日子 (#91): the days I cannot serve, whole days in every
/// service, a month at a time over the next [_months]. A tap marks a day or
/// clears it; a drag marks the days it crosses, or clears them when it
/// starts on a marked one. Each change shows at once and is kept in turn. Only those who arrange rosters see them,
/// with what I wrote about each stretch.
class UnavailableScreen extends ConsumerStatefulWidget {
  const UnavailableScreen({super.key});

  @override
  ConsumerState<UnavailableScreen> createState() => _UnavailableScreenState();
}

class _UnavailableScreenState extends ConsumerState<UnavailableScreen> {
  /// What was last changed here, shown until the backend's days are the
  /// same: they come back after the save, sometimes well after.
  UnavailableDays? _shown;

  /// The save on its way, if any. The next waits for it, so they land in
  /// order, and one overtaken while waiting is left to the next.
  Future<void>? _writing;

  /// Which month shows: this one, or so many after it.
  var _page = 0;

  UnavailableDays get _days => _shown ?? ref.read(myUnavailableDaysProvider).value ?? const UnavailableDays();

  /// Keeps [next] (what is past dropped), showing it at once; put back as
  /// the backend has it when it is refused.
  Future<bool> _save(UnavailableDays next) async {
    final l10n = L10n.of(context);
    final data = ref.churchData;
    final telemetry = ref.read(telemetryProvider);
    final kept = next.since(ref.read(todayProvider));
    setState(() => _shown = kept);
    final before = _writing;
    final done = Completer<void>();
    _writing = done.future;
    try {
      await before;
      if (!identical(_shown, kept)) return true;
      await data.saveMyUnavailableDays(kept);
      telemetry.logEvent('unavailable_set');
      return true;
    } catch (e) {
      if (mounted) {
        showToast(context, errorText(l10n, e));
        if (identical(_shown, kept)) setState(() => _shown = null);
      }
      return false;
    } finally {
      done.complete();
      if (identical(_writing, done.future)) _writing = null;
      _settle();
    }
  }

  /// Back to the backend's days once nothing is on its way and they are
  /// what was last shown.
  void _settle() {
    final shown = _shown;
    if (!mounted || shown == null || _writing != null) return;
    if (ref.read(myUnavailableDaysProvider).value?.since(ref.read(todayProvider)) == shown) {
      setState(() => _shown = null);
    }
  }

  void _toggle(Day day) {
    Haptics.selection();
    final days = _days;
    _save(days.on(day) == null ? days.add(day, day) : days.without(day));
  }

  void _drag(Day from, Day to, {required bool clear}) {
    Haptics.success();
    _save(clear ? _days.without(from, to) : _days.add(from, to));
  }

  Future<void> _note(UnavailableSpan span) async {
    final l10n = L10n.of(context);
    final note = await promptText(
      context,
      title: _spanLabel(span, ref.read(todayProvider)),
      label: l10n.unavailableNote,
      hint: l10n.unavailableNoteHint,
      initial: span.note,
      maxLength: TextLimits.unavailableNote,
      optional: true,
    );
    if (note == null || note.trim() == span.note || !mounted) return;
    await _save(_days.noted(span, note));
  }

  Future<void> _remove(UnavailableSpan span) async {
    final l10n = L10n.of(context);
    final before = _days;
    if (!await _save(before.remove(span)) || !mounted) return;
    showToast(context, l10n.removed(_spanLabel(span, ref.read(todayProvider))), onUndo: () => _save(before));
  }

  /// 「11月16日 週日」, or 「12月20日 – 12月27日」, with the year when it is
  /// not this one.
  String _spanLabel(UnavailableSpan span, Day today) {
    String day(Day d, DateFormat Function() f) => f().format(d.midnight);
    final thisYear = span.to.year == today.year;
    if (span.from == span.to) return day(span.from, thisYear ? DateFormat.MMMEd : DateFormat.yMMMEd);
    final f = thisYear ? DateFormat.MMMd : DateFormat.yMMMd;
    return '${day(span.from, f)} – ${day(span.to, f)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final today = ref.watch(todayProvider);
    final saved = ref.watch(myUnavailableDaysProvider);
    final days = (_shown ?? saved.value ?? const UnavailableDays()).since(today);
    final serving = [
      for (final s in ref.watch(myServicesProvider).value ?? const <MyService>[])
        if (days.during(s.roster.day, s.roster.lastDay) != null && !s.roster.lastDay.isBefore(today)) s,
    ];
    final services = ref.watch(servicesProvider).value;
    ref.listen(myUnavailableDaysProvider, (_, _) => _settle());
    // What 找人代 says of a day already asked about (#92).
    ref.watch(myOpenSwapRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.unavailableTitle)),
      body: saved.hasError && saved.value == null
          ? EmptyState(
              message: errorText(l10n, saved.error!),
              actionLabel: l10n.retry,
              onAction: () => ref.invalidate(myUnavailableDaysProvider),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.xl),
              children: [
                _Month(
                  month: Day(today.year, today.month + _page, 1),
                  today: today,
                  days: days,
                  onTap: _toggle,
                  onDrag: _drag,
                  onShift: (by) => setState(() => _page = (_page + by).clamp(0, _months - 1).toInt()),
                  first: _page == 0,
                  last: _page == _months - 1,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
                  child: Text(
                    l10n.unavailableHint,
                    style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
                  ),
                ),
                if (serving.isNotEmpty)
                  ListSection(
                    header: l10n.unavailableServing,
                    footer: l10n.unavailableServingFooter,
                    children: [
                      for (final s in serving)
                        for (final duty in s.roster.isEvent ? [s.duties.join(l10n.listSeparator)] : s.duties)
                          ListRow(
                            title: '${s.roster.forEvent?.title ?? services?.byId(s.roster.type)?.name ?? ''} $duty',
                            subtitle: dayLabel(l10n, s.roster.day, today),
                            // 找人代 for it, as on the roster (#92); an event's roster is the leads'.
                            trailing: s.roster.isEvent
                                ? null
                                : RowButton(
                                    label: l10n.swapMenu,
                                    onPressed: () => showMyDutyMenu(context, ref, s.roster, duty),
                                  ),
                            onTap: () {
                              if (s.roster.forEvent case final e?) {
                                context.push('/rosters/event/${e.eventId}');
                                return;
                              }
                              ref.read(selectedServiceProvider.notifier).select(s.roster.type);
                              context.push('/rosters/${s.roster.type}/${s.roster.day.key}');
                            },
                          ),
                    ],
                  ),
                if (!days.isEmpty)
                  ListSection(
                    header: l10n.unavailableMarked,
                    footer: l10n.unavailableNoteFooter,
                    children: [
                      for (final span in days.spans)
                        ListRow(
                          title: _spanLabel(span, today),
                          subtitle: span.note.isEmpty ? null : span.note,
                          chevron: false,
                          trailing: RowButton(
                            label: l10n.remove,
                            semanticsLabel: '${l10n.remove} ${_spanLabel(span, today)}',
                            onPressed: () => _remove(span),
                          ),
                          onTap: () => _note(span),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// One month of days to mark, with arrows to the others: a tap marks or
/// clears a day; a finger dragged marks the days it passes over in this
/// month, or clears them when it starts on a marked day. The days take the
/// finger at once, so the page does not scroll from them; a tap is one day
/// dragged over. Days gone by are only shown. One month at a time, above what it
/// lists: a list growing above the days would move them under the finger.
class _Month extends StatefulWidget {
  const _Month({
    required this.month,
    required this.today,
    required this.days,
    required this.onTap,
    required this.onDrag,
    required this.onShift,
    required this.first,
    required this.last,
  });

  /// Its first day.
  final Day month;
  final Day today;
  final UnavailableDays days;
  final ValueChanged<Day> onTap;

  /// [from] to [to] dragged over: to clear when it started on a marked day.
  final void Function(Day from, Day to, {required bool clear}) onDrag;

  /// To the month before (-1) or after (1); none before [first] or after
  /// [last].
  final ValueChanged<int> onShift;
  final bool first;
  final bool last;

  @override
  State<_Month> createState() => _MonthState();
}

class _MonthState extends State<_Month> {
  /// Where the finger started and where it is now, and whether it clears.
  Day? _from;
  Day? _to;
  var _clearing = false;

  bool _marking(Day day) {
    final (from, to) = (_from, _to);
    if (from == null || to == null) return false;
    final (a, b) = from.isAfter(to) ? (to, from) : (from, to);
    return !day.isBefore(a) && !b.isBefore(day);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final material = MaterialLocalizations.of(context);
    final c = AppColors.of(context);
    final firstWeekday = material.firstDayOfWeekIndex; // 0 = Sunday
    final month = widget.month;
    // The day in the first column of the first week.
    final start = month.addDays(-((month.weekday % 7 - firstWeekday + 7) % 7));
    final weeks = ((start.daysUntil(month.lastOfMonth) + 1) / 7).ceil();
    final rowHeight = Space.minTap(Theme.of(context).platform);

    Day? dayAt(Offset at, double width) {
      if (at.dx < 0 || at.dy < 0 || at.dx >= width || at.dy >= weeks * rowHeight) return null;
      final day = start.addDays((at.dy ~/ rowHeight) * 7 + (at.dx ~/ (width / 7)));
      return day.month == month.month && !day.isBefore(widget.today) ? day : null;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: l10n.calPrevMonth,
                icon: const Icon(Symbols.chevron_left_rounded),
                onPressed: widget.first ? null : () => widget.onShift(-1),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    DateFormat.yMMMM().format(month.midnight),
                    textAlign: TextAlign.center,
                    style: AppText.headline,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.calNextMonth,
                icon: const Icon(Symbols.chevron_right_rounded),
                onPressed: widget.last ? null : () => widget.onShift(1),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Text(
                      material.narrowWeekdays[(firstWeekday + i) % 7],
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(color: c.secondaryLabel),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return RawGestureDetector(
                gestures: {
                  _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(_EagerPan.new, (pan) {
                    pan
                      ..onStart = (d) {
                        final day = dayAt(d.localPosition, width);
                        if (day == null) return;
                        setState(() {
                          _from = _to = day;
                          _clearing = widget.days.on(day) != null;
                        });
                      }
                      ..onUpdate = (d) {
                        final day = dayAt(d.localPosition, width);
                        if (_from == null || day == null || day == _to) return;
                        Haptics.selection();
                        setState(() => _to = day);
                      }
                      ..onEnd = (_) {
                        final (from, to, clear) = (_from, _to, _clearing);
                        setState(() => _from = _to = null);
                        if (from == null || to == null) return;
                        from == to ? widget.onTap(from) : widget.onDrag(from, to, clear: clear);
                      }
                      ..onCancel = () => setState(() => _from = _to = null);
                  }),
                },
                child: Column(
                  children: [
                    for (var w = 0; w < weeks; w++)
                      SizedBox(
                        height: rowHeight,
                        child: Row(
                          children: [
                            for (var d = 0; d < 7; d++)
                              Expanded(child: _cell(context, l10n, c, start.addDays(w * 7 + d), column: d)),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, L10n l10n, AppColors c, Day day, {required int column}) {
    if (day.month != widget.month.month) return const SizedBox.shrink();
    final past = day.isBefore(widget.today);
    bool on(Day d) => d.month == day.month && (_marking(d) ? !_clearing : widget.days.on(d) != null);
    final marked = !past && on(day);
    // A stretch reads as one band: round only where it starts and ends.
    final joinsBefore = marked && column > 0 && on(day.addDays(-1));
    final joinsAfter = marked && column < 6 && on(day.addDays(1));
    const r = Radius.circular(Radii.m);
    return Semantics(
      button: !past,
      selected: marked,
      label: DateFormat.yMMMMEEEEd().format(day.midnight),
      onTap: past ? null : () => widget.onTap(day),
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: marked
            ? BoxDecoration(
                color: _marking(day) ? c.accentSoft.withValues(alpha: 0.6) : c.accentSoft,
                borderRadius: BorderRadius.horizontal(
                  left: joinsBefore ? Radius.zero : r,
                  right: joinsAfter ? Radius.zero : r,
                ),
              )
            : null,
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: AppText.subheadline.copyWith(
            color: past ? c.tertiaryLabel : (marked ? c.accent : c.label),
            fontWeight: day == widget.today || marked ? FontWeight.w600 : null,
          ),
        ),
      ),
    );
  }
}

/// A drag that takes the pointer as soon as it is down: the page around
/// would otherwise take a drag down the month as a scroll.
class _EagerPan extends PanGestureRecognizer {
  _EagerPan() {
    dragStartBehavior = DragStartBehavior.down;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
