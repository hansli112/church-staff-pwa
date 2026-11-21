import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../domain/roster_edit.dart';
import '../domain/roster_news.dart';
import 'church_writes.dart';
import 'providers.dart';
import 'roster_actions.dart';
import 'staff_actions.dart';

/// Who is picked for a duty on a day, and what else picking them changes:
/// its list, its staff order, 同工 typed in to add.
@immutable
class DutyPick {
  const DutyPick({
    required this.people,
    this.ranking,
    this.putOnList = const [],
    this.takeOffList = const [],
    this.guestNames = const {},
    this.newStaff = const {},
  });

  /// The chosen names, any order (the staff order sorts them).
  final List<String> people;

  /// The new staff order for this duty, only if someone dragged it.
  final List<String>? ranking;

  /// Members to put on the duty's list, so they show up first next time.
  final List<Member> putOnList;

  /// Members taken off the duty's list.
  final List<Member> takeOffList;

  /// Names arranged this once (臨時排), not a same-name 同工.
  final Set<String> guestNames;

  /// Names typed to be 同工 without an account (新增同工), added to the
  /// service, on the duty's list, before the day is saved.
  final Set<String> newStaff;
}

/// A [DutyPick] saved, but for the day itself: [day] writes it, for the
/// caller to offer 復原 and to try again.
class DutyPickSave {
  DutyPickSave({this.day, required this.peopleChanged, required this.lists, this.undoTakeOff});

  /// Writes the day, its staff order with it; null when neither changed.
  final ChurchWrite Function()? day;

  /// Whether who is on the duty changed, not only its order.
  final bool peopleChanged;

  /// The list changes, written in turn behind each other; they show at
  /// once. Fails as the first that fails.
  final Future<void> lists;

  /// Puts those taken off the list back on; null when nobody was.
  final Future<void> Function()? undoTakeOff;
}

/// A 同工 typed in that could not be added: the day was not saved.
class StaffNotAdded implements Exception {
  const StaffNotAdded(this.name, this.error);

  final String name;
  final Object error;

  @override
  String toString() => 'StaffNotAdded($name): $error';
}

/// Picking people for a duty on a day (a day's page, an event's, 安排服事):
/// what one may change, and saving it.
class DutyPicking {
  DutyPicking(this._ref);

  final Ref _ref;

  /// What I may change picking for [duty] on [roster].
  DutyRights rightsOn(Roster roster, String duty) =>
      _ref
          .read(meProvider)
          .value
          ?.rightsOnDuty(
            roster,
            duty,
            services: _ref.read(servicesProvider).value,
            ministries: _ref.read(ministriesProvider).value?.ministries ?? const [],
          ) ??
      const DutyRights();

  /// Saves [pick] for [duty] on [roster]: the 同工 typed in first, each on
  /// the list of a duty the service has, so the day names them by ID; one
  /// that fails throws [StaffNotAdded] and nothing else is written. Then
  /// the list changes, and what writes the day.
  Future<DutyPickSave> save(Roster roster, Duty duty, DutyPick pick, {RosterVia via = RosterVia.app}) async {
    // Read before waiting: whoever asked can be gone by then.
    final actions = _ref.read(rosterActionsProvider);
    final staff = _ref.read(staffActionsProvider);
    final type = roster.type;
    final role = duty.role;
    final listed = !roster.isEvent && (_ref.read(servicesProvider).value?.byId(type)?.duties.contains(role) ?? false);
    final newIds = <String, String>{};
    for (final name in pick.newStaff) {
      try {
        newIds[name] = await staff.add(name, type, duty: listed ? role : null);
      } catch (e) {
        throw StaffNotAdded(name, e);
      }
    }
    final lists = Future.wait([
      for (final m in pick.putOnList) actions.grantDuty(m, type, role),
      for (final m in pick.takeOffList) actions.revokeDuty(m, type, role),
    ]);
    final changed = pickChanges(duty, pick.people, guestNames: pick.guestNames);
    final taken = pick.takeOffList;
    return DutyPickSave(
      day: changed || pick.ranking != null
          ? () => actions.setPeople(
              roster,
              role,
              pick.people,
              guestNames: pick.guestNames,
              ranking: pick.ranking,
              newIds: newIds,
              via: via,
            )
          : null,
      peopleChanged: changed,
      lists: lists,
      undoTakeOff: taken.isEmpty ? null : () => Future.wait([for (final m in taken) actions.grantDuty(m, type, role)]),
    );
  }
}

final dutyPickingProvider = Provider<DutyPicking>(DutyPicking.new);
