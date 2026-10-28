import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/plan_weeks.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../common/errors.dart';
import '../common/saving_indicator.dart';
import 'format.dart';
import 'roster_day_screen.dart';

/// 排好幾週 (#90): one service's days a month at a time, a row a day and a
/// column a duty I arrange. Tapping a cell picks its people as on the
/// day's page, saved at once; tapping a date opens that day. Nobody is
/// told until 通知同工, which tells each person once, for all their days.
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

class _PlanWeeksScreenState extends ConsumerState<PlanWeeksScreen> {
  late String _type = widget.serviceType;

  /// The first month shown (its first day); null until the days are in.
  Day? _from;
  int _months = _monthsAtATime;
  bool _notifying = false;

  // The duties' names scroll sideways with the cells under them.
  final _cells = ScrollController();
  final _names = ScrollController();

  @override
  void initState() {
    super.initState();
    _cells.addListener(() {
      if (_names.hasClients) _names.jumpTo(_cells.offset);
    });
  }

  @override
  void dispose() {
    _cells.dispose();
    _names.dispose();
    super.dispose();
  }

  Future<void> _notify() async {
    final l10n = L10n.of(context);
    setState(() => _notifying = true);
    try {
      final r = await ref.read(rosterActionsProvider).notifyPlanned(_type);
      if (!mounted) return;
      showToast(context, r.later ? l10n.planNotifiedLater(r.people) : l10n.planNotified(r.people));
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e), onRetry: _notify);
    } finally {
      if (mounted) setState(() => _notifying = false);
    }
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
    final news = ref.watch(plannedNewsProvider(_type)).value ?? false;

    Widget body;
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
      final duties = planDuties(service, months.expand((m) => m.days), arranges);
      body = _table(context, months, duties, earlier: from.isAfter(thisMonth) ? thisMonth : null);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.planWeeksTitle),
        actions: savingActions([
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: TextButton(
              onPressed: news && !_notifying ? _notify : null,
              child: Text(l10n.planNotify),
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
          Expanded(child: body),
        ],
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
    final dateWidth = (scale.scale(15) * 4 + Space.m).clamp(76.0, 132.0);
    final line = BorderSide(color: c.separator, width: 0.5);

    return LayoutBuilder(
      builder: (context, box) {
        final cellWidth = duties.isEmpty ? 0.0 : math.max(104.0, (box.maxWidth - dateWidth) / duties.length);
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
                color: c.background,
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
                      roster: day,
                      role: role,
                      today: today,
                      width: cellWidth,
                      height: rowHeight,
                      border: line,
                      onTap: (duty) => pickPeople(context, ref, day, duty, via: 'plan'),
                    ),
                ],
              ),
            );
            y += rowHeight;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
      },
    );
  }
}

/// A day at the start of its row: the date, its weekday and its first
/// 特別活動. Tapping it opens the day.
class _DateCell extends StatelessWidget {
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
    return Semantics(
      button: true,
      label: l10n.planOpenDay(dayLabel(l10n, day, today)),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsetsDirectional.fromSTEB(Space.m, Space.xs, Space.xs, Space.xs),
          decoration: BoxDecoration(
            border: Border(bottom: border, right: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat.Md().format(day.midnight),
                maxLines: 1,
                style: AppText.subheadline.copyWith(
                  fontWeight: FontWeight.w600,
                  color: day == today ? c.accent : c.label,
                ),
              ),
              if (roster.events.isEmpty)
                Text(
                  DateFormat.E().format(day.midnight),
                  maxLines: 1,
                  style: AppText.footnote.copyWith(color: c.secondaryLabel),
                )
              else
                Flexible(
                  child: Tag.event(
                    context,
                    roster.events.length == 1
                        ? roster.events.first.name
                        : '${roster.events.first.name} +${roster.events.length - 1}',
                    roster.events.first.color,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who is on [role] that day. Tapping picks them; a day without the duty
/// shows a dash and is changed on the day's own page.
class _DutyCell extends StatelessWidget {
  const _DutyCell({
    required this.roster,
    required this.role,
    required this.today,
    required this.width,
    required this.height,
    required this.border,
    required this.onTap,
  });

  final Roster roster;
  final String role;
  final Day today;
  final double width;
  final double height;
  final BorderSide border;
  final ValueChanged<Duty> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final duty = roster.duties.where((d) => d.role == role).firstOrNull;
    final names = duty?.people.join(l10n.listSeparator) ?? '';
    final text = duty == null ? '—' : (names.isEmpty ? l10n.nobodyYet : names);
    return Semantics(
      button: duty != null,
      label: '$role, ${dayLabel(l10n, roster.day, today)}',
      value: text,
      excludeSemantics: true,
      child: InkWell(
        onTap: duty == null ? null : () => onTap(duty),
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
          alignment: AlignmentDirectional.centerStart,
          decoration: BoxDecoration(
            border: Border(bottom: border, right: border),
          ),
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.subheadline.copyWith(
              color: duty == null
                  ? c.tertiaryLabel
                  : names.isEmpty
                  ? c.secondaryLabel
                  : c.label,
            ),
          ),
        ),
      ),
    );
  }
}
