/// A roster as its editors see it, on a day's page and on an event's
/// (活動的服事表): duties to tap, 新增服事項目.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import 'duty_picking.dart';
import 'future_changes.dart';

/// Whether what editing [roster] reads is loaded; watching it keeps it so.
bool _editingReady(WidgetRef ref, Roster roster) =>
    roster.isEvent ? ref.watch(eventEditingProvider) : ref.watch(rosterEditingProvider(roster.type));

/// A roster as its editors see it: tap a duty, names and all, to pick
/// people, swipe it away.
class EditableRoster extends ConsumerWidget {
  const EditableRoster({
    super.key,
    required this.roster,
    required this.title,
    this.whenEmpty,
    this.arranges = const Arranges.all(),
    this.onEditEvents,
  });

  final Roster roster;
  final String title;

  /// What I arrange here: a 事工's 負責人 only its duties, the rest only
  /// show.
  final Arranges arranges;

  /// Shown while it has no duties; by default a hint to add one.
  final Widget? whenEmpty;

  /// Opens 特別活動 from the day's tags; null for who may not change them.
  final VoidCallback? onEditEvents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final ready = _editingReady(ref, roster);
    // Read as the picker opens: who cannot serve the day (#91); and as my
    // name's menu opens, what I asked for (#92).
    ref.watch(unavailableDaysProvider);
    ref.watch(myOpenSwapRequestsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          child: Text(title, style: AppText.title2),
        ),
        if (roster.events.isNotEmpty)
          Padding(
            // Space.s less at the sides, given back inside: the tags line
            // up with the title, the ink reaches a little past them.
            padding: const EdgeInsets.fromLTRB(Space.l - Space.s, Space.xs, Space.l - Space.s, 0),
            // The tags open what they say, as 特別活動 in the menu does.
            child: Semantics(
              button: onEditEvents != null,
              hint: onEditEvents == null ? null : l10n.events,
              child: InkWell(
                onTap: ready ? onEditEvents : null,
                borderRadius: BorderRadius.circular(Radii.s),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: Space.minTap(Theme.of(context).platform)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Wrap(
                        spacing: Space.xs,
                        runSpacing: Space.xs,
                        children: [
                          for (final e in roster.events) Tag.event(context, e.name, e.color),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ListSection(
          children: [
            for (final duty in roster.duties)
              Dismissible(
                key: ValueKey('${roster.id}/${duty.role}'),
                direction: ready && arranges.has(duty.role) ? DismissDirection.endToStart : DismissDirection.none,
                background: const SwipeDeleteBackground(),
                confirmDismiss: (_) async {
                  await runWithUndo(
                    context,
                    l10n.dutyRemoved(duty.role),
                    () => ref.read(rosterActionsProvider).removeDuty(roster, duty.role),
                  );
                  return false;
                },
                child: _DutyRow(roster: roster, duty: duty, editable: arranges.has(duty.role)),
              ),
          ],
        ),
        if (roster.duties.isEmpty) whenEmpty ?? EmptyState(message: l10n.addDuty),
      ],
    );
  }
}

class _DutyRow extends ConsumerWidget {
  const _DutyRow({required this.roster, required this.duty, this.editable = true});

  final Roster roster;
  final Duty duty;

  /// False for a duty someone else arranges: it only shows.
  final bool editable;

  /// The picker, for the whole row, names and all: who is on it, 請人代
  /// on my own, 和別週交換 with the service's other days.
  Future<void> _pick(BuildContext context, WidgetRef ref) => pickPeople(
    context,
    ref,
    roster,
    duty,
    swapDays: roster.isEvent ? const [] : ref.read(serviceRostersProvider(roster.type)).value ?? const [],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final platform = Theme.of(context).platform;
    final ready = editable && _editingReady(ref, roster);
    return InkWell(
      onTap: ready ? () => _pick(context, ref) : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: Space.minTap(platform)),
        child: Padding(
          // One tap target, names and all: it opens the picker.
          padding: const EdgeInsets.symmetric(
            horizontal: Space.m,
            vertical: Space.xs,
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
                    : Text(duty.people.join(l10n.listSeparator), style: AppText.body),
              ),
              const SizedBox(width: Space.s),
              if (editable) Icon(Symbols.chevron_right_rounded, color: c.tertiaryLabel, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks a duty to add: one of [suggestions], or a name typed in.
class AddDutySheet extends StatefulWidget {
  const AddDutySheet({super.key, required this.suggestions, this.typed = true});

  final List<String> suggestions;

  /// Whether a duty may be typed in, not only picked: not for a 事工's
  /// 負責人, who adds only the duties it leads.
  final bool typed;

  @override
  State<AddDutySheet> createState() => _AddDutySheetState();
}

class _AddDutySheetState extends State<AddDutySheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final typed = _name.text.trim();
    return UnsavedChanges(
      changed: () => _name.text.trim().isNotEmpty,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A suggestion is added with a tap; a typed name with 新增.
              SheetBar(
                title: l10n.addDuty,
                actions: [
                  if (widget.typed)
                    SecondaryButton(
                      label: l10n.add,
                      onPressed: typed.isEmpty ? null : () => Navigator.pop(context, typed),
                    ),
                ],
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (widget.suggestions.isNotEmpty)
                      ListSection(
                        children: [
                          for (final s in widget.suggestions)
                            ListRow(
                              title: s,
                              leading: const Icon(Symbols.add_rounded),
                              onTap: () => Navigator.pop(context, s),
                            ),
                        ],
                      ),
                    if (widget.typed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
                        child: TextField(
                          controller: _name,
                          autofocus: widget.suggestions.isEmpty,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(hintText: l10n.dutyName),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (v) => Navigator.pop(context, v),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
