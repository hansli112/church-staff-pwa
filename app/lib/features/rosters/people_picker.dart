import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../core/perf.dart';
import '../../core/design/tokens.dart';
import '../../domain/event_roster.dart';
import '../../domain/models.dart';
import '../../domain/staff_order.dart';
import '../../domain/text.dart' show nameKey;
import '../../l10n/app_localizations.dart';

/// What the picker hands back when it closes.
class PickerResult {
  const PickerResult({
    required this.people,
    this.ranking,
    this.addDutyTo = const [],
    this.removeDuty = false,
  });

  /// The chosen names, any order (the caller sorts by staff order).
  final List<String> people;

  /// The new staff order for this duty, only if someone dragged it.
  final List<String>? ranking;

  /// Members to give this duty to, so they show up first next time.
  final List<Member> addDutyTo;

  /// Take this duty off the day altogether.
  final bool removeDuty;
}

/// When to focus the search box on open: long lists are faster to search
/// than to scroll.
const searchAutofocusThreshold = 30;

/// Picks the people for one duty on one day.
///
/// Like self-host it lists only the people who serve this duty here, in
/// staff order. New: a search over the whole church (part of a name, any
/// width or case) shows everyone else under 「其他同工」, and picking one of
/// them offers to give them the duty. Everyone is listed there from the start
/// while nobody serves the duty yet. A typed name nobody has can be used
/// as is, for a visiting speaker.
class PeoplePicker extends StatefulWidget {
  const PeoplePicker({
    super.key,
    required this.serviceType,
    required this.duty,
    required this.initial,
    required this.members,
    required this.order,
    required this.canGrantDuty,
    required this.canReorder,
    this.canRemove = false,
    this.onChanged,
  });

  /// The service, or null for an event's roster: then whoever serves the
  /// duty in any 牧區 is listed first.
  final String? serviceType;
  final String duty;
  final List<String> initial;
  final List<Member> members;
  final StaffOrder order;

  /// Admins may add the duty to someone's zone; roster editors may not.
  final bool canGrantDuty;
  final bool canReorder;

  /// Offer 「移除這項」 at the end of the list (the row also swipes away).
  final bool canRemove;

  /// Called with the latest result after every change, so closing the
  /// sheet any way (drag down, tap outside) keeps what was picked.
  final ValueChanged<PickerResult>? onChanged;

  @override
  State<PeoplePicker> createState() => PeoplePickerState();
}

class PeoplePickerState extends State<PeoplePicker> {
  late final List<String> _selected = [...widget.initial];
  late List<String> _serving;
  late final List<Member> _others;
  final _grant = <Member>[];
  String _query = '';
  bool _reordering = false;
  List<String>? _ranking;

  @override
  void initState() {
    super.initState();
    perfMark('picker-visible', repeat: true);
    final servingSet = <String>{};
    final serving = <String>[];
    final others = <Member>[];
    for (final m in widget.members) {
      final name = m.name.trim();
      if (name.isEmpty) continue;
      final type = widget.serviceType;
      if (type == null ? servesAnywhere(m, widget.duty) : m.serves(type, widget.duty)) {
        if (servingSet.add(name)) serving.add(name);
      } else {
        others.add(m);
      }
    }
    serving.sort();
    _serving = widget.order.orderedCandidates(widget.duty, serving);
    others.sort((a, b) => a.name.compareTo(b.name));
    _others = others;
  }

  /// The result if the sheet closes now.
  PickerResult get result => PickerResult(people: _selected, ranking: _ranking, addDutyTo: _grant);

  void _toggle(String name) {
    Haptics.selection();
    setState(() {
      if (!_selected.remove(name)) _selected.add(name);
    });
    widget.onChanged?.call(result);
  }

  Future<void> _pickOther(Member m) async {
    final l10n = L10n.of(context);
    if (_selected.contains(m.name)) {
      _toggle(m.name);
      return;
    }
    if (widget.canGrantDuty) {
      final grant = await askChoice(
        context,
        title: l10n.pickerAddDutyTitle(m.name, widget.duty),
        message: l10n.pickerAddDutyBody(widget.duty),
        yes: l10n.pickerAddDutyYes,
        no: l10n.pickerAddDutyNo,
      );
      if (grant == null) return;
      if (grant) {
        _grant.add(m);
        setState(() => _serving = [..._serving, m.name]);
      }
    }
    _toggle(m.name);
  }

  void _useTyped() {
    final name = _query.trim();
    if (name.isEmpty || _selected.contains(name)) return;
    _toggle(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.s, Space.s),
          child: Row(
            children: [
              Expanded(child: Text(widget.duty, style: AppText.title3)),
              if (widget.canReorder && _serving.length > 1)
                SecondaryButton(
                  label: _reordering ? l10n.done : l10n.reorder,
                  onPressed: () => setState(() => _reordering = !_reordering),
                ),
              if (!_reordering)
                SecondaryButton(
                  label: l10n.done,
                  onPressed: () => Navigator.pop(context, result),
                ),
            ],
          ),
        ),
        if (_reordering)
          Expanded(child: _reorderList(l10n, c))
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: SearchField(
              hint: l10n.pickerSearchHint,
              autofocus: widget.members.length > searchAutofocusThreshold,
              onChanged: (q) => setState(() => _query = q),
            ),
          ),
          if (_selected.isNotEmpty) _selectedChips(c),
          Expanded(child: _list(l10n, c)),
        ],
      ],
    );
  }

  Widget _selectedChips(AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final name in widget.order.sort(widget.duty, _selected))
              InputChip(
                label: Text(name),
                onDeleted: () => _toggle(name),
                deleteButtonTooltipMessage: L10n.of(context).removed(name),
                backgroundColor: c.accentSoft,
                side: BorderSide.none,
              ),
          ],
        ),
      ),
    );
  }

  /// Folded search keys, computed once per name rather than on every
  /// keystroke for the whole church.
  final _keys = <String, String>{};

  bool _matches(String name, String query) =>
      query.isEmpty || _keys.putIfAbsent(name, () => nameKey(name)).contains(query);

  Widget _list(L10n l10n, AppColors c) {
    final q = nameKey(_query);
    final servingSet = _serving.toSet();
    final serving = [
      for (final n in _serving)
        if (_matches(n, q)) n,
    ];
    final searching = q.isNotEmpty;
    // Nobody serves this duty yet (a new church): offer everyone rather
    // than an empty list that only a search would fill.
    final others = searching || _serving.isEmpty
        ? [
            for (final m in _others)
              if (_matches(m.name, q) && !servingSet.contains(m.name)) m,
          ]
        : const <Member>[];
    final typed = _query.trim();
    final typedIsKnown =
        typed.isEmpty || serving.contains(typed) || others.any((m) => m.name == typed) || _selected.contains(typed);
    // Names typed earlier for this day that are not members.
    final custom = [
      for (final n in _selected)
        if (!_serving.contains(n) && !_others.any((m) => m.name == n)) n,
    ];

    final rows = <Widget>[];
    if (serving.isNotEmpty || custom.isNotEmpty) {
      rows.add(SectionHeader(l10n.pickerServes));
      for (final n in [
        ...serving,
        ...custom.where((n) => !serving.contains(n)),
      ]) {
        rows.add(_row(n, c, onTap: () => _toggle(n)));
      }
    } else if (!searching) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(Space.l),
          child: BalancedText(
            l10n.pickerNoOneServes(widget.duty),
            style: AppText.body.copyWith(color: c.secondaryLabel),
          ),
        ),
      );
    }
    if (others.isNotEmpty) {
      rows.add(SectionHeader(l10n.pickerOthers));
      for (final m in others) {
        rows.add(_row(m.name, c, onTap: () => _pickOther(m)));
      }
    }
    if (!typedIsKnown) {
      rows.add(
        ListRow(
          title: l10n.pickerUseName(typed),
          leading: const Icon(Icons.add),
          onTap: _useTyped,
        ),
      );
    }
    if (searching && serving.isEmpty && others.isEmpty && typedIsKnown) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(Space.l),
          child: BalancedText(l10n.pickerNoResults(typed), style: AppText.body.copyWith(color: c.secondaryLabel)),
        ),
      );
    }
    if (widget.canRemove && !searching) {
      rows.add(const SizedBox(height: Space.l));
      rows.add(
        ListRow(
          title: l10n.removeDuty,
          destructive: true,
          onTap: () => Navigator.pop(
            context,
            PickerResult(people: widget.initial, removeDuty: true),
          ),
        ),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: Space.xl),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _row(String name, AppColors c, {required VoidCallback onTap}) {
    final on = _selected.contains(name);
    return Semantics(
      selected: on,
      child: Material(
        color: c.surfaceRaised,
        child: ListRow(title: name, selected: on, chevron: false, onTap: onTap),
      ),
    );
  }

  Widget _reorderList(L10n l10n, AppColors c) {
    final list = _ranking ?? _serving;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.m,
            vertical: Space.s,
          ),
          child: Text(
            l10n.reorderHint,
            style: AppText.footnote.copyWith(color: c.secondaryLabel),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: list.length,
            onReorder: (from, to) {
              final next = [...list];
              final moved = next.removeAt(from);
              next.insert(to > from ? to - 1 : to, moved);
              Haptics.selection();
              setState(() {
                _ranking = next;
                _serving = next;
              });
              widget.onChanged?.call(result);
            },
            itemBuilder: (_, i) => Material(
              key: ValueKey(list[i]),
              color: c.surfaceRaised,
              child: ReorderableDelayedDragStartListener(
                index: i,
                child: ListRow(
                  title: list[i],
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Icon(Icons.drag_handle, color: c.tertiaryLabel),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
