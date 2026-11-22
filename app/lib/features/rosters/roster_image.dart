/// 分享成圖片 (2026-11-19): a month of a service's roster as a picture to
/// send to a group chat, from 安排服事's ⋯. One row a duty and one column a
/// day, so it is tall like a phone; only the names arranged, nothing of
/// who cannot serve.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/plan_weeks.dart';
import '../../l10n/app_localizations.dart';
import '../../state/export.dart';
import '../../state/providers.dart';
import '../common/errors.dart';

/// Opens the picture of [serviceType]'s roster in [month] (its first day),
/// the months around it a tap away, to share: the duties I arrange, or
/// with [everyDuty] (表格) all of them.
Future<void> showRosterImage(
  BuildContext context, {
  required String serviceType,
  required Day month,
  bool everyDuty = false,
}) => showAppSheet<void>(
  context,
  builder: (_) => _RosterImageSheet(serviceType: serviceType, month: month, everyDuty: everyDuty),
);

/// What was saved in [month] (its first day) before today, which
/// savedRostersProvider leaves out: a month gone by, or this one's first
/// weeks, arranged.
final _pastInMonthProvider = FutureProvider.autoDispose.family<List<Roster>, Day>((ref, month) async {
  final today = ref.watch(todayProvider);
  if (!month.isBefore(today)) return const [];
  final end = addMonths(month, 1);
  return openChurch(ref).pastRosters(from: month, before: end.isBefore(today) ? end : today);
});

class _RosterImageSheet extends ConsumerStatefulWidget {
  const _RosterImageSheet({required this.serviceType, required this.month, required this.everyDuty});

  final String serviceType;
  final Day month;
  final bool everyDuty;

  @override
  ConsumerState<_RosterImageSheet> createState() => _RosterImageSheetState();
}

class _RosterImageSheetState extends ConsumerState<_RosterImageSheet> {
  late Day _month = widget.month;
  final _picture = GlobalKey();
  bool _sharing = false;

  Future<void> _share(String name) async {
    final boundary = _picture.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null || !mounted) return;
      await ref.read(fileSaverProvider).save('$name.png', png.buffer.asUint8List(), 'image/png');
    } catch (e) {
      if (mounted) showToast(context, errorText(L10n.of(context), e));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final service = ref.watch(servicesProvider).value?.byId(widget.serviceType);
    final upcoming = ref.watch(savedRostersProvider).value;
    final past = ref.watch(_pastInMonthProvider(_month));
    // Its past weeks too, once read; without them if they cannot be.
    final saved = upcoming == null || past.isLoading ? null : [...?past.value, ...upcoming];
    final arranges = widget.everyDuty ? const Arranges.all() : ref.watch(arrangesProvider(widget.serviceType));
    final church = ref.watch(churchProvider).value?.name ?? '';
    final monthName = DateFormat.yMMMM().format(_month.midnight);
    final today = ref.watch(todayProvider);
    final savedIds = {for (final r in saved ?? const <Roster>[]) r.id};
    final days = [
      if (service != null && saved != null)
        for (final r
            in planMonths(service: service, saved: saved, today: _month, month: _month, months: 1).firstOrNull?.days ??
                const <Roster>[])
          // A day gone by that nobody arranged is no row of empty cells.
          if (!r.day.isBefore(today) || savedIds.contains(r.id)) r,
    ];
    final duties = service == null ? const <String>[] : planDuties(service, days, arranges);
    final title = l10n.rosterImageTitle(service?.name ?? '', monthName);
    // As tall as the picture: 分享 right under it, not at the screen's foot.
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetBar(
            title: l10n.rosterShareImage,
            cancel: false,
            actions: [SecondaryButton(label: l10n.done, onPressed: () => Navigator.pop(context))],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.calPrevMonth,
                icon: const Icon(Symbols.chevron_left_rounded),
                onPressed: () => setState(() => _month = addMonths(_month, -1)),
              ),
              SizedBox(
                width: 160,
                child: Text(monthName, textAlign: TextAlign.center, style: AppText.headline),
              ),
              IconButton(
                tooltip: l10n.calNextMonth,
                icon: const Icon(Symbols.chevron_right_rounded),
                onPressed: () => setState(() => _month = addMonths(_month, 1)),
              ),
            ],
          ),
          Flexible(
            child: Container(
              color: c.background,
              padding: const EdgeInsets.all(Space.m),
              // The whole picture, made smaller to fit; shared at full size.
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RepaintBoundary(
                    key: _picture,
                    child: RosterImage(church: church, title: title, days: days, duties: duties),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: PrimaryButton(
              label: l10n.share,
              busy: _sharing,
              onPressed: days.isEmpty ? null : () => _share(title),
            ),
          ),
        ],
      ),
    );
  }
}

/// The picture: the church's name, the service and month, then the table.
/// Light whatever the phone's look, as a picture is seen in a chat.
class RosterImage extends StatelessWidget {
  const RosterImage({
    super.key,
    required this.church,
    required this.title,
    required this.days,
    required this.duties,
  });

  final String church;
  final String title;
  final List<Roster> days;
  final List<String> duties;

  @override
  Widget build(BuildContext context) {
    final theme = buildTheme(Brightness.light);
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final c = AppColors.of(context);
          final line = BorderSide(color: c.separator, width: 0.5);
          Widget cell(Widget child, {bool first = false}) => Padding(
            padding: EdgeInsetsDirectional.fromSTEB(first ? 0 : Space.m, Space.s, 0, Space.s),
            child: child,
          );
          return DefaultTextStyle(
            style: AppText.body.copyWith(color: c.label),
            child: Container(
              color: c.surface,
              padding: const EdgeInsets.all(Space.l),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (church.isNotEmpty) Text(church, style: AppText.subheadline.copyWith(color: c.secondaryLabel)),
                    Text(title, style: AppText.title2),
                    const SizedBox(height: Space.m),
                    // A duty a row and a day a column (2026-11-19): a month
                    // is 4 or 5 days, so as many duties as a church has
                    // make it longer, not wider, and it reads on a phone.
                    Table(
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      defaultVerticalAlignment: TableCellVerticalAlignment.top,
                      children: [
                        TableRow(
                          decoration: BoxDecoration(border: Border(bottom: line)),
                          children: [
                            const SizedBox.shrink(),
                            for (final day in days) cell(_DayLabel(day)),
                          ],
                        ),
                        for (final duty in duties)
                          TableRow(
                            decoration: BoxDecoration(border: Border(bottom: line)),
                            children: [
                              cell(
                                first: true,
                                Text(
                                  duty,
                                  style: AppText.footnote.copyWith(
                                    color: c.secondaryLabel,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              for (final day in days)
                                cell(
                                  Text(
                                    (day.duties.where((d) => d.role == duty).firstOrNull?.people ?? const []).join(
                                      '\n',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.day);

  final Roster day;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(DateFormat.MMMd().format(day.day.midnight), style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final e in day.events)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Tag.event(context, e.name, e.color),
          ),
      ],
    );
  }
}
