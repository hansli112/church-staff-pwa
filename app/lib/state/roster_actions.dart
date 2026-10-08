import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import '../domain/roster_edit.dart';
import '../domain/roster_import.dart';
import '../domain/schedule.dart';
import '../domain/staff_order.dart';
import 'providers.dart';

/// A write that has been issued, and how to take it back.
///
/// [done] completes when the server has it; offline it waits, while the
/// change already shows on this device. [undo] restores only what this
/// write touched, applied to the day as it is when undo is tapped, so a
/// change someone else made meanwhile is kept.
typedef RosterWrite = ({Future<void> done, Future<void> Function() undo});

/// Writes for 安排服事表. Each returns a [RosterWrite], so screens offer
/// 「復原」 instead of asking for confirmation.
///
/// It reads the church's services, saved rosters, members and staff orders
/// as this device has them. A screen that edits a service watches
/// [rosterEditingProvider] for it, which keeps all of them loaded and says
/// when they are; a write before then fails rather than guess.
class RosterActions {
  RosterActions(this._ref);

  final Ref _ref;

  ChurchData get _data => _ref.churchData;

  static T _loaded<T>(AsyncValue<T> value, String what) =>
      value.hasValue ? value.requireValue : throw StateError('$what not loaded');

  ServiceSettings get _services => _loaded(_ref.read(servicesProvider), 'services');

  List<Roster> get _saved => _loaded(_ref.read(savedRostersProvider), 'rosters');

  Map<String, String> get _nameIds => uniqueNameIds(_loaded(_ref.read(membersProvider), 'members'));

  StaffOrder _order(String type) => _loaded(_ref.read(staffOrderProvider(type)), 'staff order');

  /// [r]'s day as this device sees it now: saved, or the template draft.
  Roster _now(Roster r) {
    for (final s in _saved) {
      if (s.id == r.id) return s;
    }
    final service = _services.byId(r.type);
    return service == null ? r.copyWith(saved: false) : draftRoster(service, r.day);
  }

  /// Puts [role] back to [previous] (or removes it when it did not exist)
  /// on the day as it is now, at its old position.
  Roster _withDutyRestored(Roster now, String role, Duty? previous, int index) {
    final rest = [
      for (final d in now.duties)
        if (d.role != role) d,
    ];
    if (previous == null) return now.copyWith(duties: rest);
    rest.insert(index.clamp(0, rest.length), previous);
    return now.copyWith(duties: rest);
  }

  bool _untouchedDraft(Roster before, Roster next) =>
      !before.saved && _now(before).copyWith(saved: false) == next.copyWith(saved: false);

  /// Writes [next] over [before], which differ only in [role]; undo
  /// restores that duty.
  RosterWrite _dutyWrite(Roster before, Roster next, String role) {
    final index = before.duties.indexWhere((d) => d.role == role);
    final previous = index < 0 ? null : before.duties[index];
    return (
      done: _data.saveRoster(next),
      undo: () {
        // A day that was only a draft and that nobody touched since goes
        // back to following the template.
        if (_untouchedDraft(before, next)) return _data.deleteRoster(before);
        return _data.saveRoster(_withDutyRestored(_now(before), role, previous, index));
      },
    );
  }

  RosterWrite setPeople(Roster roster, String role, List<String> people) => _dutyWrite(
    roster,
    withPeople(roster, role, people, nameIds: _nameIds, order: _order(roster.type)),
    role,
  );

  RosterWrite removeDuty(Roster roster, String role) => _dutyWrite(roster, withoutDuty(roster, role), role);

  RosterWrite addDuty(Roster roster, String role) => setPeople(roster, role, const []);

  /// Sets [roster]'s special events; [addToCommon] also become choices for
  /// every day of the service. Undo takes back both.
  RosterWrite setEvents(Roster roster, List<EventTag> events, {List<EventTag> addToCommon = const []}) {
    final next = roster.copyWith(events: events);
    // Ticking a tag off and on again only moves it to the end: the day
    // stays as it is (a draft stays a draft).
    final changed = !setEquals(events.toSet(), roster.events.toSet());
    final services = _services;
    final service = services.byId(roster.type);
    final common = addToCommon.isEmpty || service == null
        ? null
        : [
            for (final s in services.services)
              s.id == service.id ? s.copyWith(events: [...s.events, ...addToCommon]) : s,
          ];
    Future<void> done() async {
      if (common != null) await _data.saveServices(common);
      if (changed) await _data.saveRoster(next);
    }

    return (
      done: done(),
      undo: () async {
        if (common != null) {
          await _data.saveServices([
            for (final s in _services.services)
              s.id == service!.id
                  ? s.copyWith(
                      events: [
                        for (final e in s.events)
                          if (!addToCommon.contains(e)) e,
                      ],
                    )
                  : s,
          ]);
        }
        if (!changed) return;
        if (_untouchedDraft(roster, next)) return _data.deleteRoster(roster);
        return _data.saveRoster(_now(roster).copyWith(events: roster.events));
      },
    );
  }

  /// Swaps two people in [role] in one batch; undo puts both days' [role]
  /// back, also in one batch.
  RosterWrite swap(String role, SwapSide a, SwapSide b) {
    final (a2, b2) = swapPeople(role, a, b, nameIds: _nameIds, order: _order(a.roster.type));
    int indexOf(Roster r) => r.duties.indexWhere((d) => d.role == role);
    Duty? dutyOf(Roster r) => indexOf(r) < 0 ? null : r.duties[indexOf(r)];
    final prevA = dutyOf(a.roster), prevB = dutyOf(b.roster);
    final idxA = indexOf(a.roster), idxB = indexOf(b.roster);
    return (
      done: _data.saveRosters([a2, b2]),
      undo: () => _data.saveRosters([
        _withDutyRestored(_now(a.roster), role, prevA, idxA),
        _withDutyRestored(_now(b.roster), role, prevB, idxB),
      ]),
    );
  }

  /// Saves a new ranking for [role] and re-sorts the upcoming saved days.
  /// Writes nothing when nothing moved.
  Future<void> setRanking(String type, String role, List<String> ranking) async {
    final before = _order(type);
    final after = before.withRanking(role, ranking);
    final changes = before.changesTo(after);
    if (changes.isEmpty) return;
    await _data.updateStaffOrder(type, changes);
    final resorted = [
      for (final r in _saved)
        if (r.type == type)
          if (after.applyTo(r) case final next when !identical(next, r)) next,
    ];
    if (resorted.isNotEmpty) await _data.saveRosters(resorted);
  }

  /// Gives [member] the duty, so the picker lists them first next time.
  Future<void> grantDuty(Member member, String type, String role) => _data.saveMember(member.withDuty(type, role));

  /// What importing [rows] into [type] would do, against the rosters as
  /// they are now.
  ImportPlan previewImport(String type, List<dynamic> rows) => planImport(
    rows: rows,
    service: _services.byId(type) ?? (throw StateError('No service $type')),
    members: _loaded(_ref.read(membersProvider), 'members'),
    saved: _saved,
    order: _order(type),
    today: _ref.read(todayProvider),
  );

  /// Imports [rows] into [type], planned again now so edits made since the
  /// preview are not overwritten, and the staff order the plan grew. Undo
  /// puts back each imported day whole, as it was before the import (an
  /// edit made to it since is lost), and the staff order.
  RosterWrite applyImport(String type, List<dynamic> rows) {
    final plan = previewImport(type, rows);
    final before = {
      for (final r in _saved)
        if (r.type == type) r.id: r,
    };
    final order = _order(type);
    final changes = order.changesTo(plan.order);
    Future<void> done() async {
      await _data.saveRosters(plan.rosters, via: 'import');
      if (changes.isNotEmpty) await _data.updateStaffOrder(type, changes);
    }

    return (
      done: done(),
      undo: () async {
        final restore = [
          for (final r in plan.rosters) ?before[r.id],
        ];
        // As an import too: the import told nobody, nor does taking it back.
        if (restore.isNotEmpty) await _data.saveRosters(restore, via: 'import');
        for (final r in plan.rosters) {
          if (!before.containsKey(r.id)) await _data.deleteRoster(r);
        }
        final back = plan.order.changesTo(order);
        if (back.isNotEmpty) await _data.updateStaffOrder(type, back);
      },
    );
  }
}

/// Whether everything [RosterActions] reads for service [type] is loaded.
/// A screen that edits the service watches this, which also keeps it
/// loaded: Riverpod pauses what nobody watches.
final rosterEditingProvider = Provider.autoDispose.family<bool, String>((ref, type) {
  final loaded = [
    ref.watch(servicesProvider),
    ref.watch(savedRostersProvider),
    ref.watch(membersProvider),
    ref.watch(staffOrderProvider(type)),
  ];
  return loaded.every((v) => v.hasValue);
});
final rosterActionsProvider = Provider<RosterActions>(RosterActions.new);
