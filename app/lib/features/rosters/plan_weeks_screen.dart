import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/plan_weeks.dart';
import '../../domain/roster_edit.dart';
import '../../domain/roster_news.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../common/errors.dart';
import '../common/saving_indicator.dart';
import 'duty_picking.dart';
import 'format.dart';

/// 安排服事 (#90): one service's days a month at a time, a row a day and a
/// column a duty I arrange. Tapping a cell picks its people as on the
/// day's page, saved with its 完成; tapping a date opens that day. A cell held
/// lifts, and dropped on another day of its duty trades the two (moves
/// them, onto a day with nobody); the picker's 和別週交換 does the same
/// without dragging. Nobody is told until 通知同工, which tells each
/// person once, for all their days.
/// Opens at the first month with a duty nobody is on yet; the months
/// before it are a button away, later ones join on as it scrolls.
class PlanWeeksScreen extends ConsumerStatefulWidget {
  const PlanWeeksScreen({super.key, required this.serviceType});

  /// The service it opens at, the one the 服事表 tab showed.
  final String serviceType;

  @override
  ConsumerState<PlanWeeksScreen> createState() => _PlanWeeksScreenState();
}

/// How many months the page shows at first, and adds as its end nears.
const _monthsAtATime = 3;

/// How far the months go on: through the same month next year.
const _monthsAhead = 13;

/// How far ahead the page looks for the first month with a gap.
const _gapSearchMonths = 12;

/// How fast the table scrolls while a lifted cell is held at its edge, per
/// point past it (as ReorderableList).
const _autoScrollSpeed = 50.0;

/// The narrowest a duty's column gets, and how much of the next one shows
/// when they do not all fit.
const _minCellWidth = 100.0;
const _peek = 0.4;

/// How long the cells a drop traded stay lit.
const _flashFor = Duration(milliseconds: 700);

class _PlanWeeksScreenState extends ConsumerState<PlanWeeksScreen> with SingleTickerProviderStateMixin {
  late String _type = widget.serviceType;

  /// The first month shown (its first day); null until the days are in.
  Day? _from;
  int _months = _monthsAtATime;
  bool _notifying = false;

  /// Leaving by 完成: nobody left to tell.
  bool _leaving = false;

  /// The services the page switches between with people to tell: 完成
  /// tells them all.
  Set<String> _waiting = const {};

  /// The table's sideways scroll, for the fade at its edge.
  final _cells = ScrollController();

  /// The table's scroll down the days, back to the top when months are
  /// shown before.
  final _rows = ScrollController();

  /// How many more months may join on.
  int _room = 0;

  /// Months have joined on since the last build: the table's end is
  /// where it was till it is laid out again.
  bool _joined = false;

  /// What of the table stays put as the rest scrolls under it: the
  /// dates' width and the duties' names' height.
  double _datesWidth = 0;
  double _namesHeight = 0;

  // A cell held: where it would land, found by the cells' places on
  // screen, again as the table scrolls under a still finger.
  _Lift? _lift;
  OverlayEntry? _liftView;
  EdgeDraggingAutoScroller? _scroller;
  final _cellKeys = <String, GlobalKey>{};
  List<Roster> _shown = const [];
  Set<String> _flash = const {};
  Timer? _flashTimer;

  /// The cells' look while one is held or just traded: only they build
  /// again as it changes, not the table.
  final _looks = _Looks();

  /// The cells a held one cannot go to fade together, on one animation;
  /// the last held one's stay on it as they come back.
  late final _fading = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
  late final _faded = Tween<double>(begin: 1, end: 0.4).animate(_fading);
  _Lift? _lastLift;

  /// Reduce Motion, as the last build had it.
  bool _still = false;
  int? _down;

  @override
  void dispose() {
    _scroller?.stopAutoScroll();
    _liftView
      ?..remove()
      ..dispose();
    _flashTimer?.cancel();
    _cells.dispose();
    _rows.dispose();
    _looks.dispose();
    _fading.dispose();
    super.dispose();
  }

  static String _cellId(Roster day, String role) => '${day.id}/$role';

  GlobalKey _keyOf(Roster day, String role) => _cellKeys.putIfAbsent(_cellId(day, role), GlobalKey.new);

  /// [day] as the table has it now.
  Roster _current(Roster day) => _shown.firstWhere((d) => d.id == day.id, orElse: () => day);

  void _liftStart(BuildContext cell, Roster day, String role, LongPressStartDetails d) {
    _liftEnd(drop: false);
    final box = cell.findRenderObject()! as RenderBox;
    final table = _globalRect(Scrollable.of(cell, axis: Axis.vertical).context);
    final lift = _Lift(
      pointer: _down,
      from: day,
      role: role,
      size: box.size,
      grab: d.localPosition,
      at: d.globalPosition,
      bounds: Rect.fromLTRB(table.left + _datesWidth, table.top + _namesHeight, table.right, table.bottom),
    );
    Haptics.light();
    _scroller = EdgeDraggingAutoScroller(
      Scrollable.of(cell, axis: Axis.vertical),
      velocityScalar: _autoScrollSpeed,
      onScrollViewScrolled: () {
        // The cells are where the scroll put them once laid out again.
        WidgetsBinding.instance.addPostFrameCallback((_) => _retarget());
        _autoScroll();
      },
    );
    final view = OverlayEntry(builder: (_) => _LiftedCell(lift: lift));
    _liftView = view;
    Overlay.of(context, rootOverlay: true).insert(view);
    _lift = _lastLift = lift;
    _looks.changed();
    _fade(in_: true);
  }

  void _fade({required bool in_}) {
    if (_still) {
      _fading.value = in_ ? 1 : 0;
    } else {
      in_ ? _fading.forward() : _fading.reverse();
    }
  }

  // The finger that holds a cell is followed here, not by the cell's own
  // long press, which goes if the cell is emptied meanwhile.
  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) _down = e.pointer;
    final lift = _lift;
    if (lift == null || e.pointer != lift.pointer) return;
    switch (e) {
      case PointerMoveEvent():
        lift.at = e.position;
        _liftView?.markNeedsBuild();
        _retarget();
        _autoScroll();
      case PointerUpEvent():
        _liftEnd();
      case PointerCancelEvent():
        _liftEnd(drop: false);
      default:
    }
  }

  /// Near the top or the bottom, the table scrolls on under the finger,
  /// and on for as long as it stays there.
  void _autoScroll() {
    final lift = _lift;
    final scroller = _scroller;
    if (lift == null || scroller == null) return;
    final reach = math.min(lift.size.height * 2, scroller.scrollable.position.viewportDimension / 2);
    // The table's top edge is under the duties' names, which stay put.
    final at = lift.at;
    scroller.startAutoScrollIfNecessary(
      Rect.fromLTRB(at.dx, at.dy - reach / 2 - _namesHeight, at.dx + 1, at.dy + reach / 2),
    );
  }

  /// The day the lifted cell would trade with if let go now: the one of
  /// its duty under the finger, if they can trade.
  void _retarget() {
    final lift = _lift;
    if (lift == null) return;
    Roster? to;
    if (lift.bounds.contains(lift.at)) {
      for (final day in _shown) {
        final cell = _cellKeys[_cellId(day, lift.role)]?.currentContext;
        if (cell == null || !_globalRect(cell).contains(lift.at)) continue;
        if (canSwapDuty(lift.role, _current(lift.from), day)) to = day;
        break;
      }
    }
    if (to?.id == lift.to?.id) return;
    if (to != null) Haptics.selection();
    lift.to = to;
    _looks.changed();
  }

  /// Lets go of the held cell: dropped where it would trade, the two days
  /// trade, and light up once they have.
  Future<void> _liftEnd({bool drop = true}) async {
    final lift = _lift;
    if (lift == null) return;
    _scroller?.stopAutoScroll();
    _scroller = null;
    _liftView
      ?..remove()
      ..dispose();
    _liftView = null;
    _lift = null;
    _looks.changed();
    _fade(in_: false);
    if (!drop || lift.to == null) return;
    // As they are now: either may have changed while it was held.
    final (from, to) = (_current(lift.from), _current(lift.to!));
    if (!canSwapDuty(lift.role, from, to)) return;
    if (!await swapDutyDays(context, ref, lift.role, from, to, via: RosterVia.plan) || !mounted) return;
    _flashTimer?.cancel();
    _flash = {_cellId(from, lift.role), _cellId(to, lift.role)};
    _looks.changed();
    _flashTimer = Timer(_flashFor, () {
      _flash = const {};
      _looks.changed();
    });
  }

  /// 完成: tells whoever was put on or taken off here, then goes back. A
  /// failure stays, with 重試.
  Future<void> _finish() async {
    setState(() => _notifying = true);
    final toasts = _toasts;
    final actions = ref.read(rosterActionsProvider);
    final waiting = _waiting;
    // 重試 once the page is gone (left while telling) tells from wherever
    // it is.
    void retry() => mounted ? _finish() : _tellPlanned(toasts, actions, waiting, onRetry: retry);
    final told = await _tellPlanned(toasts, actions, waiting, onRetry: retry);
    if (!mounted) return;
    setState(() {
      _notifying = false;
      // Told: no toast offering 通知 on the way out, though the news has
      // not caught up yet.
      _leaving = told;
    });
    if (told) context.pop();
  }

  /// Left another way than 完成 while people wait (back, a swipe from the
  /// edge): gone at once, as any page goes, with 通知 offered on the page
  /// behind; left alone, they are told with the next 完成.
  void _left() {
    final toasts = _toasts;
    final actions = ref.read(rosterActionsProvider);
    final waiting = _waiting;
    void tell() => _tellPlanned(toasts, actions, waiting, onRetry: tell);
    showToast(toasts, L10n.of(toasts).planNotYetTold, action: (label: L10n.of(toasts).planNotifyNow, onPressed: tell));
  }

  /// Where toasts go, still there once this page is gone.
  BuildContext get _toasts => Navigator.of(context, rootNavigator: true).context;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    _still = MediaQuery.disableAnimationsOf(context);
    final today = ref.watch(todayProvider);
    final thisMonth = Day(today.year, today.month, 1);
    final settings = ref.watch(servicesProvider).value;
    final me = ref.watch(meProvider).value;
    final ministries = ref.watch(ministriesProvider).value?.ministries ?? const <Ministry>[];
    final mine = [
      for (final s in me?.rosterServices(settings?.enabled ?? const [], ministries: ministries) ?? const <Service>[])
        if (me!.arranges(ministries, s.id).any) s,
    ];
    final service = settings?.byId(_type);
    final arranges = ref.watch(arrangesProvider(_type));
    final ready = ref.watch(rosterEditingProvider(_type));
    final saved = ref.watch(savedRostersProvider).value;
    // Every service the page switches between, watched so 完成 knows.
    _waiting = {
      for (final type in {_type, for (final s in mine) s.id})
        if (ref.watch(plannedNewsProvider(type)).value ?? false) type,
    };
    final news = _waiting.isNotEmpty;

    Widget body;
    List<String> duties = const [];
    if (service == null || saved == null || !ready || !arranges.any) {
      body = const SizedBox.shrink();
    } else {
      final from = _from ??= () {
        final ahead = planMonths(
          service: service,
          saved: saved,
          today: today,
          month: thisMonth,
          months: _gapSearchMonths,
        ).expand((m) => m.days);
        return firstGap(ahead, planDuties(service, ahead, arranges)) ?? thisMonth;
      }();
      final months = planMonths(service: service, saved: saved, today: today, month: from, months: _months);
      _room = math.max(0, _monthsAhead - _monthsBetween(thisMonth, from) - _months);
      _joined = false;
      duties = planDuties(service, months.expand((m) => m.days), arranges);
      body = _table(context, months, duties, earlier: from.isAfter(thisMonth) ? thisMonth : null);
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && news && !_leaving && !_notifying) _left();
      },
      // White, as a table is: the empty cells' dashes show on it.
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: AppBar(
          backgroundColor: c.surface,
          // One duty: named here, in place of a column's name.
          title: Text(duties.length == 1 ? l10n.planWeeksTitleOne(duties.single) : l10n.planWeeksTitle),
          actions: savingActions([
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.5,
              child: TextButton(
                onPressed: _notifying ? null : _finish,
                child: Text(l10n.done),
              ),
            ),
          ]),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (mine.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [for (final s in mine) ButtonSegment(value: s.id, label: Text(s.name, maxLines: 1))],
                  selected: {_type},
                  onSelectionChanged: (v) {
                    Haptics.selection();
                    setState(() {
                      _type = v.first;
                      _from = null;
                      _months = _monthsAtATime;
                    });
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              child: Text(l10n.planWeeksHint, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
            ),
            Expanded(
              child: Listener(
                onPointerDown: _onPointer,
                onPointerMove: _onPointer,
                onPointerUp: _onPointer,
                onPointerCancel: _onPointer,
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The table: the duties' names stay at the top and the dates at the
  /// start, the rest scrolls both ways; each month starts under its name.
  /// Only the cells on screen are built, however many months there are.
  Widget _table(
    BuildContext context,
    List<({Day month, List<Roster> days})> months,
    List<String> duties, {
    Day? earlier,
  }) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final scale = MediaQuery.textScalerOf(context);
    final platform = Theme.of(context).platform;
    final today = ref.watch(todayProvider);
    // Two lines of names, two of a duty's name.
    final rowHeight = math.max(Space.minTap(platform) + Space.s, scale.scale(15) * 1.3 * 2 + Space.m);
    final monthHeight = scale.scale(17) * 1.3 + Space.m + Space.s;
    final line = BorderSide(color: c.separator, width: 0.5);

    _shown = [for (final m in months) ...m.days];
    // A month's name (its first day) or a day, under the duties' names.
    final rows = <Object>[
      for (final m in months) ...[m.month, ...m.days],
    ];
    final named = duties.length > 1;
    // The duties' names' row, over the months.
    final head = named ? 1 : 0;
    _namesHeight = named ? scale.scale(13) * 1.3 * 2 + Space.s * 2 : 0;
    final dateWidth = _datesWidth = _DateCell.widthFor(context, _shown);

    Widget cellAt(TableVicinity at) {
      final role = at.column == 0 ? null : duties[at.column - 1];
      if (named && at.row == 0) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: line),
          ),
          child: role == null
              ? const SizedBox.expand()
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s),
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    role,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.footnote.copyWith(color: c.secondaryLabel, fontWeight: FontWeight.w600),
                  ),
                ),
        );
      }
      switch (rows[at.row - head]) {
        case final Day month:
          if (role != null) return const SizedBox.shrink();
          // Across the row from the dates, over the duties' empty cells.
          return ColoredBox(
            color: c.surface,
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              alignment: AlignmentDirectional.bottomStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(Space.m, 0, Space.m, Space.s),
                child: Semantics(
                  header: true,
                  child: Text(DateFormat.yMMMM().format(month.midnight), style: AppText.headline),
                ),
              ),
            ),
          );
        case final Roster day when role == null:
          // Over the cells scrolled under it, with its own ink.
          return Material(
            color: c.surface,
            child: _DateCell(
              roster: day,
              today: today,
              border: line,
              onTap: () => context.push('/rosters/${day.type}/${day.day.key}'),
            ),
          );
        case final Roster day:
          return _DutyCell(
            key: _keyOf(day, role!),
            roster: day,
            role: role,
            today: today,
            border: line,
            looks: _looks,
            fade: _faded,
            // While a cell is held, only the days it can go to stay.
            faded: () {
              final lift = _lift ?? _lastLift;
              return lift != null && (lift.role != role || !canSwapDuty(role, lift.from, day));
            },
            lit: () {
              final lift = _lift;
              return lift?.to?.id == day.id && lift?.role == role || _flash.contains(_cellId(day, role));
            },
            onTap: (duty) => pickPeople(context, ref, day, duty, via: RosterVia.plan, swapDays: _shown),
            onLift: (cell, d) => _liftStart(cell, day, role, d),
            alone: duties.length == 1,
            onSwap: _shown.any((d) => canSwapDuty(role, day, d))
                ? (duty) => pickDayToSwap(context, ref, day, duty, _shown, via: RosterVia.plan)
                : null,
          );
        default:
          throw StateError('A row is a month or a day.');
      }
    }

    final table = LayoutBuilder(
      builder: (context, box) {
        // All the duties when they fit; when not, the last one shown is
        // cut short of half, so the table says it goes on sideways.
        final room = box.maxWidth - dateWidth;
        final fits = duties.isNotEmpty && room / duties.length >= _minCellWidth;
        final whole = (room / _minCellWidth - _peek).floor().clamp(1, math.max(1, duties.length));
        final cellWidth = duties.isEmpty ? 0.0 : (fits ? room / duties.length : room / (whole + _peek));
        final table = NotificationListener<Notification>(
          onNotification: _nearEnd,
          // Unclipped within, a month's name runs on past the dates; the
          // dates and the duties' names cover what scrolls under them.
          child: ClipRect(
            child: TableView.builder(
              key: PageStorageKey('plan-$_type'),
              verticalDetails: ScrollableDetails.vertical(controller: _rows),
              horizontalDetails: ScrollableDetails.horizontal(controller: _cells),
              clipBehavior: Clip.none,
              // Built as they scroll in, a row ahead: opening builds little
              // more than shows (the default 250 takes half again as long
              // to open), and a screen reader still reaches the next row.
              // scrollCacheExtent, which it points to, is not in 0.5.5 yet.
              // ignore: deprecated_member_use
              cacheExtent: rowHeight,
              pinnedRowCount: head,
              pinnedColumnCount: 1,
              rowCount: rows.length + head,
              columnCount: duties.length + 1,
              rowBuilder: (i) {
                final row = i - head;
                return TableSpan(
                  extent: FixedTableSpanExtent(switch (row) {
                    < 0 => _namesHeight,
                    _ when rows[row] is Day => monthHeight,
                    _ => rowHeight,
                  }),
                  padding: row == rows.length - 1 ? const TableSpanPadding(trailing: Space.xl) : null,
                );
              },
              columnBuilder: (i) => TableSpan(extent: FixedTableSpanExtent(i == 0 ? dateWidth : cellWidth)),
              cellBuilder: (context, at) => TableViewCell(child: cellAt(at)),
            ),
          ),
        );
        if (fits || duties.isEmpty) return table;
        // The cut column fades out at the edge while there is more that way.
        return Stack(
          children: [
            table,
            PositionedDirectional(
              top: 0,
              bottom: 0,
              end: 0,
              width: Space.l,
              child: IgnorePointer(
                child: ListenableBuilder(
                  listenable: _cells,
                  builder: (context, _) => AnimatedOpacity(
                    opacity:
                        !_cells.hasClients || !_cells.position.hasContentDimensions || _cells.position.extentAfter > 1
                        ? 1
                        : 0,
                    duration: const Duration(milliseconds: 150),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: [c.surface.withValues(alpha: 0), c.surface],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Over the table, where it stays while there are months before.
        if (earlier != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(Space.xs, 0, Space.m, Space.xs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _months += _monthsBetween(earlier, _from!);
                    _from = earlier;
                  });
                  // Where they now start, wherever the table was.
                  if (_rows.hasClients) _rows.jumpTo(0);
                },
                icon: const Icon(Symbols.keyboard_arrow_up_rounded),
                label: Text(l10n.planShowEarlier),
              ),
            ),
          ),
        Expanded(child: table),
      ],
    );
  }

  /// Near the table's end, the next months join on, through the same month
  /// next year.
  bool _nearEnd(Notification n) {
    final metrics = switch (n) {
      ScrollUpdateNotification(:final metrics) || ScrollMetricsNotification(:final metrics) => metrics,
      _ => null,
    };
    if (metrics == null || metrics.axis != Axis.vertical || _room == 0 || _joined) return false;
    if (metrics.extentAfter < metrics.viewportDimension) {
      _joined = true;
      setState(() => _months += math.min(_monthsAtATime, _room));
    }
    return false;
  }
}

/// How many months [to] is after [from].
int _monthsBetween(Day from, Day to) => (to.year - from.year) * 12 + to.month - from.month;

/// A day at the start of its row, as a calendar has it under its month:
/// the day's number, then its weekday or its first 特別活動. Tapping it
/// opens the day.
class _DateCell extends StatelessWidget {
  static const dayStyle = AppText.title3;
  static const weekdayStyle = AppText.caption;
  static final eventStyle = AppText.caption.copyWith(fontWeight: FontWeight.w600);

  /// The 特別活動's dot and the room after it.
  static const dot = 9.0;

  static String eventLabel(Roster roster) =>
      roster.events.length == 1 ? roster.events.first.name : '${roster.events.first.name} +${roster.events.length - 1}';

  /// As wide as the widest of [days], its weekday or its 特別活動 in full
  /// (English ones run long), within reason: the rest is the duties'.
  static double widthFor(BuildContext context, Iterable<Roster> days) {
    final base = DefaultTextStyle.of(context).style;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    double widthOf(String text, TextStyle style) {
      painter
        ..text = TextSpan(text: text, style: base.merge(style))
        ..layout();
      return painter.width;
    }

    final labels = <(String, TextStyle, double)>{
      ('30', dayStyle, 0),
      for (final day in days)
        day.events.isEmpty
            ? (DateFormat.E().format(day.day.midnight), weekdayStyle, 0)
            : (eventLabel(day), eventStyle, dot),
    };
    var widest = 0.0;
    for (final (text, style, before) in labels) {
      widest = math.max(widest, before + widthOf(text, style));
    }
    painter.dispose();
    return (Space.m + widest + Space.s).clamp(64.0, 140.0);
  }

  const _DateCell({
    required this.roster,
    required this.today,
    required this.border,
    required this.onTap,
  });

  final Roster roster;
  final Day today;
  final BorderSide border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final day = roster.day;
    final event = roster.events.firstOrNull;
    final eventColor = event == null ? null : EventColors.of(context, event.color).fg;
    return Semantics(
      button: true,
      label: l10n.planOpenDay(dayLabel(l10n, day, today)),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsetsDirectional.only(start: Space.m),
          padding: const EdgeInsetsDirectional.only(end: Space.xs),
          decoration: BoxDecoration(border: Border(bottom: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                maxLines: 1,
                style: dayStyle.copyWith(color: day == today ? c.accent : c.label, height: 1.1),
              ),
              if (event == null)
                Text(
                  DateFormat.E().format(day.midnight),
                  maxLines: 1,
                  style: weekdayStyle.copyWith(color: c.secondaryLabel),
                )
              else
                Row(
                  children: [
                    Container(
                      width: dot - 3,
                      height: dot - 3,
                      margin: const EdgeInsetsDirectional.only(end: 3),
                      decoration: BoxDecoration(color: eventColor, shape: BoxShape.circle),
                    ),
                    Flexible(
                      child: Text(
                        eventLabel(roster),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: eventStyle.copyWith(color: eventColor),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who is on [role] that day. Tapping picks them; held, they lift to be
/// dropped on another day. Nobody yet shows a dashed ＋, a place to fill
/// rather than a word repeated down the table. A day without the duty
/// shows a dash and is changed on the day's own page.
class _DutyCell extends StatelessWidget {
  const _DutyCell({
    super.key,
    required this.roster,
    required this.role,
    required this.today,
    required this.border,
    required this.looks,
    required this.fade,
    required this.faded,
    required this.lit,
    required this.onTap,
    required this.onLift,
    required this.alone,
    required this.onSwap,
  });

  final Roster roster;
  final String role;
  final Day today;
  final BorderSide border;

  /// Tells when [faded] or [lit] may have changed.
  final Listenable looks;

  /// How faded cells show, the same for them all.
  final Animation<double> fade;

  /// Somewhere a held cell cannot go, or the last one held could not.
  final bool Function() faded;

  /// Where a held cell would go, or just traded.
  final bool Function() lit;
  final ValueChanged<Duty> onTap;

  /// Held: the screen follows the finger from here.
  final void Function(BuildContext cell, LongPressStartDetails details) onLift;

  /// 和別週交換, for screen readers in place of dragging; null when no
  /// other day can trade.
  final ValueChanged<Duty>? onSwap;

  /// The only duty shown: a list of days, not a table, with no duty's
  /// name above to line up under.
  final bool alone;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final duty = roster.duties.where((d) => d.role == role).firstOrNull;
    final people = duty?.people ?? const <String>[];
    // Read out whole, though only two show.
    final text = duty == null ? '—' : (people.isEmpty ? l10n.nobodyYet : people.join(l10n.listSeparator));
    return Semantics(
      button: duty != null,
      label: '$role, ${dayLabel(l10n, roster.day, today)}',
      value: text,
      customSemanticsActions: {
        if (onSwap case final swap? when duty != null)
          CustomSemanticsAction(label: l10n.pickerSwapDay): () => swap(duty),
      },
      excludeSemantics: true,
      child: GestureDetector(
        onLongPressStart: people.isEmpty ? null : (d) => onLift(context, d),
        child: _CellLook(
          looks: looks,
          faded: faded,
          lit: lit,
          builder: (context, faded, lit, content) => FadeTransition(
            opacity: faded ? fade : kAlwaysCompleteAnimation,
            child: InkWell(
              onTap: duty == null ? null : () => onTap(duty),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
                alignment: AlignmentDirectional.centerStart,
                decoration: BoxDecoration(
                  color: lit == 0 ? null : Color.lerp(c.accentSoft.withValues(alpha: 0), c.accentSoft, lit),
                  border: Border(bottom: border),
                ),
                child: content,
              ),
            ),
          ),
          child: duty == null
              ? Text('—', style: AppText.subheadline.copyWith(color: c.tertiaryLabel))
              : people.isEmpty
              ? _EmptySlot(wide: alone)
              : _People(people),
        ),
      ),
    );
  }
}

/// A duty nobody is on yet: a dashed box with a ＋, as an open place. At
/// the start of the cell, under the duty's name, as names are: a column
/// cut at the screen's edge still shows both. [wide]: across the row, the
/// only duty shown, with no name above it.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CustomPaint(
      // tertiaryLabel: 3:1 or better, as a control's edge needs.
      painter: _Dashes(c.tertiaryLabel),
      child: SizedBox(
        height: Space.minTap(Theme.of(context).platform) - Space.s,
        width: wide ? double.infinity : Space.xxl + Space.s,
        child: Icon(Symbols.add_rounded, size: 20, color: c.tertiaryLabel),
      ),
    );
  }
}

class _Dashes extends CustomPainter {
  const _Dashes(this.color);

  final Color color;

  // Every empty cell is the same size: its dashes are measured out once.
  static final _paths = <Size, Path>{};

  static Path _dashed(Size size) {
    final box = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), const Radius.circular(Radii.s));
    final dashes = Path();
    for (final metric in (Path()..addRRect(box)).computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 7) {
        dashes.addPath(metric.extractPath(at, math.min(at + 4, metric.length)), Offset.zero);
      }
    }
    return dashes;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (_paths.length > 8 && !_paths.containsKey(size)) _paths.clear();
    canvas.drawPath(_paths.putIfAbsent(size, () => _dashed(size)), paint);
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}

/// A person a line, each cut short rather than wrapped onto the next;
/// past two, how many more after the second.
class _People extends StatelessWidget {
  const _People(this.people);

  final List<String> people;

  @override
  Widget build(BuildContext context) {
    final style = AppText.subheadline.copyWith(color: AppColors.of(context).label);
    Text line(String name) => Text(name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(people[0]),
        if (people.length > 1)
          Row(
            children: [
              Flexible(child: line(people[1])),
              if (people.length > 2) Text(' +${people.length - 2}', style: style),
            ],
          ),
      ],
    );
  }
}

/// Tells the cells their look may have changed.
class _Looks extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// A cell's look, built again only when [faded] or [lit] turn as [looks]
/// changes: held cells retarget on every move, and only two cells light.
/// Lit, it brightens over a moment, [builder]'s `lit` going from 0 to 1;
/// only a cell that lights makes an animation for it.
class _CellLook extends StatefulWidget {
  const _CellLook({
    required this.looks,
    required this.faded,
    required this.lit,
    required this.builder,
    required this.child,
  });

  final Listenable looks;
  final bool Function() faded;
  final bool Function() lit;
  final Widget Function(BuildContext context, bool faded, double lit, Widget child) builder;
  final Widget child;

  @override
  State<_CellLook> createState() => _CellLookState();
}

class _CellLookState extends State<_CellLook> with SingleTickerProviderStateMixin {
  late bool _faded = widget.faded();
  late bool _lit = widget.lit();
  AnimationController? _lighting;
  bool _still = false;

  void _light(bool lit) {
    final lighting = _lighting ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: _lit ? 1 : 0,
    )..addListener(() => setState(() {}));
    if (_still) {
      lighting.value = lit ? 1 : 0;
    } else {
      lit ? lighting.forward() : lighting.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.looks.addListener(_changed);
  }

  @override
  void didUpdateWidget(_CellLook old) {
    super.didUpdateWidget(old);
    if (old.looks != widget.looks) {
      old.looks.removeListener(_changed);
      widget.looks.addListener(_changed);
    }
    _faded = widget.faded();
    final lit = widget.lit();
    if (lit != _lit) _light(lit);
    _lit = lit;
  }

  @override
  void dispose() {
    widget.looks.removeListener(_changed);
    _lighting?.dispose();
    super.dispose();
  }

  void _changed() {
    final (faded, lit) = (widget.faded(), widget.lit());
    if (faded != _faded || lit != _lit) {
      if (lit != _lit) _light(lit);
      setState(() {
        _faded = faded;
        _lit = lit;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _still = MediaQuery.disableAnimationsOf(context);
    return widget.builder(context, _faded, _lighting?.value ?? (_lit ? 1 : 0), widget.child);
  }
}

/// A cell held (#90): [role] on [from], lifted from [grab] within its
/// [size], under the finger at [at]; [to] the day it would trade with.
/// [bounds]: where the table's cells show on screen.
class _Lift {
  _Lift({
    required this.pointer,
    required this.from,
    required this.role,
    required this.size,
    required this.grab,
    required this.at,
    required this.bounds,
  });

  /// The finger holding it.
  final int? pointer;
  final Roster from;
  final String role;
  final Size size;
  final Offset grab;
  final Rect bounds;
  Offset at;
  Roster? to;
}

/// The held cell, raised over the page and following the finger from
/// where it was held.
class _LiftedCell extends StatelessWidget {
  const _LiftedCell({required this.lift});

  final _Lift lift;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = overlay.globalToLocal(lift.at - lift.grab);
    final people = lift.from.duties.firstWhere((d) => d.role == lift.role).people;
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      child: IgnorePointer(
        child: Material(
          color: c.surfaceRaised,
          elevation: 8,
          borderRadius: BorderRadius.circular(Radii.s),
          child: Container(
            width: lift.size.width,
            height: lift.size.height,
            padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
            alignment: AlignmentDirectional.centerStart,
            child: _People(people),
          ),
        ),
      ),
    );
  }
}

Rect _globalRect(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Tells the people waiting on [types], one notice each, and says so in a
/// toast from [toasts]; false when it failed, said with 重試 ([onRetry]).
Future<bool> _tellPlanned(
  BuildContext toasts,
  RosterActions actions,
  Set<String> types, {
  required VoidCallback onRetry,
}) async {
  final l10n = L10n.of(toasts);
  try {
    var people = 0;
    var later = false;
    for (final type in types) {
      final r = await actions.notifyPlanned(type);
      people += r.people;
      later |= r.later;
    }
    if (toasts.mounted && people > 0) {
      showToast(toasts, later ? l10n.planNotifiedLater(people) : l10n.planNotified(people));
    }
    return true;
  } catch (e) {
    if (toasts.mounted) showToast(toasts, errorText(l10n, e), onRetry: onRetry);
    return false;
  }
}
