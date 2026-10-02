import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import '../domain/roster_edit.dart';
import '../domain/staff_order.dart';
import 'providers.dart';

/// Writes for 安排服事表. Every write returns what to restore for 「復原」,
/// so screens can undo instead of asking for confirmation.
class RosterActions {
  RosterActions(this._ref);

  final Ref _ref;

  ChurchData get _data => _ref.read(churchDataProvider)!;

  Map<String, String> get _nameIds => uniqueNameIds(_ref.read(membersProvider).value ?? const []);

  StaffOrder _order(String type) => _ref.read(staffOrderProvider(type)).value ?? StaffOrder();

  /// Saves [next] and returns an undo that puts [previous] back. A day that
  /// was only a draft before is deleted again, so it follows the template.
  Future<Future<void> Function()> _save(Roster previous, Roster next) async {
    await _data.saveRoster(next);
    return () => previous.saved ? _data.saveRoster(previous) : _data.deleteRoster(previous);
  }

  Future<Future<void> Function()> setPeople(
    Roster roster,
    String role,
    List<String> people,
  ) => _save(
    roster,
    withPeople(
      roster,
      role,
      people,
      nameIds: _nameIds,
      order: _order(roster.type),
    ),
  );

  Future<Future<void> Function()> removeDuty(Roster roster, String role) => _save(roster, withoutDuty(roster, role));

  Future<Future<void> Function()> addDuty(Roster roster, String role) => setPeople(roster, role, const []);

  Future<Future<void> Function()> setEvents(
    Roster roster,
    List<EventTag> events,
  ) => _save(roster, roster.copyWith(events: events));

  /// Swaps two people in [role] in one write; the undo is one write too.
  Future<Future<void> Function()> swap(
    String role,
    SwapSide a,
    SwapSide b,
  ) async {
    final (a2, b2) = swapPeople(
      role,
      a,
      b,
      nameIds: _nameIds,
      order: _order(a.roster.type),
    );
    await _data.saveRosters([a2, b2]);
    return () async {
      final restore = [a.roster, b.roster];
      final drafts = restore.where((r) => !r.saved).toList();
      await _data.saveRosters([
        for (final r in restore)
          if (r.saved) r,
      ]);
      for (final d in drafts) {
        await _data.deleteRoster(d);
      }
    };
  }

  /// Saves a new ranking for [role] and re-sorts the upcoming saved days
  /// that list more than one person in it. Writes nothing when nothing
  /// moved.
  Future<void> setRanking(
    String type,
    String role,
    List<String> ranking,
  ) async {
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
