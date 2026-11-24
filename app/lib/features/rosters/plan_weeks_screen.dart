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
import '../../data/backend.dart' show RosterChange;
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/plan_weeks.dart';
import '../../domain/roster_edit.dart';
import '../../domain/roster_news.dart';
import '../../l10n/app_localizations.dart';
import '../../state/plan_draft.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../common/errors.dart';
import '../common/saving_indicator.dart';
import 'duty_picking.dart';
import 'format.dart';
import 'roster_image.dart';

/// 安排服事 (#90): one service's days a month at a time, a row a day and a
/// column a duty I arrange. Tapping a cell picks its people as on the
/// day's page, saved with its 完成; tapping a date opens that day. A cell held
/// lifts, and dropped on another day of its duty trades the two (moves
/// them, onto a day with nobody); the picker's 和別週交換 does the same
/// without dragging. Nobody is told until 通知同工, which tells each
/// person once, for all their days.
/// Opens at this month, arranged or not, as the 服事表 tab does; later
/// months join on as it scrolls.
///
/// [readOnly]: 表格, the same table only to look at, every duty, for whoever
/// does not arrange all of it: from the 服事表 tab, arranging none of it,
/// or 安排服事's ⋯, arranging some. Their own cells are marked; a date
/// still opens its day.
class PlanWeeksScreen extends ConsumerStatefulWidget {
  const PlanWeeksScreen({super.key, required this.serviceType, this.readOnly = false});

  /// The service it opens at, the one the 服事表 tab showed.
  final String serviceType;

  final bool readOnly;

  @override
  ConsumerState<PlanWeeksScreen> createState() => _PlanWeeksScreenState();
}

/// How many months the page shows at first, and adds as its end nears.
const _monthsAtATime = 3;

/// How fast the table scrolls while a lifted cell is held at its edge, per
/// point past it (as ReorderableList).
const _autoScrollSpeed = 50.0;

/// How much of the next duty's column shows when they do not all fit.
const _peek = 0.4;

/// The narrowest a duty's column gets: room for the ＋ of a place to fill
/// (_EmptySlot) and the cell's padding.
const _narrowest = Space.xxl + Space.s + Space.s * 2;

/// The widest a duty's column gets for a long name; past it, names are cut
/// short.
const _widest = 120.0;

/// How long the cells a drop traded stay lit.
const _flashFor = Duration(milliseconds: 700);

class _PlanWeeksScreenState extends ConsumerState<PlanWeeksScreen> with SingleTickerProviderStateMixin {
  late String _type = widget.serviceType;

  int _months = _monthsAtATime;

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
  late final AnimationController _fading;
  late final Animation<double> _faded;
  _Lift? _lastLift;

  /// Reduce Motion, as the last build had it.
  bool _still = false;
  int? _down;

  @override
  void initState() {
    super.initState();
    // Made now: one never used (表格) is still disposed of.
    _fading = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _faded = Tween<double>(begin: 1, end: 0.4).animate(_fading);
    // What is changed here waits for 完成; only to look at, nothing does.
    if (!widget.readOnly) {
      final draft = ref.read(planDraftProvider.notifier)..hold();
      _draft = draft;
    }
  }

  /// Where what is changed here waits for 完成; null only to look at.
  PlanDraft? _draft;

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
    // Not saved by 完成: dropped, once the tree is done changing.
    if (_draft case final draft?) Future.microtask(draft.release);
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

  /// The menu, in the order arranging goes: 通知同工填 (#91) from [from],
  /// the first month being arranged, greyed with nobody on a list to ask;
  /// photo import, for a roster already on paper; 分享成圖片, once
  /// arranged. Below a divider, for who arranges some duties only, the
  /// whole roster to look at (表格). Each says only what it does.
  Widget _menu(L10n l10n, Day from) {
    final type = _type;
    final some = !ref.watch(arrangesProvider(type)).all;
    final canAsk = _askedToFill(type).isNotEmpty;
    // Read ahead, for the months' sheet to say.
    ref.watch(unavailableRoundProvider(type));
    return PopupMenuButton<String>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      icon: const Icon(Symbols.more_horiz_rounded),
      onSelected: (v) => switch (v) {
        'ask' => _askUnavailable(type, from),
        'photo' => _saveFirst().then((ok) {
          if (ok && mounted) context.push('/rosters/import/$type');
        }),
        'image' => showRosterImage(context, serviceType: type, month: from),
        'table' => context.push('/rosters/table/$type'),
        _ => null,
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'ask', enabled: canAsk, child: Text(l10n.planAskUnavailable)),
        PopupMenuItem(value: 'photo', child: Text(l10n.photoImportAction)),
        PopupMenuItem(value: 'image', child: Text(l10n.rosterShareImage)),
        if (some) ...[
          const PopupMenuDivider(),
          PopupMenuItem(value: 'table', child: Text(l10n.planWholeTable)),
        ],
      ],
    );
  }

  /// Whom 通知同工填 tells for [type] now.
  List<Member> _askedToFill(String type) {
    final me = ref.watch(meProvider).value;
    if (me == null) return const [];
    return askedToFill(ref.watch(membersProvider).value ?? const [], type, ref.watch(arrangesProvider(type)), me.uid);
  }

  /// 通知同工填 (#91): which months, the months from [from] (the table's
  /// first) in a grid by year, each 已排好 marked; it opens on the first
  /// not arranged, and a tap after it ends the months. Under the last ask
  /// while its months last, which opens who has not sent theirs; then,
  /// asked first as it cannot be taken back, one push each.
  Future<void> _askUnavailable(String type, Day from) async {
    final l10n = L10n.of(context);
    final today = ref.read(todayProvider);
    final round = ref.read(unavailableRoundProvider(type)).value;
    // Its months not all gone by, and someone told still here.
    final last = round != null && round.currentOn(today) && _stillHere(round.told).isNotEmpty ? round : null;
    final waiting = last == null ? 0 : _stillHere(last.waiting).length;
    final ahead = monthsThroughNextYear(from, today: today);
    final choices = [for (var i = 0; i < ahead; i++) Day(from.year, from.month + i, 1)];
    final service = ref.read(servicesProvider).value?.byId(type);
    final saved = ref.read(savedRostersProvider).value ?? const <Roster>[];
    final arranges = ref.read(arrangesProvider(type));
    final arranged = service == null
        ? const <Day>{}
        : {
            for (final m in planMonths(service: service, saved: saved, today: today, month: from, months: ahead))
              if (monthArranged(m.days, arranges)) m.month,
          };
    final picked = await showAppSheet<(Day, Day)>(
      context,
      builder: (context) => _AskMonths(
        months: choices,
        arranged: arranged,
        first: choices.firstWhere((m) => !arranged.contains(m), orElse: () => choices.first),
        round: last == null
            ? null
            : waiting == 0
            ? l10n.planAskRoundDone(monthsLabel(l10n, last.from, last.to))
            : l10n.planAskRound(monthsLabel(l10n, last.from, last.to), waiting),
        onRound: () {
          Navigator.pop(context);
          _showRound(type);
        },
      ),
    );
    if (picked == null || !mounted) return;
    final (start, to) = picked;
    final months = monthsLabel(l10n, start, to);
    final count = _askedToFill(type).length;
    final ok = await confirmAction(
      context,
      title: l10n.planAskConfirm(count, months),
      action: l10n.planAskSend,
      cancel: l10n.cancel,
    );
    if (!ok || !mounted) return;
    final toasts = _toasts;
    try {
      final told = await ref.read(rosterActionsProvider).askUnavailable(type, from: start, to: to);
      if (toasts.mounted) showToast(toasts, l10n.planNotified(told));
    } catch (e) {
      if (toasts.mounted) showToast(toasts, errorText(l10n, e));
    }
  }

  /// Those of [uids] still in the church, in that order.
  List<Member> _stillHere(Iterable<String> uids) {
    final members = {for (final m in ref.read(membersProvider).value ?? const <Member>[]) m.uid: m};
    return [for (final uid in uids) ?members[uid]];
  }

  /// [type]'s last 通知同工填 (#91): who has not sent theirs, by name, and
  /// how many have; 再通知 tells those again.
  Future<void> _showRound(String type) async {
    final l10n = L10n.of(context);
    final remind = await showAppSheet<bool>(
      context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final round = ref.watch(unavailableRoundProvider(type)).value;
          final members = ref.watch(membersProvider).value ?? const <Member>[];
          if (round == null) return const SizedBox.shrink();
          final here = {for (final m in members) m.uid: m};
          final waiting = [for (final uid in round.waiting) ?here[uid]];
          final filled = round.sent.where(here.containsKey).length;
          final c = AppColors.of(context);
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.planAskRoundTitle(monthsLabel(l10n, round.from, round.to)),
                    style: AppText.headline,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    l10n.planAskRoundAt(DateFormat.MMMd().format(round.at)),
                    style: AppText.footnote.copyWith(color: c.secondaryLabel),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.s),
                  if (waiting.isNotEmpty)
                    ListSection(
                      header: l10n.planAskWaiting(waiting.length),
                      footer: filled == 0 ? null : l10n.planAskFilled(filled),
                      children: [for (final m in waiting) ListRow(title: m.name, chevron: false)],
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(Space.m),
                      child: Text(
                        l10n.planAskFilled(filled),
                        style: AppText.footnote.copyWith(color: c.secondaryLabel),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (waiting.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
                      child: PrimaryButton(
                        label: l10n.planAskRemind(waiting.length),
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (remind != true || !mounted) return;
    final toasts = _toasts;
    try {
      final told = await ref.read(rosterActionsProvider).remindUnavailable(type);
      if (toasts.mounted) showToast(toasts, l10n.planNotified(told));
    } catch (e) {
      if (toasts.mounted) showToast(toasts, errorText(l10n, e));
    }
  }

  /// 完成: what was changed here saved, then back at once, telling
  /// whoever was put on or taken off behind it; a failure to tell says so
  /// where it went, with 重試. Not saved (offline, or a day someone else
  /// changed meanwhile), it stays, everything still on it, and says why.
  Future<void> _finish() async {
    // A second tap while the page goes would go back from the one behind.
    if (_leaving || _saving) return;
    final toasts = _toasts;
    final actions = ref.read(rosterActionsProvider);
    final change = _draft?.change;
    final ids = <String, List<String>>{};
    for (final r in [...?change?.after.values, ...?change?.before.values]) {
      if (r == null || r.isEvent) continue;
      final of = ids.putIfAbsent(r.type, () => []);
      if (!of.contains(r.id)) of.add(r.id);
    }
    final types = {..._waiting, ...ids.keys};
    if (change != null && !await _save(change)) return;
    if (!mounted) return;
    void tell() => unawaited(_tellPlanned(toasts, actions, types, rosterIds: ids, onRetry: tell));
    // Being told: no toast offering 通知 on the way out, though the news
    // has not caught up yet.
    _leaving = true;
    tell();
    context.pop();
  }

  /// Saving what waited here: a second tap waits for it.
  bool _saving = false;

  /// [change], what waited here, saved; dropped from here once it is (it
  /// shows as saved), kept when not, which is said. Whether it was.
  Future<bool> _save(RosterChange change) async {
    _saving = true;
    try {
      await ref.read(rosterActionsProvider).savePlanned(change);
      _draft?.discard();
      return true;
    } catch (e) {
      if (mounted) showToast(context, saveErrorText(L10n.of(context), e));
      return false;
    } finally {
      _saving = false;
    }
  }

  /// Leaving with changes not saved: asked first, 放棄變更 drops them.
  Future<void> _askToLeave() async {
    if (_saving || !await confirmDiscard(context) || !mounted) return;
    _draft?.discard();
    context.pop();
  }

  /// What was changed here saved now, nobody told yet: before the day's
  /// own page or 照片匯入, which save at once, open on it.
  Future<bool> _saveFirst() async {
    if (_saving) return false;
    final change = _draft?.change;
    return (change == null || await _save(change)) && mounted;
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

  /// [day]'s own page, what was changed here saved first.
  Future<void> _openDay(Roster day) async {
    if (await _saveFirst() && mounted) unawaited(context.push('/rosters/${day.type}/${day.day.key}'));
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
    final view = widget.readOnly;
    final mine = [
      for (final s in me?.rosterServices(settings?.services ?? const [], ministries: ministries) ?? const <Service>[])
        if (view || me!.arranges(ministries, s.id).any) s,
    ];
    final service = settings?.byId(_type);
    final arranges = view ? const Arranges.all() : ref.watch(arrangesProvider(_type));
    // Only to look at, it waits for nothing but the days.
    final ready = view || ref.watch(rosterEditingProvider(_type));
    // The others it switches to, read while it is open: switching shows
    // their table at once, not a blank page first.
    if (!view) {
      for (final s in mine) {
        ref.watch(rosterEditingProvider(s.id));
      }
    }
    final saved = ref.watch(savedRostersProvider).value;
    // Every service the page switches between, watched so 完成 knows.
    _waiting = {
      if (!view)
        for (final type in {_type, for (final s in mine) s.id})
          if (ref.watch(plannedNewsProvider(type)).value ?? false) type,
    };
    final news = _waiting.isNotEmpty;
    final unsaved = !view && ref.watch(planDraftProvider).isNotEmpty;

    Widget body;
    List<String> duties = const [];
    if (service == null || saved == null || !ready || !arranges.any) {
      body = const SizedBox.shrink();
    } else {
      final months = planMonths(service: service, saved: saved, today: today, month: thisMonth, months: _months);
      // Through next December, so all of next year can be arranged.
      _room = math.max(0, monthsThroughNextYear(thisMonth, today: today) - _months);
      _joined = false;
      duties = planDuties(service, months.expand((m) => m.days), arranges);
      // Every day saved ahead, not only the months joined on so far: the
      // columns keep their width as more months join while scrolling.
      final ahead = [
        for (final r in saved)
          if (!r.isEvent && r.type == _type && !r.day.isBefore(today)) r,
      ];
      body = _table(context, months, duties, ahead);
    }

    return PopScope(
      // Changed and not saved: asked before going.
      canPop: !unsaved || _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_askToLeave());
        } else if (news && !_leaving) {
          _left();
        }
      },
      // White, as a table is: the empty cells' dashes show on it.
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: AppBar(
          backgroundColor: c.surface,
          // One duty: named here, in place of a column's name.
          title: Text(switch (duties) {
            _ when view => l10n.tabRosters,
            [final one] => l10n.planWeeksTitleOne(one),
            _ => l10n.planWeeksTitle,
          }),
          actions: view
              ? [
                  if (service != null)
                    IconButton(
                      tooltip: l10n.rosterShareImage,
                      icon: const Icon(Symbols.ios_share_rounded),
                      onPressed: () => showRosterImage(context, serviceType: _type, month: thisMonth, everyDuty: true),
                    ),
                ]
              : savingActions([
                  if (service != null && arranges.any) _menu(l10n, thisMonth),
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.5,
                    child: TextButton(
                      onPressed: _finish,
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
                      _months = _monthsAtATime;
                    });
                  },
                ),
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

  /// Who is on [role] on [day] but marked it as a day they cannot serve
  /// (#91), by name.
  Set<String> _unavailableNames(Roster day, String role, Map<String, UnavailableDays> everyone) {
    final duty = day.duties.where((d) => d.role == role).firstOrNull;
    if (duty == null || everyone.isEmpty) return const {};
    final unavailable = unavailableOn(day, everyone);
    return {
      for (final name in duty.people)
        if (unavailable.containsKey(duty.uids[name])) name,
    };
  }

  /// Widths measured, by text and look: the names barely change between
  /// builds, and a build may come with every move of a held cell.
  final _measured = <(String, TextStyle, double, int), double>{};

  /// How wide each duty's column is at least, the same for all: the widest
  /// of their names, on two lines as the head draws them, and of the people
  /// on [days] as [_People] draws them ([_twoOrCount]), leaving out the
  /// longest tenth of those: they are cut short instead. Measured in the
  /// language shown, so short names (李美玉) fit more columns than long ones
  /// (Christopher Lee); no column is wider than [_widest].
  double _columnWidth(BuildContext context, List<String> duties, Iterable<Roster> days) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final dutyStyle = base.merge(AppText.footnote.copyWith(fontWeight: FontWeight.w600));
    final nameStyle = base.merge(AppText.subheadline);
    final painter = TextPainter(textDirection: Directionality.of(context), textScaler: scaler);
    double measure(String text, TextStyle style, int lines) {
      final key = (text, style, scaler.scale(14), lines);
      if (_measured[key] case final known?) return known;
      // Each word's own first: a word is never broken.
      final words = text.split(' ');
      final longestWord = lines == 2 && words.length > 1
          ? words.map((w) => measure(w, style, 1)).reduce(math.max)
          : 0.0;
      painter
        ..text = TextSpan(text: text, style: style)
        ..maxLines = 1
        ..layout();
      var width = painter.width;
      if (lines == 2) {
        // The narrowest it still fits two lines at: lines break greedily,
        // so half its width may need a third.
        painter.maxLines = 2;
        var low = math.max(longestWord, width / 2);
        for (var i = 0; i < 12 && width - low > 0.5; i++) {
          final mid = (low + width) / 2;
          painter.layout(maxWidth: mid);
          painter.didExceedMaxLines ? low = mid : width = mid;
        }
        width = width.ceilToDouble();
      }
      return _measured[key] = width;
    }

    var widest = 0.0;
    for (final duty in duties) {
      widest = math.max(widest, measure(duty, dutyStyle, 2));
    }
    final wanted = duties.toSet();
    final names = <double>[
      for (final day in days)
        for (final d in day.duties)
          if (wanted.contains(d.role))
            for (final name in _twoOrCount(d.people).shown) measure(name, nameStyle, 1),
    ]..sort();
    // As wide as most of them: the longest tenth are cut short rather than
    // every column widened for them.
    if (names.isNotEmpty) widest = math.max(widest, names[names.length - 1 - names.length ~/ 10]);
    painter.dispose();
    if (_measured.length > 2000) _measured.clear();
    // As the cells pad, with a pixel to spare.
    return (widest + Space.s * 2 + 1).clamp(_narrowest, _widest);
  }

  /// The table: the duties' names stay at the top and the dates at the
  /// start, the rest scrolls both ways; each month starts under its name.
  /// Only the cells on screen are built, however many months there are.
  Widget _table(
    BuildContext context,
    List<({Day month, List<Roster> days})> months,
    List<String> duties,
    List<Roster> everyArranged,
  ) {
    final c = AppColors.of(context);
    final scale = MediaQuery.textScalerOf(context);
    final platform = Theme.of(context).platform;
    final today = ref.watch(todayProvider);
    // Two lines of names; a day's number and two lines under it.
    final rowHeight = [
      Space.minTap(platform) + Space.s,
      scale.scale(15) * 1.3 * 2 + Space.m,
      _DateCell.heightAt(scale),
    ].reduce(math.max);
    final monthHeight = scale.scale(17) * 1.3 + Space.m + Space.s;
    final line = BorderSide(color: c.separator, width: 0.5);

    final everyone = widget.readOnly
        ? const <String, UnavailableDays>{}
        : ref.watch(unavailableDaysProvider).value ?? const <String, UnavailableDays>{};
    final me = ref.watch(uidProvider);
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
    final columnWidth = _columnWidth(context, duties, everyArranged);

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
              onTap: () => _openDay(day),
            ),
          );
        case final Roster day when day.noService:
          // 沒有聚會 across the row, from the first duty's cell; nothing to
          // pick or drop on. Tapping opens the day, where it is undone.
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openDay(day),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.background,
                border: Border(bottom: line),
              ),
              child: role != duties.first
                  ? const SizedBox.expand()
                  : OverflowBox(
                      minWidth: 0,
                      maxWidth: double.infinity,
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.s),
                        child: Text(
                          L10n.of(context).noService,
                          style: AppText.subheadline.copyWith(color: c.secondaryLabel),
                        ),
                      ),
                    ),
            ),
          );
        case final Roster day when widget.readOnly:
          return _ViewCell(roster: day, role: role!, today: today, border: line, me: me);
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
            unavailable: _unavailableNames(day, role, everyone),
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
        final fits = duties.isNotEmpty && room / duties.length >= columnWidth;
        final whole = (room / columnWidth - _peek).floor().clamp(1, math.max(1, duties.length));
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
        // The cut column fades out at the edge while there is more that way.
        // Always in a Stack, the fade clear when they all fit: switching to
        // a service that fits would otherwise move the table, building a
        // second one while the first still holds the scroll, and the fade
        // reading it then failed (a grey strip down the edge in release).
        final cut = !fits && duties.isNotEmpty;
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
                    opacity: switch (_cells.positions.toList()) {
                      _ when !cut => 0,
                      [final ScrollPosition at] when at.hasContentDimensions => at.extentAfter > 1 ? 1 : 0,
                      _ => 1,
                    },
                    // Gone at once on a table that fits, not fading out over it.
                    duration: cut ? const Duration(milliseconds: 150) : Duration.zero,
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
    return table;
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

/// Two lines of a cell: both of two, or past two the first and how many
/// more on the second: a second name and a count do not fit one line of a
/// narrow column.
({List<T> shown, int more}) _twoOrCount<T>(List<T> all) =>
    all.length <= 2 ? (shown: all, more: 0) : (shown: [all.first], more: all.length - 1);

/// A day at the start of its row, as a calendar has it under its month:
/// the day's number, then its weekday or its 特別活動, each a line in its
/// color, as many as [_twoOrCount] says. Tapping it opens the day, where
/// they are in full.
class _DateCell extends StatelessWidget {
  static const dayStyle = AppText.title3;
  static const weekdayStyle = AppText.caption;
  static final eventStyle = AppText.caption.copyWith(fontWeight: FontWeight.w600);

  /// Measured for how much of a 特別活動's name a line shows: most are
  /// four characters or so, the rest are cut short.
  static const eventRuler = '特別活動';

  /// The same for every day, however long their 特別活動: the room is the
  /// duties'. Wide enough for the day's number, the weekdays of [days] and
  /// [eventRuler], up to 140 at the largest text.
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

    final labels = <(String, TextStyle)>{
      ('30', dayStyle),
      (eventRuler, eventStyle),
      for (final day in days) (DateFormat.E().format(day.day.midnight), weekdayStyle),
    };
    var widest = 0.0;
    for (final (text, style) in labels) {
      widest = math.max(widest, widthOf(text, style));
    }
    painter.dispose();
    return math.min(140, (Space.m + widest + Space.xs).ceilToDouble());
  }

  /// The day's number is set tighter than [dayStyle]'s own.
  static const dayHeight = 1.1;

  /// How tall the day's number and two lines under it are, at [scale], with
  /// the row's line under them.
  static double heightAt(TextScaler scale) =>
      scale.scale(dayStyle.fontSize!) * dayHeight + scale.scale(eventStyle.fontSize!) * eventStyle.height! * 2 + 1;

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
    final events = roster.events;
    Text event(EventTag tag, {int lines = 1}) => Text(
      tag.name,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: eventStyle.copyWith(color: EventColors.of(context, tag.color).fg),
    );
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
                style: dayStyle.copyWith(
                  color: roster.noService
                      ? c.secondaryLabel
                      : day == today
                      ? c.accent
                      : c.label,
                  height: dayHeight,
                ),
              ),
              if (events.isEmpty)
                Text(
                  DateFormat.E().format(day.midnight),
                  maxLines: 1,
                  style: weekdayStyle.copyWith(color: c.secondaryLabel),
                )
              else if (_twoOrCount(events) case (:final shown, :final more)) ...[
                // One alone may take both lines.
                for (final tag in shown) event(tag, lines: shown.length == 1 ? 2 : 1),
                if (more > 0) Text('+$more', maxLines: 1, style: eventStyle.copyWith(color: c.secondaryLabel)),
              ],
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
    this.unavailable = const {},
  });

  final Roster roster;

  /// Who is on it but marked the day as one they cannot serve (#91): their
  /// names are greyed.
  final Set<String> unavailable;
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
    final text = duty == null
        ? '—'
        : (people.isEmpty
              ? l10n.nobodyYet
              : [
                  for (final n in people) unavailable.contains(n) ? '$n, ${l10n.pickerUnavailable}' : n,
                ].join(l10n.listSeparator));
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
              : _People(people, unavailable: unavailable),
        ),
      ),
    );
  }
}

/// Who is on [role] that day, only to look at (表格): 待定 for nobody yet,
/// and marked when [me] is on it.
class _ViewCell extends StatelessWidget {
  const _ViewCell({
    required this.roster,
    required this.role,
    required this.today,
    required this.border,
    required this.me,
  });

  final Roster roster;
  final String role;
  final Day today;
  final BorderSide border;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final duty = roster.duties.where((d) => d.role == role).firstOrNull;
    final people = duty?.people ?? const <String>[];
    final mine = {
      for (final n in people)
        if (me != null && duty!.uids[n] == me) n,
    };
    return Semantics(
      label: '$role, ${dayLabel(l10n, roster.day, today)}',
      value: duty == null ? '—' : (people.isEmpty ? l10n.nobodyYet : people.join(l10n.listSeparator)),
      selected: mine.isNotEmpty,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          color: mine.isEmpty ? null : c.accentSoft,
          border: Border(bottom: border),
        ),
        child: switch (duty) {
          null => Text('—', style: AppText.subheadline.copyWith(color: c.tertiaryLabel)),
          _ when people.isEmpty => Text(l10n.nobodyYet, style: AppText.subheadline.copyWith(color: c.secondaryLabel)),
          _ => _People(people, own: mine),
        },
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
/// past two, as [_twoOrCount] says.
class _People extends StatelessWidget {
  const _People(this.people, {this.unavailable = const {}, this.own = const {}});

  final List<String> people;

  /// Those of [people] who are the one looking (表格): in bold, in the
  /// accent.
  final Set<String> own;

  /// Those of [people] greyed: they marked the day as one they cannot
  /// serve (#91).
  final Set<String> unavailable;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = AppText.subheadline.copyWith(color: c.label);
    Text line(String name) => Text(
      name,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: switch (name) {
        _ when own.contains(name) => style.copyWith(color: c.accent, fontWeight: FontWeight.w700),
        _ when unavailable.contains(name) => style.copyWith(color: c.secondaryLabel),
        _ => style,
      },
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_twoOrCount(people) case (:final shown, :final more)) ...[
          for (final name in shown) line(name),
          if (more > 0) Text('+$more', maxLines: 1, style: style.copyWith(color: c.secondaryLabel)),
        ],
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
/// toast from [toasts]; a failure is said with 重試 ([onRetry]).
Future<void> _tellPlanned(
  BuildContext toasts,
  RosterActions actions,
  Set<String> types, {
  Map<String, List<String>> rosterIds = const {},
  required VoidCallback onRetry,
}) async {
  final l10n = L10n.of(toasts);
  try {
    // Side by side: each may wait for the backend to read its days.
    final told = await Future.wait([
      for (final type in types) actions.notifyPlanned(type, rosterIds: rosterIds[type] ?? const []),
    ]);
    final people = told.fold(0, (n, r) => n + r.people);
    final later = told.any((r) => r.later);
    if (toasts.mounted && people > 0) {
      showToast(toasts, later ? l10n.planNotifiedLater(people) : l10n.planNotified(people));
    }
  } catch (e) {
    if (toasts.mounted) showToast(toasts, errorText(l10n, e), onRetry: onRetry);
  }
}

/// 要問哪幾個月 (#91): [months] in a grid by year, [arranged] ones marked
/// 已排好, [first] picked to start. A tap on or after the start ends the
/// months there; before it, or once they have an end, starts them anew.
/// The button says the months and pops them. [round], the last ask, opens
/// it ([onRound]).
class _AskMonths extends StatefulWidget {
  const _AskMonths({
    required this.months,
    required this.arranged,
    required this.first,
    required this.round,
    required this.onRound,
  });

  final List<Day> months;
  final Set<Day> arranged;
  final Day first;
  final String? round;
  final VoidCallback onRound;

  @override
  State<_AskMonths> createState() => _AskMonthsState();
}

class _AskMonthsState extends State<_AskMonths> {
  late Day _start = widget.first;
  Day? _end;

  void _tap(Day month) {
    Haptics.selection();
    setState(() {
      if (_end == null && !month.isBefore(_start)) {
        _end = month;
      } else {
        _start = month;
        _end = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final end = _end ?? _start;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.planAskWhich, style: AppText.headline, textAlign: TextAlign.center),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs, bottom: Space.s),
            child: Text(
              l10n.planAskPick,
              style: AppText.footnote.copyWith(color: c.secondaryLabel),
              textAlign: TextAlign.center,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.round case final round?)
                    ListSection(
                      children: [ListRow(title: round, onTap: widget.onRound)],
                    ),
                  for (final year in {for (final m in widget.months) m.year})
                    _MonthGrid(
                      year: year,
                      months: [
                        for (final m in widget.months)
                          if (m.year == year) m,
                      ],
                      start: _start,
                      end: _end,
                      arranged: widget.arranged,
                      onPick: _tap,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
            child: PrimaryButton(
              label: l10n.planAskNotifyMonths(monthsLabel(l10n, _start, end)),
              onPressed: () => Navigator.pop(context, (_start, end)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One year's [months] of [_AskMonths], four to a row: [start] to [end]
/// filled, those between tinted; under a month 開始, 結束 or 已排好.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.months,
    required this.start,
    required this.end,
    required this.arranged,
    required this.onPick,
  });

  final int year;
  final List<Day> months;
  final Day start;
  final Day? end;
  final Set<Day> arranged;
  final ValueChanged<Day> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final year = DateFormat.y().format(DateTime(this.year));
    final last = end ?? start;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: Text(year, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.m)),
            child: Padding(
              padding: const EdgeInsets.all(Space.m - Space.xs),
              child: LayoutBuilder(
                builder: (context, box) {
                  final width = (box.maxWidth - 3 * Space.s) / 4;
                  return Wrap(
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      for (final month in months)
                        () {
                          final edge = month == start || month == end;
                          final inside = month.isAfter(start) && month.isBefore(last);
                          final note = month == start
                              ? l10n.planAskStart
                              : month == end
                              ? l10n.planAskEnd
                              : arranged.contains(month)
                              ? l10n.planMonthArranged
                              : null;
                          // 已排好 and not picked: outlined and grey, as asked less.
                          final done = !edge && !inside && arranged.contains(month);
                          final ink = edge
                              ? c.onAccent
                              : inside
                              ? c.accent
                              : done
                              ? c.secondaryLabel
                              : c.label;
                          final shape = RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.s + 2),
                            side: done ? BorderSide(color: c.separator) : BorderSide.none,
                          );
                          return SizedBox(
                            width: width,
                            height: Space.minTap(Theme.of(context).platform) + Space.s,
                            child: Semantics(
                              button: true,
                              selected: edge || inside,
                              label: [DateFormat.yMMMM().format(month.midnight), ?note].join(', '),
                              excludeSemantics: true,
                              child: Material(
                                color: edge
                                    ? c.accent
                                    : inside
                                    ? c.accentSoft
                                    : done
                                    ? c.surface
                                    : c.background,
                                shape: shape,
                                child: InkWell(
                                  customBorder: shape,
                                  onTap: () => onPick(month),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        DateFormat.MMM().format(month.midnight),
                                        style: AppText.body.copyWith(
                                          color: ink,
                                          fontWeight: edge ? FontWeight.w600 : null,
                                        ),
                                        maxLines: 1,
                                      ),
                                      if (note != null)
                                        Text(
                                          note,
                                          style: AppText.caption2.copyWith(color: ink),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }(),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
