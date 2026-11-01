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

/// How many months from this one the page lays out.
const _months = 12;

/// 不能服事的日子 (#91): the days I cannot serve, whole days in every
/// service, a month at a time over the next [_months]. A tap marks a day or
/// clears it; held and dragged, a stretch.
/// Each change is kept at once. Only those who arrange rosters see them,
/// with what I wrote about each stretch.
class UnavailableScreen extends ConsumerStatefulWidget {
  const UnavailableScreen({super.key});

  @override
  ConsumerState<UnavailableScreen> createState() => _UnavailableScreenState();
}

class _UnavailableScreenState extends ConsumerState<UnavailableScreen> {
  /// What was last changed here, shown before the backend has it; null
  /// once it does.
  UnavailableDays? _shown;

  /// Which month shows: this one, or so many after it.
  var _page = 0;

  UnavailableDays get _days => _shown ?? ref.read(myUnavailableDaysProvider).value ?? const UnavailableDays();

  /// Keeps [next] (what is past dropped), showing it at once; put back as
  /// it was when it is refused.
  Future<bool> _save(UnavailableDays next) async {
    final l10n = L10n.of(context);
    final kept = next.since(ref.read(todayProvider));
    setState(() => _shown = kept);
    try {
      await ref.churchData.saveMyUnavailableDays(kept);
      return true;
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
      return false;
    } finally {
      if (mounted && identical(_shown, kept)) setState(() => _shown = null);
    }
  }

  void _toggle(Day day) {
    Haptics.selection();
    final days = _days;
    _save(days.on(day) == null ? days.add(day, day) : days.without(day));
  }

  void _mark(Day from, Day to) {
    Haptics.success();
    _save(_days.add(from, to));
  }

  /// 加一段期間: the first day and the last, without dragging.
  Future<void> _addRange(Day today) async {
    final l10n = L10n.of(context);
    final last = Day(today.year, today.month + _months, 1).addDays(-1);
    final first = await pickDay(
      context,
      title: l10n.unavailableFirstDay,
      initial: today.midnight,
      first: today.midnight,
      last: last.midnight,
    );
    if (first == null || !mounted) return;
    final from = Day(first.year, first.month, first.day);
    final end = await pickDay(
      context,
      title: l10n.unavailableLastDay,
      initial: first,
      first: first,
      last: last.midnight,
    );
    if (end == null || !mounted) return;
    _mark(from, Day(end.year, end.month, end.day));
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
                  onMark: _mark,
                  onShift: (by) => setState(() => _page = (_page + by).clamp(0, _months - 1).toInt()),
                  first: _page == 0,
                  last: _page == _months - 1,
                ),
                ListSection(
                  footer: l10n.unavailableHint,
                  children: [
                    ListRow(
                      leading: const Icon(Symbols.date_range_rounded),
                      title: l10n.unavailableAddRange,
                      onTap: () => _addRange(today),
                    ),
                  ],
                ),
                if (serving.isNotEmpty)
                  ListSection(
                    header: l10n.unavailableServing,
                    footer: l10n.unavailableServingFooter,
                    children: [
                      for (final s in serving)
                        ListRow(
                          title:
                              '${s.roster.forEvent?.title ?? services?.byId(s.roster.type)?.name ?? ''} '
                              '${s.duties.join(l10n.listSeparator)}',
                          value: dayLabel(l10n, s.roster.day, today),
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
/// clears a day; held, the finger marks the days it passes over, in this
/// month. Days gone by are only shown. One month at a time, above what it
/// lists: a list growing above the days would move them under the finger.
class _Month extends StatefulWidget {
  const _Month({
    required this.month,
    required this.today,
    required this.days,
    required this.onTap,
    required this.onMark,
    required this.onShift,
    required this.first,
    required this.last,
  });

  /// Its first day.
  final Day month;
  final Day today;
  final UnavailableDays days;
  final ValueChanged<Day> onTap;
  final void Function(Day from, Day to) onMark;

  /// To the month before (-1) or after (1); none before [first] or after
  /// [last].
  final ValueChanged<int> onShift;
  final bool first;
  final bool last;

  @override
  State<_Month> createState() => _MonthState();
}

class _MonthState extends State<_Month> {
  /// Where a held finger started and where it is now.
  Day? _from;
  Day? _to;

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
              return GestureDetector(
                onTapUp: (d) {
                  if (dayAt(d.localPosition, width) case final day?) widget.onTap(day);
                },
                onLongPressStart: (d) {
                  final day = dayAt(d.localPosition, width);
                  if (day == null) return;
                  Haptics.selection();
                  setState(() => _from = _to = day);
                },
                onLongPressMoveUpdate: (d) {
                  final day = dayAt(d.localPosition, width);
                  if (day == null || day == _to) return;
                  Haptics.selection();
                  setState(() => _to = day);
                },
                onLongPressEnd: (_) {
                  final (from, to) = (_from, _to);
                  setState(() => _from = _to = null);
                  if (from != null && to != null) widget.onMark(from, to);
                },
                onLongPressCancel: () => setState(() => _from = _to = null),
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
    bool on(Day d) => d.month == day.month && (widget.days.on(d) != null || _marking(d));
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
