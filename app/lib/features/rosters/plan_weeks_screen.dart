import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/plan_weeks.dart';
import '../../domain/roster_edit.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../common/errors.dart';
import '../common/saving_indicator.dart';
import 'format.dart';
import 'roster_day_screen.dart';

/// 安排服事 (#90): one service's days a month at a time, a row a day and a
/// column a duty I arrange. Tapping a cell picks its people as on the
/// day's page, saved with its 完成; tapping a date opens that day. A cell held
/// lifts, and dropped on another day of its duty trades the two (moves
/// them, onto a day with nobody); the picker's 和別週交換 does the same
/// without dragging. Nobody is told until 通知同工, which tells each
/// person once, for all their days.
/// Opens at the first month with a duty nobody is on yet; the months
/// before it are a button away, later ones below.
class PlanWeeksScreen extends ConsumerStatefulWidget {
  const PlanWeeksScreen({super.key, required this.serviceType});

  /// The service it opens at, the one the 服事表 tab showed.
  final String serviceType;

  @override
  ConsumerState<PlanWeeksScreen> createState() => _PlanWeeksScreenState();
}

/// How many months the page shows at first, and adds each time.
const _monthsAtATime = 3;

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

class _PlanWeeksScreenState extends ConsumerState<PlanWeeksScreen> {
  late String _type = widget.serviceType;

  /// The first month shown (its first day); null until the days are in.
  Day? _from;
  int _months = _monthsAtATime;
  bool _notifying = false;

  /// Leaving by 完成 or 先不要: nothing more to ask.
  bool _leaving = false;

  /// The services the page switches between with people to tell: 完成
  /// tells them all.
  Set<String> _waiting = const {};

  // The duties' names scroll sideways with the cells under them.
  final _cells = ScrollController();
  final _names = ScrollController();

  // A cell held: where it would land, found by the cells' places on
  // screen, again as the table scrolls under a still finger.
  _Lift? _lift;
  OverlayEntry? _liftView;
  EdgeDraggingAutoScroller? _scroller;
  final _cellKeys = <String, GlobalKey>{};
  List<Roster> _shown = const [];
  Set<String> _flash = const {};
  Timer? _flashTimer;
  int? _down;

  @override
  void initState() {
    super.initState();
    _cells.addListener(() {
      if (_names.hasClients) _names.jumpTo(_cells.offset);
    });
  }

  @override
  void dispose() {
    _scroller?.stopAutoScroll();
    _liftView
      ?..remove()
      ..dispose();
    _flashTimer?.cancel();
    _cells.dispose();
    _names.dispose();
    super.dispose();
  }

  static String _cellId(Roster day, String role) => '${day.id}/$role';

  GlobalKey _keyOf(Roster day, String role) => _cellKeys.putIfAbsent(_cellId(day, role), GlobalKey.new);

  /// [day] as the table has it now.
  Roster _current(Roster day) => _shown.firstWhere((d) => d.id == day.id, orElse: () => day);

  void _liftStart(BuildContext cell, Roster day, String role, LongPressStartDetails d) {
    _liftEnd(drop: false);
    final box = cell.findRenderObject()! as RenderBox;
    final lift = _Lift(
      pointer: _down,
      from: day,
      role: role,
      size: box.size,
      grab: d.localPosition,
      at: d.globalPosition,
      bounds: _globalRect(Scrollable.of(cell, axis: Axis.vertical).context).intersect(
        _globalRect(Scrollable.of(cell, axis: Axis.horizontal).context),
      ),
    );
    Haptics.light();
    _scroller = EdgeDraggingAutoScroller(
      Scrollable.of(cell, axis: Axis.vertical),
      velocityScalar: _autoScrollSpeed,
      onScrollViewScrolled: () {
        _retarget();
        _autoScroll();
      },
    );
    final view = OverlayEntry(builder: (_) => _LiftedCell(lift: lift));
    _liftView = view;
    Overlay.of(context, rootOverlay: true).insert(view);
    setState(() => _lift = lift);
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
    scroller.startAutoScrollIfNecessary(Rect.fromCenter(center: lift.at, width: 1, height: reach));
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
    setState(() => lift.to = to);
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
    setState(() => _lift = null);
    if (!drop || lift.to == null) return;
    // As they are now: either may have changed while it was held.
    final (from, to) = (_current(lift.from), _current(lift.to!));
    if (!canSwapDuty(lift.role, from, to)) return;
    if (!await swapDutyDays(context, ref, lift.role, from, to, via: 'plan') || !mounted) return;
    _flashTimer?.cancel();
    setState(() => _flash = {_cellId(from, lift.role), _cellId(to, lift.role)});
    _flashTimer = Timer(_flashFor, () {
      if (mounted) setState(() => _flash = const {});
    });
  }

  /// 完成: tells whoever was put on or taken off here, then goes back. A
  /// failure stays, with 重試.
  Future<void> _finish() async {
    if (!await _tell() || !mounted) return;
    // Told: the news that would ask has not caught up yet.
    setState(() => _leaving = true);
    context.pop();
  }

  /// Tells the people waiting on each service this page arranges, one
  /// notice each; false when it failed.
  Future<bool> _tell() async {
    final l10n = L10n.of(context);
    setState(() => _notifying = true);
    try {
      final actions = ref.read(rosterActionsProvider);
      var people = 0;
      var later = false;
      for (final type in _waiting) {
        final r = await actions.notifyPlanned(type);
        people += r.people;
        later |= r.later;
      }
      if (mounted && people > 0) {
        showToast(context, later ? l10n.planNotifiedLater(people) : l10n.planNotified(people));
      }
      return true;
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e), onRetry: _finish);
      return false;
    } finally {
      if (mounted) setState(() => _notifying = false);
    }
  }

  /// Leaving another way than 完成 while people wait: asks whether to tell
  /// them now; 先不要 leaves them for the next 完成.
  Future<void> _leave() async {
    final l10n = L10n.of(context);
    final tell = await askChoice(
      context,
      title: l10n.planNotifyAsk,
      message: l10n.planNotifyAskBody,
      yes: l10n.planNotifyNow,
      no: l10n.planNotifyLater,
    );
    if (tell == null || !mounted) return;
    if (tell) return _finish();
    setState(() => _leaving = true);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
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
      duties = planDuties(service, months.expand((m) => m.days), arranges);
      body = _table(context, months, duties, earlier: from.isAfter(thisMonth) ? thisMonth : null);
    }

    return PopScope(
      canPop: !news || _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_notifying) _leave();
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
    // Fixed heights keep the dates and their cells on the same rows, in
    // two scroll views: two lines of names, two of a duty's name.
    final rowHeight = math.max(Space.minTap(platform) + Space.s, scale.scale(15) * 1.3 * 2 + Space.m);
    final headHeight = scale.scale(13) * 1.3 * 2 + Space.s * 2;
    final monthHeight = scale.scale(17) * 1.3 + Space.m + Space.s;
    final line = BorderSide(color: c.separator, width: 0.5);

    _shown = [for (final m in months) ...m.days];
    final dateWidth = _DateCell.widthFor(context, _shown);
    final lift = _lift;
    return LayoutBuilder(
      builder: (context, box) {
        // All the duties when they fit; when not, the last one shown is
        // cut short of half, so the table says it goes on sideways.
        final room = box.maxWidth - dateWidth;
        final fits = duties.isNotEmpty && room / duties.length >= _minCellWidth;
        final whole = (room / _minCellWidth - _peek).floor().clamp(1, math.max(1, duties.length));
        final cellWidth = duties.isEmpty ? 0.0 : (fits ? room / duties.length : room / (whole + _peek));
        final dates = <Widget>[];
        final cells = <Widget>[];
        final headers = <Widget>[];
        var y = 0.0;
        for (final m in months) {
          headers.add(
            Positioned(
              top: y,
              left: 0,
              right: 0,
              height: monthHeight,
              child: Container(
                color: c.surface,
                alignment: AlignmentDirectional.bottomStart,
                padding: const EdgeInsetsDirectional.fromSTEB(Space.m, 0, Space.m, Space.s),
                child: Semantics(
                  header: true,
                  child: Text(DateFormat.yMMMM().format(m.month.midnight), style: AppText.headline),
                ),
              ),
            ),
          );
          dates.add(SizedBox(height: monthHeight));
          cells.add(SizedBox(height: monthHeight, width: cellWidth * duties.length));
          y += monthHeight;
          for (final day in m.days) {
            dates.add(
              _DateCell(
                roster: day,
                today: today,
                height: rowHeight,
                border: line,
                onTap: () => context.push('/rosters/${day.type}/${day.day.key}'),
              ),
            );
            cells.add(
              Row(
                children: [
                  for (final role in duties)
                    _DutyCell(
                      key: _keyOf(day, role),
                      roster: day,
                      role: role,
                      today: today,
                      width: cellWidth,
                      height: rowHeight,
                      border: line,
                      // While a cell is held, only the days it can go to stay.
                      faded: lift != null && (lift.role != role || !canSwapDuty(role, lift.from, day)),
                      lit: lift?.to?.id == day.id && lift?.role == role || _flash.contains(_cellId(day, role)),
                      onTap: (duty) => pickPeople(context, ref, day, duty, via: 'plan', swapDays: _shown),
                      onLift: (cell, d) => _liftStart(cell, day, role, d),
                      alone: duties.length == 1,
                      onSwap: _shown.any((d) => canSwapDuty(role, day, d))
                          ? (duty) => pickDayToSwap(context, ref, day, duty, _shown, via: 'plan')
                          : null,
                    ),
                ],
              ),
            );
            y += rowHeight;
          }
        }
        final table = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (duties.length > 1)
              DecoratedBox(
                decoration: BoxDecoration(border: Border(bottom: line)),
                child: SizedBox(
                  height: headHeight,
                  child: Row(
                    children: [
                      SizedBox(width: dateWidth),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _names,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: Row(
                            children: [
                              for (final role in duties)
                                Container(
                                  width: cellWidth,
                                  padding: const EdgeInsets.symmetric(horizontal: Space.s),
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    role,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.footnote.copyWith(
                                      color: c.secondaryLabel,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                key: PageStorageKey('plan-$_type'),
                padding: const EdgeInsets.only(bottom: Space.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (earlier != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s),
                        child: TextButton(
                          onPressed: () => setState(() {
                            _months += _from!.month - earlier.month + 12 * (_from!.year - earlier.year);
                            _from = earlier;
                          }),
                          child: Text(l10n.planShowEarlier),
                        ),
                      ),
                    Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: dateWidth,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: dates),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _cells,
                                scrollDirection: Axis.horizontal,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
                              ),
                            ),
                          ],
                        ),
                        ...headers,
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Space.m),
                      child: SecondaryButton(
                        label: l10n.rosterShowMore,
                        onPressed: () => setState(() => _months += _monthsAtATime),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
  }
}

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
    required this.height,
    required this.border,
    required this.onTap,
  });

  final Roster roster;
  final Day today;
  final double height;
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
          height: height,
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
    required this.width,
    required this.height,
    required this.border,
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
  final double width;
  final double height;
  final BorderSide border;

  /// Somewhere a held cell cannot go.
  final bool faded;

  /// Where a held cell would go, or just traded.
  final bool lit;
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
    final still = MediaQuery.disableAnimationsOf(context);
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
        child: AnimatedOpacity(
          opacity: faded ? 0.4 : 1,
          duration: still ? Duration.zero : const Duration(milliseconds: 150),
          child: InkWell(
            onTap: duty == null ? null : () => onTap(duty),
            child: AnimatedContainer(
              duration: still ? Duration.zero : const Duration(milliseconds: 200),
              width: width,
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
              alignment: AlignmentDirectional.centerStart,
              decoration: BoxDecoration(
                color: lit ? c.accentSoft : null,
                border: Border(bottom: border),
              ),
              child: duty == null
                  ? Text('—', style: AppText.subheadline.copyWith(color: c.tertiaryLabel))
                  : people.isEmpty
                  ? _EmptySlot(wide: alone)
                  : _People(people),
            ),
          ),
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

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final box = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), const Radius.circular(Radii.s));
    for (final metric in (Path()..addRRect(box)).computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 7) {
        canvas.drawPath(metric.extractPath(at, math.min(at + 4, metric.length)), paint);
      }
    }
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
