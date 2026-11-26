import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/perf.dart';
import '../../core/design/tokens.dart';
import '../../domain/event_roster.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';
import '../../domain/staff_order.dart';
import '../../domain/text.dart' show nameKey;
import '../../l10n/app_localizations.dart';
import '../../state/duty_pick.dart';

/// What the picker hands back when it closes.
class PickerResult extends DutyPick {
  const PickerResult({
    required super.people,
    super.ranking,
    super.putOnList,
    super.takeOffList,
    super.guestNames,
    super.newStaff,
    super.groupIds,
    this.removeDuty = false,
    this.swapDay = false,
    this.removeFutureGuest,
  });

  /// A name arranged this once, to take off the days ahead too
  /// (之後都不排), swiped in 臨時排過的人.
  final String? removeFutureGuest;

  /// Take this duty off the day altogether.
  final bool removeDuty;

  /// Trade who is on the duty with another day (#90).
  final bool swapDay;
}

/// A 小組 the duty can be given to (服事交給小組), with how many are in it.
typedef PickerGroup = ({String id, String name, int count});

/// Picks the people for one duty on one day.
///
/// Like self-host it lists only the people who serve this duty here, in
/// staff order. New: a search over the whole church (part of a name, any
/// width or case) shows everyone else under 「其他同工」. Picking one of
/// them, an admin also gives them the duty, without asking: whoever is
/// scheduled for it once is listed first next time, so nobody has to set
/// duties up beforehand. Everyone is listed there from the start while
/// nobody serves the duty yet. Swiped away, an admin takes someone off the
/// list again. A typed name nobody has can be a 同工 without an account
/// (新增同工, whose day it is once they join by that name), or used as is,
/// for a visiting speaker. 先空著 at the end takes everyone off the day's
/// duty and keeps it. For a duty that takes one person (多人服事 off), picking
/// someone puts them there in place of whoever was, and closes; 「選取」
/// at the top ticks several this once, as a duty of several does from the
/// start: a circle before each name, and a handle to drag the list's
/// order by (iOS's edit mode: selecting and reordering, one mode).
/// Nothing is kept until then or 完成: 取消, or closing it any other way
/// after a change, asks to discard it ([UnsavedChanges]). Last, before
/// those, the church's 小組 ([smallGroups]): one picked is given the duty
/// (服事交給小組), as a person is.
class PeoplePicker extends StatefulWidget {
  const PeoplePicker({
    super.key,
    required this.serviceType,
    required this.duty,
    required this.initial,
    required this.staff,
    required this.order,
    required this.rights,
    this.canRemove = false,
    this.canSwapDay = false,
    this.offDay = false,
    this.onePerson = false,
    this.initialGuests = const {},
    this.guestSuggestions = const [],
    this.notes = const {},
    this.busy = const {},
    this.unavailable = const {},
    this.smallGroups = const [],
    this.initialGroups = const {},
  });

  /// The church's 小組, in its order, to give the duty to.
  final List<PickerGroup> smallGroups;

  /// The 小組 on the duty as it opened: name → id.
  final Map<String, String> initialGroups;

  /// What picking may change besides who is on the day: putting someone
  /// picked on the list, swiping them off it, dragging the order, a typed
  /// name made a 同工 (新增同工), a name arranged this once swiped off the
  /// days ahead.
  final DutyRights rights;

  /// The service, or null for an event's roster: then whoever serves the
  /// duty in any service is listed first.
  final String? serviceType;
  final String duty;
  final List<String> initial;
  final Staff staff;
  final StaffOrder order;
  final Set<String> initialGuests;
  final List<String> guestSuggestions;

  /// Offer 「這一天沒有這項服事」 at the end of the list (the row also swipes away).
  final bool canRemove;

  /// Offer 「和別週交換」 there: the dragless way to what dragging a cell
  /// in 安排服事 does (#90).
  final bool canSwapDay;

  /// The duty is not on the day (taken off it): 先空著 puts it back with
  /// nobody yet.
  final bool offDay;

  /// The duty takes one person (RosterActions.takesOnePerson).
  final bool onePerson;

  /// A line under a member's name, by name: what they already serve
  /// around the day (#90).
  final Map<String, String> notes;

  /// Who already serves another duty at the same service, by name:
  /// suggested after those who do not, still to be picked.
  final Set<String> busy;

  /// Who marked the day as one they cannot serve (#91), by name: listed
  /// after the rest of their section, still to be picked.
  final Set<String> unavailable;

  @override
  State<PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<PeoplePicker> {
  late final List<String> _selected = [...widget.initial];
  late final Set<String> _guests = {...widget.initialGuests};

  /// The 小組 picked, name → id.
  late final Map<String, String> _groups = {...widget.initialGroups};

  /// Typed as 新增同工, in the order typed; unticked, still listed.
  final _newStaff = <String>{};
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

  List<String>? _ranking;

  @override
  void initState() {
    super.initState();
    perfMark('picker-visible', repeat: true);
    final servingSet = <String>{};
    final serving = <String>[];
    final others = <Member>[];
    for (final m in widget.staff.all) {
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
    putOnList: [
      for (final m in _grant)
        if (_selected.contains(m.name)) m,
    ],
    takeOffList: _takeOff,
    guestNames: _guests.intersection(_selected.toSet()),
    newStaff: _newStaff.intersection(_selected.toSet()),
    groupIds: {
      for (final e in _groups.entries)
        if (_selected.contains(e.key)) e.key: e.value,
    },
  );

  /// Whether closing without 完成 would lose something: who is picked,
  /// or the duty's list or its order.
  bool get _changed =>
      !setEquals(_selected.toSet(), widget.initial.toSet()) ||
      !setEquals(result.guestNames, widget.initialGuests) ||
      !mapEquals(result.groupIds, widget.initialGroups) ||
      (_ranking != null && !listEquals(_ranking, _servingAtOpen)) ||
      _grant.isNotEmpty ||
      _takeOff.isNotEmpty;

  void _toggle(String name, {bool guest = false, bool staff = false, String? group}) {
    Haptics.selection();
    setState(() {
      if (_selected.remove(name)) {
        _guests.remove(name);
        _groups.remove(name);
        // Put on the list by being picked here: unpicked, off it again.
        if (_grant.any((m) => m.name == name)) _unlist(name);
      } else {
        _selected.add(name);
        if (guest) _guests.add(name);
        if (staff) _newStaff.add(name);
        if (group != null) _groups[name] = group;
      }
    });
  }

  /// A name tapped in the list: for a duty of one, [name] in place of
  /// whoever was there, and done; otherwise, or [name] ticked already,
  /// picked or unpicked. [group]: the 小組's id, for one.
  void _choose(String name, {bool guest = false, bool staff = false, String? group}) {
    if (!_tapReplaces || _selected.contains(name)) return _toggle(name, guest: guest, staff: staff, group: group);
    Haptics.selection();
    _selected
      ..clear()
      ..add(name);
    _guests.clear();
    _newStaff.clear();
    _groups.clear();
    if (guest) _guests.add(name);
    if (staff) _newStaff.add(name);
    if (group != null) _groups[name] = group;
    Navigator.pop(context, result);
  }

  void _pickOther(Member m) {
    if (_swipesOff && _takeOff.contains(m)) {
      // Swiped off the list and tapped again: back on it, and picked.
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
    if (widget.rights.putsOnList && m.zoneTypes.contains(widget.serviceType)) {
      _grant.add(m);
      _putOnList(m);
    }
    _choose(m.name);
  }

  /// Puts [m] last on the duty's list, and its staff order with it.
  void _putOnList(Member m) {
    (_servingMembers[m.name] ??= []).add(m);
    setState(() {
      _serving = [..._serving, m.name];
      if (widget.rights.reorders || widget.rights.putsOnList) _ranking = _serving;
    });
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
    _serving = [
      for (final n in _serving)
        if (n != name) n,
    ];
    // The staff order is the whole service's: not a 事工 leader's to write.
    if (widget.rights.reorders || widget.rights.putsOnList) _ranking = _serving;
  }

  bool get _swipesOff => widget.rights.putsOnList || widget.rights.takesOffList;

  /// Swiped off the list: [name] listed with everyone else, still picked
  /// for this day.
  void _takeOffList(String name) {
    Haptics.selection();
    setState(() => _unlist(name));
  }

  void _useTyped({bool staff = false}) {
    final name = _query.trim();
    if (name.isEmpty || _selected.contains(name)) return;
    _choose(name, guest: !staff, staff: staff);
  }

  /// 「選取」 until something changed, for a duty of one: a tap there is
  /// done already.
  bool get _offersSelect => _tapReplaces && !_changed;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return UnsavedChanges(
      changed: () => _changed,
      child: Column(
        children: [
          // Nothing is saved until 完成.
          SheetBar(
            title: widget.duty,
            actions: [
              _offersSelect
                  ? SecondaryButton(
                      label: l10n.pickerSeveralThisTime,
                      onPressed: () => setState(() => _tapReplaces = false),
                    )
                  : SecondaryButton(label: l10n.done, onPressed: () => Navigator.pop(context, result)),
            ],
          ),
          // At the top, whether or not anyone serves the duty yet: for
          // anyone else in the church, or a name typed.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: SearchField(
              hint: widget.smallGroups.isEmpty ? l10n.pickerSearchHint : l10n.pickerSearchHintGroups,
              onChanged: (q) => setState(() => _query = q),
            ),
          ),
          Expanded(child: _list(l10n, c)),
        ],
      ),
    );
  }

  /// Folded search keys, computed once per name rather than on every
  /// keystroke for the whole church.
  final _keys = <String, String>{};

  bool _matches(String name, String query) =>
      query.isEmpty || _keys.putIfAbsent(name, () => nameKey(name)).contains(query);

  /// Who is on the duty that day, as the picker opened: listed first, so
  /// the ticks are in sight. Fixed while it is open; a tap moves no row.
  late final _onDay = widget.initial.toSet();

  /// A row for [name], one of [_onDay] off the duty's list: a name
  /// arranged this once, or another 同工.
  Widget _onDayRow(String name, AppColors c, L10n l10n) {
    if (_others.where((m) => m.name == name).firstOrNull case final m? when !widget.initialGuests.contains(name)) {
      return _row(name, c, l10n, note: widget.notes[name], onTap: () => _pickOther(m));
    }
    return _guestRow(name, c, l10n);
  }

  /// The 小組 on the day as it opened that are listed under 小組, by name:
  /// ticked there, not among those on the day.
  late final _groupsOnDay = {
    for (final g in widget.smallGroups)
      if (widget.initialGroups[g.name] == g.id) g.name,
  };

  Widget _list(L10n l10n, AppColors c) {
    final q = nameKey(_query);
    final servingSet = _serving.toSet();
    bool listed(String n) => servingSet.contains(n) && !widget.initialGuests.contains(n);
    // On the day and on the list, in its order (they move with a drag);
    // then those on the day this once.
    final onDayListed = [
      for (final n in _serving)
        if (_onDay.contains(n) && listed(n) && _matches(n, q)) n,
    ];
    final onDayOthers = [
      for (final n in widget.initial)
        if (!listed(n) && !_groupsOnDay.contains(n) && _matches(n, q)) n,
    ];
    final rest = [
      for (final n in _serving)
        if (_matches(n, q) && !_onDay.contains(n)) n,
    ];
    final available = [
      for (final n in rest)
        if (!widget.unavailable.contains(n) && !widget.busy.contains(n)) n,
    ];
    final busy = [
      for (final n in rest)
        if (!widget.unavailable.contains(n) && widget.busy.contains(n)) n,
    ];
    final unavailable = [
      for (final n in rest)
        if (widget.unavailable.contains(n)) n,
    ];
    final searching = q.isNotEmpty;
    // Nobody serves this duty yet (a new church): offer everyone rather
    // than an empty list that only a search would fill. Otherwise those
    // found and picked: ticked where they were, the search cleared.
    final everyone = searching || _serving.isEmpty;
    final others = _unavailableLast([
      for (final m in _others)
        if (!servingSet.contains(m.name) &&
            !_onDay.contains(m.name) &&
            (everyone ? _matches(m.name, q) : _selected.contains(m.name)))
          m,
    ], (m) => m.name);
    final typed = _query.trim();
    // Guests are an explicit separate choice, even when a member shares a name.
    final guests = <String>{
      ...widget.guestSuggestions,
      ..._guests,
      for (final n in _selected)
        if (!_serving.contains(n) &&
            !_others.any((m) => m.name == n) &&
            !_newStaff.contains(n) &&
            !_groups.containsKey(n))
          n,
    }.where((n) => _matches(n, q) && !_onDay.contains(n)).toList();
    final added = [
      for (final n in _newStaff)
        if (_matches(n, q)) n,
    ];
    final groups = [
      for (final g in widget.smallGroups)
        if (_matches(g.name, q)) g,
    ];
    final typedIsKnown =
        typed.isEmpty ||
        onDayListed.contains(typed) ||
        onDayOthers.contains(typed) ||
        rest.contains(typed) ||
        others.any((m) => m.name == typed) ||
        guests.contains(typed) ||
        groups.any((g) => g.name == typed) ||
        _newStaff.contains(typed) ||
        _selected.contains(typed);

    // Ticking several, whoever may change the list's order drags it by the
    // handles: each part of it within itself, the day's people too.
    final drags = !_tapReplaces && !searching && (widget.rights.putsOnList || widget.rights.reorders);
    final rows = <_Entry>[];
    void listRow(String n, int part) => rows.add(
      _Entry(
        'serves/$n',
        (i) => _row(
          n,
          c,
          l10n,
          note: widget.notes[n],
          onTap: () => _choose(n),
          dragAt: drags ? i : null,
          swipesOff: _swipesOff,
        ),
        name: n,
        part: drags ? part : null,
      ),
    );
    if (onDayListed.isNotEmpty || onDayOthers.isNotEmpty || rest.isNotEmpty || added.isNotEmpty) {
      rows.add(_Entry('h/serves', (_) => SectionHeader(l10n.pickerServes)));
      for (final n in onDayListed) {
        listRow(n, 0);
      }
      for (final n in onDayOthers) {
        rows.add(_Entry('day/$n', (_) => _onDayRow(n, c, l10n)));
      }
      for (final n in available) {
        listRow(n, 1);
      }
      for (final n in busy) {
        listRow(n, 2);
      }
      for (final n in unavailable) {
        listRow(n, 3);
      }
      // 新增同工 here: on the list once saved.
      for (final n in added) {
        rows.add(_Entry('new/$n', (_) => _row(n, c, l10n, onTap: () => _choose(n, staff: true))));
      }
    }
    if (others.isNotEmpty) {
      // Nobody serves it yet: everyone, not 「other」 than nobody.
      rows.add(_Entry('h/others', (_) => SectionHeader(_serving.isEmpty ? l10n.pickerEveryone : l10n.pickerOthers)));
      for (final m in others) {
        rows.add(
          _Entry(
            'other/${m.uid}',
            (_) => _row(m.name, c, l10n, note: widget.notes[m.name], onTap: () => _pickOther(m)),
          ),
        );
      }
    }
    if (guests.isNotEmpty) {
      rows.add(_Entry('h/guests', (_) => SectionHeader(l10n.pickerGuestNames)));
      for (final name in guests) {
        rows.add(_Entry('guest/$name', (_) => _guestRow(name, c, l10n)));
      }
    }
    // 服事交給小組: the whole 小組, picked as a person is.
    if (groups.isNotEmpty) {
      rows.add(_Entry('h/groups', (_) => SectionHeader(l10n.smallGroups)));
      for (final g in groups) {
        rows.add(
          _Entry(
            'group/${g.id}',
            (_) => _row(
              g.name,
              c,
              l10n,
              note: l10n.memberCount(g.count),
              onTap: () => _choose(g.name, group: g.id),
            ),
          ),
        );
      }
    }
    // Nobody in the church by that name, however written: adding would
    // refuse it.
    if (!typedIsKnown && widget.rights.addsStaff && !widget.staff.hasName(typed)) {
      rows.add(
        _Entry(
          'typed-staff',
          (_) => ListRow(
            title: l10n.pickerAddStaff(typed),
            subtitle: l10n.pickerAddStaffDetail,
            leading: const Icon(Symbols.person_add_rounded),
            // Done at once: nothing further to open.
            chevron: false,
            onTap: () => _useTyped(staff: true),
          ),
        ),
      );
    }
    if (!typedIsKnown) {
      rows.add(
        _Entry(
          'typed',
          (_) => ListRow(
            title: l10n.pickerOnce(typed),
            leading: const Icon(Symbols.add_rounded),
            // Done at once: nothing further to open.
            chevron: false,
            onTap: _useTyped,
          ),
        ),
      );
    }
    if (searching &&
        rest.isEmpty &&
        others.isEmpty &&
        guests.isEmpty &&
        added.isEmpty &&
        groups.isEmpty &&
        typedIsKnown) {
      rows.add(
        _Entry(
          'none',
          (_) => Padding(
            padding: const EdgeInsets.all(Space.l),
            child: BalancedText(l10n.pickerNoResults(typed), style: AppText.body.copyWith(color: c.secondaryLabel)),
          ),
        ),
      );
    }
    // Only before anyone is picked here: a swap does not keep picks.
    final swaps = widget.canSwapDay && !searching && listEquals(_selected, widget.initial);
    // Someone on it as it opened: the duty kept, nobody on it for now.
    final empties = (widget.initial.isNotEmpty || widget.offDay) && !searching;
    if (swaps || empties || (widget.canRemove && !searching)) {
      rows.add(_Entry('gap', (_) => const SizedBox(height: Space.l)));
    }
    if (swaps) {
      rows.add(
        _Entry(
          'swap',
          (_) => ListRow(
            title: l10n.pickerSwapDay,
            leading: const Icon(Symbols.swap_vert_rounded),
            onTap: () => Navigator.pop(context, PickerResult(people: widget.initial, swapDay: true)),
          ),
        ),
      );
    }
    if (empties) {
      rows.add(
        _Entry(
          'empty',
          (_) => ListRow(
            title: l10n.pickerLeaveEmpty,
            leading: const Icon(Symbols.person_off_rounded),
            // Done at once: nothing further to open.
            chevron: false,
            onTap: () => Navigator.pop(
              context,
              PickerResult(people: const [], ranking: _ranking, takeOffList: _takeOff),
            ),
          ),
        ),
      );
    }
    if (widget.canRemove && !searching) {
      rows.add(
        _Entry(
          'remove',
          (_) => ListRow(
            title: l10n.removeDuty,
            destructive: true,
            onTap: () => Navigator.pop(
              context,
              PickerResult(people: widget.initial, removeDuty: true),
            ),
          ),
        ),
      );
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      // The sheet runs on under the keyboard; its end scrolls out above it.
      padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.viewInsetsOf(context).bottom),
      itemCount: rows.length,
      onReorder: (from, to) => _reorder(rows, from, to),
      itemBuilder: (_, i) => KeyedSubtree(key: ValueKey(rows[i].key), child: rows[i].build(i)),
    );
  }

  /// A row dragged from [from] to before [to], kept within its part of the
  /// list. The names of that part take their places in the duty's order
  /// in their new order; everyone else keeps theirs.
  void _reorder(List<_Entry> rows, int from, int to) {
    final part = rows[from].part;
    if (part == null) return;
    final first = rows.indexWhere((e) => e.part == part);
    final last = rows.lastIndexWhere((e) => e.part == part);
    final at = (to > from ? to - 1 : to).clamp(first, last);
    final names = [for (final e in rows.sublist(first, last + 1)) e.name!];
    names.insert(at - first, names.removeAt(from - first));
    final moved = names.toSet();
    final next = names.iterator;
    Haptics.selection();
    setState(
      () => _serving = _ranking = [
        for (final n in _serving)
          if (moved.contains(n)) (next..moveNext()).current else n,
      ],
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
    final row = _row(name, c, l10n, onTap: () => _choose(name, guest: true));
    if (!widget.rights.dropsFutureGuests) return row;
    void remove() => Navigator.pop(context, PickerResult(people: widget.initial, removeFutureGuest: name));
    return SwipeAction(
      key: ValueKey('guest/$name'),
      label: l10n.rosterRemoveFutureGuest,
      onAction: remove,
      child: row,
    );
  }

  /// One name. Ticking several, a circle before it; one at a time, a check
  /// after the one there. [dragAt] gives it a handle to drag by;
  /// [swipesOff] takes it off the duty's list, swiped to the end.
  Widget _row(
    String name,
    AppColors c,
    L10n l10n, {
    String? note,
    required VoidCallback onTap,
    int? dragAt,
    bool swipesOff = false,
  }) {
    final on = _selected.contains(name);
    Widget row = Semantics(
      selected: on,
      child: Material(
        color: c.surfaceRaised,
        child: ListRow(
          title: name,
          subtitle: note,
          leading: _tapReplaces
              ? null
              : Icon(
                  on ? Symbols.check_circle_rounded : Symbols.radio_button_unchecked_rounded,
                  fill: on ? 1 : 0,
                  color: on ? c.accent : c.tertiaryLabel,
                  size: 24,
                ),
          selected: _tapReplaces ? on : null,
          trailing: dragAt == null
              ? null
              : ReorderableDragStartListener(
                  index: dragAt,
                  child: Icon(Symbols.drag_handle_rounded, color: c.tertiaryLabel),
                ),
          chevron: false,
          onTap: onTap,
        ),
      ),
    );
    if (!swipesOff) return row;
    // Still listed after it, on the day or picked, it stays, off the list.
    return SwipeAction(
      key: ValueKey('off/$name'),
      label: l10n.pickerOffList,
      semanticLabel: l10n.pickerTakeOff(name),
      onAction: () => _takeOffList(name),
      child: row,
    );
  }
}

/// A row of the picker's list, keyed for dragging. [part], for a name on
/// the duty's list that drags: the run of rows it moves within.
class _Entry {
  const _Entry(this.key, this.build, {this.name, this.part});
  final String key;
  final Widget Function(int index) build;
  final String? name;
  final int? part;
}
