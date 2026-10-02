import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/roster_edit.dart';
import '../../domain/schedule.dart';
import '../../domain/staff_order.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../common/errors.dart';
import 'event_sheet.dart';
import 'format.dart';
import 'people_picker.dart';
import 'roster_card.dart';

/// One service on one day. Everyone can look; people who may arrange this
/// service's rosters (admin, or roster-editors holding its zone) tap a duty
/// to pick people, a name to swap or remove it, and use the menu for duties
/// and special events. Every change saves at once and can be undone.
class RosterDayScreen extends ConsumerWidget {
  const RosterDayScreen({
    super.key,
    required this.serviceType,
    required this.dayKey,
  });

  final String serviceType;
  final String dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final day = Day.tryParse(dayKey);
    final service = ref.watch(
      servicesProvider.select((s) => s.value?.byId(serviceType)),
    );
    final rosters = ref.watch(serviceRostersProvider(serviceType));
    final today = ref.watch(todayProvider);
    if (day == null || service == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final roster = rosters.value?.where((r) => r.day == day).firstOrNull ?? draftRoster(service, day);
    final canEdit = ref.watch(
      meProvider.select((m) => m.value?.canEditRosters(serviceType) ?? false),
    );
    if (canEdit) {
      // Keep the member list and staff order loaded, so the picker opens at
      // once with everything already in memory.
      ref.watch(membersProvider);
      ref.watch(staffOrderProvider(serviceType));
    }
    final title = dayLabel(l10n, day, today);

    return Scaffold(
      appBar: AppBar(
        title: Text(service.name),
        actions: [
          if (canEdit)
            PopupMenuButton<String>(
              tooltip: l10n.edit,
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) => switch (v) {
                'duty' => _addDuty(context, ref, roster, service),
                'events' => _editEvents(context, ref, roster, service),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'duty', child: Text(l10n.addDuty)),
                PopupMenuItem(value: 'events', child: Text(l10n.events)),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          if (!canEdit)
            RosterDayView(
              roster: roster,
              title: title,
              highlightUid: ref.watch(uidProvider),
              highlightName: ref.watch(meProvider.select((m) => m.value?.name)),
            )
          else
            _EditableDay(roster: roster, service: service, title: title),
        ],
      ),
    );
  }

  Future<void> _addDuty(
    BuildContext context,
    WidgetRef ref,
    Roster roster,
    Service service,
  ) async {
    final l10n = L10n.of(context);
    final present = {for (final d in roster.duties) d.role};
    final suggestions = [
      for (final d in service.duties)
        if (!present.contains(d)) d,
    ];
    final role = await showAppSheet<String>(
      context,
      builder: (context) => _AddDutySheet(suggestions: suggestions),
    );
    if (role == null || role.trim().isEmpty || present.contains(role.trim())) {
      return;
    }
    if (!context.mounted) return;
    await runWithUndo(
      context,
      l10n.dutyUpdated(role.trim()),
      () => ref.read(rosterActionsProvider).addDuty(roster, role.trim()),
    );
  }

  Future<void> _editEvents(
    BuildContext context,
    WidgetRef ref,
    Roster roster,
    Service service,
  ) async {
    final l10n = L10n.of(context);
    final isAdmin = ref.read(meProvider).value?.isAdmin ?? false;
    final result = await showAppSheet<EventSheetResult>(
      context,
      builder: (context) => EventSheet(
        options: service.events,
        selected: roster.events,
        canAddToCommon: isAdmin,
      ),
    );
    if (result == null || !context.mounted) return;
    if (result.addToCommon.isNotEmpty) {
      final settings = ref.read(servicesProvider).value!;
      await ref.read(churchDataProvider)!.saveServices([
        for (final s in settings.services)
          s.id == service.id ? s.copyWith(events: [...s.events, ...result.addToCommon]) : s,
      ]);
    }
    if (!context.mounted) return;
    await runWithUndo(
      context,
      l10n.events,
      () => ref.read(rosterActionsProvider).setEvents(roster, result.events),
    );
  }
}

/// Runs a write that returns its own undo, then shows 「復原」 for it.
Future<void> runWithUndo(
  BuildContext context,
  String message,
  Future<Future<void> Function()> Function() write,
) async {
  final l10n = L10n.of(context);
  try {
    final undo = await write();
    Haptics.success();
    if (!context.mounted) return;
    showToast(
      context,
      message,
      onUndo: () => undo().catchError((Object e) {
        if (context.mounted) showToast(context, errorText(l10n, e));
      }),
    );
  } catch (e) {
    if (context.mounted) showToast(context, l10n.saveFailed);
  }
}

class _EditableDay extends ConsumerWidget {
  const _EditableDay({
    required this.roster,
    required this.service,
    required this.title,
  });

  final Roster roster;
  final Service service;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          child: Text(title, style: AppText.title2),
        ),
        if (roster.events.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
            child: Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final e in roster.events) Tag.event(context, e.name, e.color),
              ],
            ),
          ),
        ListSection(
          children: [
            for (final duty in roster.duties)
              Dismissible(
                key: ValueKey('${roster.id}/${duty.role}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: c.destructive,
                  alignment: AlignmentDirectional.centerEnd,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Text(
                    l10n.delete,
                    style: AppText.body.copyWith(color: c.onAccent),
                  ),
                ),
                onDismissed: (_) => runWithUndo(
                  context,
                  l10n.dutyRemoved(duty.role),
                  () => ref.read(rosterActionsProvider).removeDuty(roster, duty.role),
                ),
                child: _DutyRow(roster: roster, duty: duty),
              ),
          ],
        ),
        if (roster.duties.isEmpty) EmptyState(message: l10n.addDuty),
      ],
    );
  }
}

class _DutyRow extends ConsumerWidget {
  const _DutyRow({required this.roster, required this.duty});

  final Roster roster;
  final Duty duty;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final members = ref.read(membersProvider).value ?? const <Member>[];
    final order = ref.read(staffOrderProvider(roster.type)).value ?? StaffOrder();
    final me = ref.read(meProvider).value;
    PickerResult? latest;
    final returned = await showAppSheet<PickerResult>(
      context,
      expand: true,
      builder: (_) => PeoplePicker(
        serviceType: roster.type,
        duty: duty.role,
        initial: duty.people,
        members: members,
        order: order,
        canGrantDuty: me?.isAdmin ?? false,
        canReorder: true,
        canRemove: true,
        onChanged: (r) => latest = r,
      ),
    );
    final result = returned ?? latest;
    if (result == null || !context.mounted) return;
    final actions = ref.read(rosterActionsProvider);
    if (result.removeDuty) {
      await runWithUndo(context, l10n.dutyRemoved(duty.role), () => actions.removeDuty(roster, duty.role));
      return;
    }
    try {
      for (final m in result.addDutyTo) {
        await actions.grantDuty(m, roster.type, duty.role);
      }
      if (result.ranking != null) {
        await actions.setRanking(roster.type, duty.role, result.ranking!);
        if (context.mounted) showToast(context, l10n.orderSaved);
      }
    } catch (_) {
      if (context.mounted) showToast(context, l10n.saveFailed);
    }
    final changed = result.people.length != duty.people.length || !result.people.toSet().containsAll(duty.people);
    if (!changed || !context.mounted) return;
    await runWithUndo(
      context,
      l10n.dutyUpdated(duty.role),
      () => actions.setPeople(roster, duty.role, result.people),
    );
  }

  Future<void> _personMenu(
    BuildContext context,
    WidgetRef ref,
    String person,
  ) async {
    final l10n = L10n.of(context);
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: ListSection(
          header: person,
          children: [
            ListRow(
              title: l10n.swap,
              leading: const Icon(Icons.swap_horiz),
              onTap: () => Navigator.pop(context, 'swap'),
            ),
            ListRow(
              title: l10n.removeFromDuty(duty.role),
              destructive: true,
              leading: const Icon(Icons.remove_circle_outline),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'remove') {
      await runWithUndo(
        context,
        l10n.removed(person),
        () => ref.read(rosterActionsProvider).setPeople(roster, duty.role, [
          for (final p in duty.people)
            if (p != person) p,
        ]),
      );
    } else if (choice == 'swap') {
      await _swap(context, ref, person);
    }
  }

  Future<void> _swap(BuildContext context, WidgetRef ref, String person) async {
    final l10n = L10n.of(context);
    final today = ref.read(todayProvider);
    final days = ref.read(serviceRostersProvider(roster.type)).value ?? const <Roster>[];
    final targets = swapTargets(days, roster, duty.role, person);
    final target = await showAppSheet<SwapSide>(
      context,
      expand: targets.length > 6,
      builder: (context) => _SwapSheet(
        title: l10n.swapWith(duty.role),
        targets: targets,
        today: today,
      ),
    );
    if (target == null || !context.mounted) return;
    final message = target.person == null
        ? l10n.moved(person, dayLabel(l10n, target.roster.day, today))
        : l10n.swapped(person, target.person!);
    await runWithUndo(
      context,
      message,
      () => ref.read(rosterActionsProvider).swap(duty.role, SwapSide(roster, person), target),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final platform = Theme.of(context).platform;
    return InkWell(
      onTap: () => _pick(context, ref),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: Space.minTap(platform)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.m,
            vertical: Space.s,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  duty.role,
                  style: AppText.subheadline.copyWith(color: c.secondaryLabel),
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: duty.people.isEmpty
                    ? Text(
                        l10n.nobodyYet,
                        style: AppText.body.copyWith(color: c.secondaryLabel),
                      )
                    : Wrap(
                        spacing: Space.xs,
                        runSpacing: Space.xs,
                        children: [
                          for (final p in duty.people)
                            _NameButton(
                              name: p,
                              onTap: () => _personMenu(context, ref, p),
                            ),
                        ],
                      ),
              ),
              Icon(Icons.chevron_right, color: c.tertiaryLabel, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// A name inside a duty row: its own tap target for swap and remove.
class _NameButton extends StatelessWidget {
  const _NameButton({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.s),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 6),
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: BorderRadius.circular(Radii.s),
          ),
          child: Text(name, style: AppText.body),
        ),
      ),
    );
  }
}

class _SwapSheet extends StatelessWidget {
  const _SwapSheet({
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

class _AddDutySheet extends StatefulWidget {
  const _AddDutySheet({required this.suggestions});

  final List<String> suggestions;

  @override
  State<_AddDutySheet> createState() => _AddDutySheetState();
}

class _AddDutySheetState extends State<_AddDutySheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (widget.suggestions.isNotEmpty)
              ListSection(
                header: l10n.addDuty,
                children: [
                  for (final s in widget.suggestions)
                    ListRow(
                      title: s,
                      leading: const Icon(Icons.add),
                      onTap: () => Navigator.pop(context, s),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.m,
                Space.s,
                Space.m,
                Space.m,
              ),
              child: TextField(
                controller: _name,
                autofocus: widget.suggestions.isEmpty,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(hintText: l10n.dutyName),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
