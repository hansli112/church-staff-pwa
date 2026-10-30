/// Picking people for a duty, or trading it with another day, and saving
/// it with 復原: from a day's page, an event's, and 安排服事 (#90).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/roster_edit.dart';
import '../../domain/roster_news.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../common/errors.dart';
import 'format.dart';
import 'future_changes.dart';
import 'people_picker.dart';

/// Opens the picker for [duty] on [roster] and saves what was picked: the
/// day page's, and 安排服事's (#90), whose changes go [via] `plan`.
/// [swapDays]: the days of 安排服事 the duty can be traded with, from the
/// picker (#90).
Future<void> pickPeople(
  BuildContext context,
  WidgetRef ref,
  Roster roster,
  Duty duty, {
  RosterVia via = RosterVia.app,
  List<Roster> swapDays = const [],
}) async {
  final members = ref.read(membersProvider).requireValue;
  final order = ref.read(rosterActionsProvider).orderOf(roster);
  final me = ref.read(meProvider).value;
  final router = GoRouter.of(context);
  final l10n = L10n.of(context);
  final around = ref.read(rosterActionsProvider).servingAroundOf(roster);
  final notes = <String, String>{
    for (final m in members)
      if (around[m.uid] case final a? when !a.isEmpty)
        m.name: [
          if (a.inMonth > 0) l10n.pickerMonthCount(a.inMonth),
          for (final o in a.sameDay) l10n.pickerSameDay('${o.name} ${o.duties.join(l10n.listSeparator)}'),
        ].join(' · '),
  };
  var invite = false;
  final result = await showAppSheet<PickerResult>(
    context,
    expand: true,
    builder: (_) => PeoplePicker(
      serviceType: roster.isEvent ? null : roster.type,
      duty: duty.role,
      initial: duty.people,
      initialGuests: {
        for (final name in duty.people)
          if (!duty.uids.containsKey(name)) name,
      },
      guestSuggestions: ref
          .read(rosterActionsProvider)
          .guestSuggestions(roster.isEvent ? null : roster.type, duty.role),
      members: members,
      order: order,
      // An event is in no 牧區 to add the duty to, and has no staff
      // order of its own to drag.
      canEditDutyList: !roster.isEvent && (me?.editsServiceSettings ?? false),
      // The staff order is the whole service's: not a 事工 leader's.
      canReorder: !roster.isEvent && ref.read(arrangesProvider(roster.type)).all,
      canRemove: true,
      canSwapDay: swapDays.any((d) => canSwapDuty(duty.role, roster, d)),
      onePerson: ref.read(rosterActionsProvider).takesOnePerson(roster, duty.role),
      onInvite: (me?.isAdmin ?? false) ? () => invite = true : null,
      notes: notes,
    ),
  );
  if (result != null && context.mounted) {
    if (result.swapDay) {
      await pickDayToSwap(context, ref, roster, duty, swapDays, via: via);
    } else {
      await _savePicked(context, ref, roster, duty, result, via);
    }
  }
  if (invite) unawaited(router.push('/me/invites'));
}

/// 和別週交換: which of [days] to trade [duty] on [roster] with, then
/// traded.
Future<void> pickDayToSwap(
  BuildContext context,
  WidgetRef ref,
  Roster roster,
  Duty duty,
  List<Roster> days, {
  required RosterVia via,
}) async {
  final l10n = L10n.of(context);
  String? onIt(Roster d) {
    final people = d.duties.firstWhere((x) => x.role == duty.role).people;
    return people.isEmpty ? null : people.join(l10n.listSeparator);
  }

  final targets = [
    for (final d in days)
      if (canSwapDuty(duty.role, roster, d)) SwapSide(d, onIt(d)),
  ];
  final target = await showAppSheet<SwapSide>(
    context,
    expand: targets.length > 6,
    builder: (context) => SwapSheet(
      title: l10n.swapWith(duty.role),
      targets: targets,
      today: ref.read(todayProvider),
    ),
  );
  if (target == null || !context.mounted) return;
  await swapDutyDays(context, ref, duty.role, roster, target.roster, via: via);
}

/// Trades whoever is on [role] on [from] and [to] (canSwapDuty), saying
/// so with 復原: moved, when [to] had nobody. Whether it went through.
Future<bool> swapDutyDays(
  BuildContext context,
  WidgetRef ref,
  String role,
  Roster from,
  Roster to, {
  required RosterVia via,
}) {
  final l10n = L10n.of(context);
  String names(Roster r) => r.duties.firstWhere((d) => d.role == role).people.join(l10n.listSeparator);
  final (a, b) = (names(from), names(to));
  return runWithUndo(
    context,
    b.isEmpty
        ? l10n.moved(a, dayLabel(l10n, to.day, ref.read(todayProvider)))
        : a.isEmpty
        ? l10n.moved(b, dayLabel(l10n, from.day, ref.read(todayProvider)))
        : l10n.swapped(a, b),
    () => ref.read(rosterActionsProvider).swapDuty(role, from, to, via: via),
  );
}

Future<void> _savePicked(
  BuildContext context,
  WidgetRef ref,
  Roster roster,
  Duty duty,
  PickerResult result,
  RosterVia via,
) async {
  final l10n = L10n.of(context);
  final actions = ref.read(rosterActionsProvider);
  if (result.removeDuty) {
    await runWithUndo(context, l10n.dutyRemoved(duty.role), () => actions.removeDuty(roster, duty.role, via: via));
    return;
  }
  // Not waited for: changes go to the backend in turn, and the pick
  // shows at once. One that fails says so.
  if (result.addDutyTo.isNotEmpty || result.takeDutyFrom.isNotEmpty) {
    unawaited(
      Future.wait([
        for (final m in result.addDutyTo) actions.grantDuty(m, roster.type, duty.role),
        for (final m in result.takeDutyFrom) actions.revokeDuty(m, roster.type, duty.role),
      ]).then(
        (_) {},
        onError: (Object error) {
          if (context.mounted) showToast(context, errorText(l10n, error));
        },
      ),
    );
  }
  final changed = pickChanges(duty, result.people, guestNames: result.guestNames);
  if (!context.mounted || (!changed && result.ranking == null)) return;
  await runWithUndo(
    context,
    changed ? l10n.dutyUpdated(duty.role) : l10n.orderSaved,
    () => actions.setPeople(
      roster,
      duty.role,
      result.people,
      guestNames: result.guestNames,
      ranking: result.ranking,
      via: via,
    ),
  );
  // Taken off the list alone: say so, with a way back. With the day
  // changed too, the day's 復原 comes first.
  if (result.takeDutyFrom.isEmpty || changed || !context.mounted) return;
  final taken = result.takeDutyFrom;
  showToast(
    context,
    l10n.dutyListRemoved(duty.role, {for (final m in taken) m.name}.join(l10n.listSeparator)),
    onUndo: () => Future.wait([for (final m in taken) actions.grantDuty(m, roster.type, duty.role)]),
  );
}

/// Which day to move or trade a duty to: [targets], each with who is on
/// it there.
class SwapSheet extends StatelessWidget {
  const SwapSheet({
    super.key,
    required this.title,
    required this.targets,
    required this.today,
  });

  final String title;
  final List<SwapSide> targets;
  final Day today;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (targets.isEmpty) {
      return SafeArea(
        child: SizedBox(height: 200, child: EmptyState(message: l10n.swapNone)),
      );
    }
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListSection(
            header: title,
            children: [
              for (final t in targets)
                ListRow(
                  title: t.person ?? l10n.emptySlot,
                  value: dayLabel(l10n, t.roster.day, today),
                  onTap: () => Navigator.pop(context, t),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
