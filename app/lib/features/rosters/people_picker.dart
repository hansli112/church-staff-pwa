import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/rendering.dart' show CustomSemanticsAction;
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
    this.removeFutureGuest,
  });

  /// A name arranged this once, to take off the days ahead too
  /// (之後都不排), swiped in 臨時排過的人.
  final String? removeFutureGuest;

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
/// speaker. For a duty that takes one person (多人服事 off), picking
/// someone puts them there in place of whoever was, and closes;
/// 「選取多位」 at the end ticks several this once.
/// Nothing is kept until then or 完成: 取消, or closing it any other way
/// after a change, asks to discard it ([UnsavedChanges]).
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
    this.onInvite,
    this.notes = const {},
    this.unavailable = const {},
    this.canRemoveFutureGuests = false,
  });

  /// Names arranged this once swipe away from the days ahead too: a
  /// service's roster, not an event's.
  final bool canRemoveFutureGuests;

  /// The service, or null for an event's roster: then whoever serves the
  /// duty in any service is listed first.
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
  /// in 安排服事 does (#90).
  final bool canSwapDay;

  /// The duty takes one person (RosterActions.takesOnePerson).
  final bool onePerson;

  /// For those who may invite people (admins): while nobody serves the
  /// duty, a 「邀請同工」 button closes the picker, keeping what was picked,
  /// and this goes on to the invites.
  final VoidCallback? onInvite;

  /// A line under a member's name, by name: what they already serve
  /// around the day (#90).
  final Map<String, String> notes;

  /// Who marked the day as one they cannot serve (#91), by name: listed
  /// after the rest of their section, still to be picked.
  final Set<String> unavailable;

  @override
  State<PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<PeoplePicker> {
  late final List<String> _selected = [...widget.initial];
  late final Set<String> _guests = {...widget.initialGuests};
  late bool _tapReplaces = widget.onePerson && widget.initial.length < 2;
  late List<String> _serving;

  /// The duty's list as it opened, to tell a new order from a dragged-back
  /// one.
  late final List<String> _servingAtOpen;
  late final List<Member> _others;

  /// Who serves the duty here, by name, for taking them off the list.
  final _servingMembers = <String, List<Member>>{};
  final _grant = <Member>[];
  final _takeOff = <Member>[];
  String _query = '';

  /// The search box, out of the way until 找其他人: whoever is likely is on
  /// the duty's list already. Shown from the start when nobody is.
  late bool _searchShown = _serving.isEmpty;
  bool _searchFocus = false;
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
    _serving = _servingAtOpen = widget.order.orderedCandidates(widget.duty, serving);
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

  /// Whether closing without 完成 would lose something: who is picked,
  /// or the duty's list or its order.
  bool get _changed =>
      !setEquals(_selected.toSet(), widget.initial.toSet()) ||
      !setEquals(result.guestNames, widget.initialGuests) ||
      (_ranking != null && !listEquals(_ranking, _servingAtOpen)) ||
      _grant.isNotEmpty ||
      _takeOff.isNotEmpty;

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
  }

  /// A name tapped in the list: for a duty of one, [name] in place of
  /// whoever was there, and done; otherwise, or [name] ticked already,
  /// picked or unpicked.
  void _choose(String name, {bool guest = false}) {
    if (!_tapReplaces || _selected.contains(name)) return _toggle(name, guest: guest);
    Haptics.selection();
    _selected
      ..clear()
      ..add(name);
    _guests.clear();
    if (guest) _guests.add(name);
    Navigator.pop(context, result);
  }

  void _pickOther(Member m) {
    if (widget.canEditDutyList && _takeOff.contains(m)) {
      // Taken off in 編輯 and tapped again: back on the list, and picked.
      _takeOff.remove(m);
      _putOnList(m);
      if (!_selected.contains(m.name)) return _choose(m.name);
      Haptics.selection();
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
    return UnsavedChanges(
      changed: () => _changed,
      child: Column(
        children: [
          // Nothing is saved until 完成. In 編輯 its own 完成 goes back to
          // picking.
          SheetBar(
            title: widget.duty,
            cancel: !_reordering,
            actions: [
              // Whoever edits the list (Member.editsDutyList) changes its
              // order and who is on it; other roster editors only reorder.
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
              if (!_reordering) SecondaryButton(label: l10n.done, onPressed: () => Navigator.pop(context, result)),
            ],
          ),
          if (_reordering)
            Expanded(child: _reorderList(l10n, c))
          else ...[
            if (_searchShown)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m),
                child: SearchField(
                  hint: l10n.pickerSearchHint,
                  autofocus: _searchFocus,
                  onChanged: (q) => setState(() => _query = q),
                ),
              ),
            Expanded(child: _list(l10n, c)),
          ],
        ],
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
    final serving = _unavailableLast([
      for (final n in _serving)
        if (_matches(n, q)) n,
    ], (n) => n);
    final searching = q.isNotEmpty;
    // Nobody serves this duty yet (a new church): offer everyone rather
    // than an empty list that only a search would fill. Otherwise those
    // found and picked: ticked where they were, the search cleared.
    final everyone = searching || _serving.isEmpty;
    final others = _unavailableLast([
      for (final m in _others)
        if (!servingSet.contains(m.name) && (everyone ? _matches(m.name, q) : _selected.contains(m.name))) m,
    ], (m) => m.name);
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
                l10n.pickerNoOneServes(widget.duty),
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
    if (!_searchShown) {
      rows.add(
        () => ListRow(
          title: l10n.pickerFindOthers,
          leading: const Icon(Symbols.search_rounded),
          chevron: false,
          onTap: () => setState(() => _searchShown = _searchFocus = true),
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
        rows.add(() => _guestRow(name, c, l10n));
      }
    }
    if (!typedIsKnown) {
      rows.add(
        () => ListRow(
          title: l10n.pickerUseName(typed),
          subtitle: l10n.pickerUseNameDetail,
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
    if ((swaps || widget.canRemove || _tapReplaces) && !searching) {
      rows.add(() => const SizedBox(height: Space.l));
    }
    if (_tapReplaces && !searching) {
      rows.add(
        () => ListRow(
          title: l10n.pickerSeveralThisTime,
          leading: const Icon(Symbols.group_add_rounded),
          chevron: false,
          onTap: () => setState(() => _tapReplaces = false),
        ),
      );
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

  /// [list] in its order, those who cannot serve the day after the rest.
  List<T> _unavailableLast<T>(List<T> list, String Function(T) name) => [
    for (final x in list)
      if (!widget.unavailable.contains(name(x))) x,
    for (final x in list)
      if (widget.unavailable.contains(name(x))) x,
  ];

  /// A name arranged before without an account; swiped, 之後都不排.
  Widget _guestRow(String name, AppColors c, L10n l10n) {
    final row = _row(name, c, onTap: () => _choose(name, guest: true));
    if (!widget.canRemoveFutureGuests) return row;
    void remove() => Navigator.pop(context, PickerResult(people: widget.initial, removeFutureGuest: name));
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: l10n.rosterRemoveFutureGuest): remove},
      child: Dismissible(
        key: ValueKey('guest/$name'),
        direction: DismissDirection.endToStart,
        background: SwipeDeleteBackground(label: l10n.rosterRemoveFutureGuest),
        confirmDismiss: (_) async {
          remove();
          return false;
        },
        child: row,
      ),
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
