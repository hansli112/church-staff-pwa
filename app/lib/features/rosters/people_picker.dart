import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
    this.takeDutyFrom = const [],
    this.removeDuty = false,
    this.swapDay = false,
    this.guestNames = const {},
  });

  /// Names explicitly arranged without binding a same-name member.
  final Set<String> guestNames;

  /// The chosen names, any order (the caller sorts by staff order).
  final List<String> people;

  /// The new staff order for this duty, only if someone dragged it.
  final List<String>? ranking;

  /// Members to give this duty to, so they show up first next time.
  final List<Member> addDutyTo;

  /// Members taken off this duty's list in 編輯.
  final List<Member> takeDutyFrom;

  /// Take this duty off the day altogether.
  final bool removeDuty;

  /// Trade who is on the duty with another day (#90).
  final bool swapDay;
}

/// When to focus the search box on open: long lists are faster to search
/// than to scroll.
const searchAutofocusThreshold = 30;

/// Picks the people for one duty on one day.
///
/// Like self-host it lists only the people who serve this duty here, in
/// staff order. New: a search over the whole church (part of a name, any
/// width or case) shows everyone else under 「其他同工」. Picking one of
/// them, an admin also gives them the duty, without asking: whoever is
/// scheduled for it once is listed first next time, so nobody has to set
/// duties up beforehand. Everyone is listed there from the start while
/// nobody serves the duty yet. In 編輯 an admin takes people off the list
/// again. A typed name nobody has can be used as is, for a visiting
/// speaker. For a duty that takes one person, picking someone puts them
/// there in place of whoever was, and closes; 「再加一位」 picks several.
class PeoplePicker extends StatefulWidget {
  const PeoplePicker({
    super.key,
    required this.serviceType,
    required this.duty,
    required this.initial,
    required this.members,
    required this.order,
    required this.canEditDutyList,
    required this.canReorder,
    this.canRemove = false,
    this.canSwapDay = false,
    this.onePerson = false,
    this.initialGuests = const {},
    this.guestSuggestions = const [],
    this.onChanged,
    this.onInvite,
    this.notes = const {},
  });

  /// The service, or null for an event's roster: then whoever serves the
  /// duty in any 牧區 is listed first.
  final String? serviceType;
  final String duty;
  final List<String> initial;
  final List<Member> members;
  final StaffOrder order;
  final Set<String> initialGuests;
  final List<String> guestSuggestions;

  /// Admins edit who is on the duty's list (picking someone puts them on,
  /// 編輯 takes them off); roster editors may not.
  final bool canEditDutyList;
  final bool canReorder;

  /// Offer 「移除這項」 at the end of the list (the row also swipes away).
  final bool canRemove;

  /// Offer 「和別週交換」 there: the dragless way to what dragging a cell
  /// in 排好幾週 does (#90).
  final bool canSwapDay;

  /// The duty takes one person (RosterActions.takesOnePerson).
  final bool onePerson;

  /// Called with the latest result after every change, so closing the
  /// sheet any way (drag down, tap outside) keeps what was picked.
  final ValueChanged<PickerResult>? onChanged;

  /// For those who may invite people (admins): while nobody serves the
  /// duty, a 「邀請同工」 button closes the picker, keeping what was picked,
  /// and this goes on to the invites.
  final VoidCallback? onInvite;

  /// A line under a member's name, by name: what they already serve
  /// around the day (#90).
  final Map<String, String> notes;

  @override
  State<PeoplePicker> createState() => PeoplePickerState();
}

class PeoplePickerState extends State<PeoplePicker> {
  late final List<String> _selected = [...widget.initial];
  late final Set<String> _guests = {...widget.initialGuests};
  late bool _tapReplaces = widget.onePerson && widget.initial.length < 2;
  late List<String> _serving;
  late final List<Member> _others;

  /// Who serves the duty here, by name, for taking them off the list.
  final _servingMembers = <String, List<Member>>{};
  final _grant = <Member>[];
  final _takeOff = <Member>[];
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
        (_servingMembers[name] ??= []).add(m);
      } else {
        others.add(m);
      }
    }
    serving.sort();
    _serving = widget.order.orderedCandidates(widget.duty, serving);
    others.sort((a, b) => a.name.compareTo(b.name));
    _others = others;
  }

  /// The result if the sheet closes now. Only someone still picked is put
  /// on the list.
  PickerResult get result => PickerResult(
    people: _selected,
    ranking: _ranking,
    addDutyTo: [
      for (final m in _grant)
        if (_selected.contains(m.name)) m,
    ],
    takeDutyFrom: _takeOff,
    guestNames: _guests.intersection(_selected.toSet()),
  );

  void _toggle(String name, {bool guest = false}) {
    Haptics.selection();
    setState(() {
      if (_selected.remove(name)) {
        _guests.remove(name);
        // Put on the list by being picked here: unpicked, off it again.
        if (_grant.any((m) => m.name == name)) _unlist(name);
      } else {
        _selected.add(name);
        if (guest) _guests.add(name);
      }
    });
    widget.onChanged?.call(result);
  }

  /// A name tapped in the list: for a duty of one, [name] in place of
  /// whoever was there, and done; otherwise picked or unpicked.
  void _choose(String name, {bool guest = false}) {
    if (!_tapReplaces) return _toggle(name, guest: guest);
    Haptics.selection();
    if (!_selected.contains(name)) {
      _selected
        ..clear()
        ..add(name);
      _guests.clear();
      if (guest) _guests.add(name);
    }
    Navigator.pop(context, result);
  }

  void _pickOther(Member m) {
    if (widget.canEditDutyList && _takeOff.contains(m)) {
      // Taken off in 編輯 and tapped again: back on the list, and picked.
      _takeOff.remove(m);
      _putOnList(m);
      if (!_selected.contains(m.name)) return _choose(m.name);
      Haptics.selection();
      widget.onChanged?.call(result);
      return;
    }
    if (_selected.contains(m.name)) return _choose(m.name);
    // Remembered for the duty only if they are one of the service's 同工;
    // someone helping out is scheduled this once (#82), and shows on the
    // service's page to be added as a 同工.
    if (widget.canEditDutyList && m.zoneTypes.contains(widget.serviceType)) {
      _grant.add(m);
      _putOnList(m);
    }
    _choose(m.name);
  }

  /// Puts [m] last on the duty's list, and its staff order with it.
  void _putOnList(Member m) {
    (_servingMembers[m.name] ??= []).add(m);
    setState(() => _serving = _ranking = [..._serving, m.name]);
  }

  /// Takes [name] off the duty's list, and its staff order: listed with
  /// everyone else again.
  void _unlist(String name) {
    for (final m in _servingMembers.remove(name) ?? const <Member>[]) {
      // Put on the list in this picker: never written, so nothing to undo.
      if (!_grant.remove(m)) _takeOff.add(m);
      if (!_others.contains(m)) _others.add(m);
    }
    _others.sort((a, b) => a.name.compareTo(b.name));
    _serving = _ranking = [
      for (final n in _serving)
        if (n != name) n,
    ];
  }

  /// 編輯's minus: [name] off the list, still picked for this day.
  void _takeOffList(String name) {
    Haptics.selection();
    setState(() => _unlist(name));
    widget.onChanged?.call(result);
  }

  void _useTyped() {
    final name = _query.trim();
    if (name.isEmpty || _selected.contains(name)) return;
    _choose(name, guest: true);
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
              // Admins edit the list (order, and who is on it); roster
              // editors only reorder it.
              // 完成 stays once 編輯 empties the list.
              if (_reordering ||
                  (widget.canEditDutyList ? _serving.isNotEmpty : widget.canReorder && _serving.length > 1))
                SecondaryButton(
                  label: _reordering
                      ? l10n.done
                      : widget.canEditDutyList
                      ? l10n.edit
                      : l10n.reorder,
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
    // Guests are an explicit separate choice, even when a member shares a name.
    final guests = <String>{
      ...widget.guestSuggestions,
      ..._guests,
      for (final n in _selected)
        if (!_serving.contains(n) && !_others.any((m) => m.name == n)) n,
    }.where((n) => _matches(n, q)).toList();
    final typedIsKnown =
        typed.isEmpty ||
        serving.contains(typed) ||
        others.any((m) => m.name == typed) ||
        guests.contains(typed) ||
        _selected.contains(typed);

    final rows = <Widget Function()>[];
    if (_tapReplaces && _selected.isNotEmpty) {
      rows.add(
        () => ListRow(
          title: l10n.pickerAddAnother,
          leading: const Icon(Symbols.person_add_rounded),
          onTap: () => setState(() => _tapReplaces = false),
        ),
      );
    }
    if (serving.isNotEmpty) {
      rows.add(() => SectionHeader(l10n.pickerServes(widget.duty)));
      for (final n in serving) {
        rows.add(() => _row(n, c, note: widget.notes[n], onTap: () => _choose(n)));
      }
    } else if (!searching) {
      // One sentence and, for those who can, one button.
      rows.add(
        () => Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            children: [
              BalancedText(
                widget.canEditDutyList ? l10n.pickerLearns : l10n.pickerNoOneServes(widget.duty),
                style: AppText.body.copyWith(color: c.secondaryLabel),
              ),
              if (widget.onInvite case final invite?)
                SecondaryButton(
                  label: l10n.inviteMembers,
                  onPressed: () {
                    Navigator.pop(context, result);
                    invite();
                  },
                ),
            ],
          ),
        ),
      );
    }
    if (others.isNotEmpty) {
      rows.add(() => SectionHeader(l10n.pickerOthers));
      for (final m in others) {
        rows.add(() => _row(m.name, c, note: widget.notes[m.name], onTap: () => _pickOther(m)));
      }
    }
    if (guests.isNotEmpty) {
      rows.add(() => SectionHeader(l10n.pickerGuestNames));
      for (final name in guests) {
        rows.add(() => _row(name, c, onTap: () => _choose(name, guest: true)));
      }
    }
    if (!typedIsKnown) {
      rows.add(
        () => ListRow(
          title: l10n.pickerUseName(typed),
          leading: const Icon(Symbols.add_rounded),
          onTap: _useTyped,
        ),
      );
    }
    if (searching && serving.isEmpty && others.isEmpty && guests.isEmpty && typedIsKnown) {
      rows.add(
        () => Padding(
          padding: const EdgeInsets.all(Space.l),
          child: BalancedText(l10n.pickerNoResults(typed), style: AppText.body.copyWith(color: c.secondaryLabel)),
        ),
      );
    }
    // Only before anyone is picked here: a swap does not keep picks.
    final swaps = widget.canSwapDay && !searching && listEquals(_selected, widget.initial);
    if ((swaps || widget.canRemove) && !searching) {
      rows.add(() => const SizedBox(height: Space.l));
    }
    if (swaps) {
      rows.add(
        () => ListRow(
          title: l10n.pickerSwapDay,
          leading: const Icon(Symbols.swap_vert_rounded),
          onTap: () => Navigator.pop(context, PickerResult(people: widget.initial, swapDay: true)),
        ),
      );
    }
    if (widget.canRemove && !searching) {
      rows.add(
        () => ListRow(
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
      // The sheet runs on under the keyboard; its end scrolls out above it.
      padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.viewInsetsOf(context).bottom),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i](),
    );
  }

  Widget _row(String name, AppColors c, {String? note, required VoidCallback onTap}) {
    final on = _selected.contains(name);
    return Semantics(
      selected: on,
      child: Material(
        color: c.surfaceRaised,
        child: ListRow(title: name, subtitle: note, selected: on, chevron: false, onTap: onTap),
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
          child: BalancedText(
            widget.canEditDutyList ? l10n.editListHint : l10n.reorderHint,
            textAlign: TextAlign.start,
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
                  leading: widget.canEditDutyList
                      ? IconButton(
                          icon: Icon(Symbols.do_not_disturb_on_rounded, color: c.destructive),
                          tooltip: l10n.pickerTakeOff(list[i]),
                          onPressed: () => _takeOffList(list[i]),
                        )
                      : null,
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Icon(Symbols.drag_handle_rounded, color: c.tertiaryLabel),
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
