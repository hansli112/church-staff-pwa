import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import '../domain/roster_edit.dart';
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
class RosterActions {
  RosterActions(this._ref);

  final Ref _ref;

  ChurchData get _data => _ref.read(churchDataProvider)!;

  Map<String, String> get _nameIds => uniqueNameIds(_ref.read(membersProvider).value ?? const []);

  StaffOrder _order(String type) => _ref.read(staffOrderProvider(type)).value ?? StaffOrder();

  /// [r]'s day as this device sees it now: saved, or the template draft.
  Roster _now(Roster r) {
    for (final s in _ref.read(savedRostersProvider).value ?? const <Roster>[]) {
      if (s.id == r.id) return s;
    }
    final service = _ref.read(servicesProvider).value?.byId(r.type);
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

  RosterWrite setEvents(Roster roster, List<EventTag> events) {
    final next = roster.copyWith(events: events);
    return (
      done: _data.saveRoster(next),
      undo: () {
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
    final saved = _ref.read(savedRostersProvider).value ?? const [];
    final resorted = [
      for (final r in saved)
        if (r.type == type)
          if (after.applyTo(r) case final next when !identical(next, r)) next,
    ];
    if (resorted.isNotEmpty) await _data.saveRosters(resorted);
  }

  /// Gives [member] the duty, so the picker lists them first next time.
  Future<void> grantDuty(Member member, String type, String role) => _data.saveMember(member.withDuty(type, role));
}

final rosterActionsProvider = Provider<RosterActions>(RosterActions.new);
