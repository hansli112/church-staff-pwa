import 'package:flutter/foundation.dart' show setEquals;

import 'day.dart';
import 'models.dart';
import 'staff_order.dart';

/// Name → uid for members whose name is unique in the church.
///
/// Two members with the same name get no uid: picking one would be a guess
/// and could send the reminder to the wrong person. Unbound names remain
/// visible guests but never become a member's personal services/reminders.
Map<String, String> uniqueNameIds(Iterable<Member> members) {
  final ids = <String, String>{};
  final duplicates = <String>{};
  for (final m in members) {
    final name = m.name.trim();
    if (name.isEmpty) continue;
    if (ids.containsKey(name)) duplicates.add(name);
    ids[name] = m.uid;
  }
  return {
    for (final e in ids.entries)
      if (!duplicates.contains(e.key)) e.key: e.value,
  };
}

/// [roster] with [role]'s people set to [people], sorted by [order].
/// Existing assignments keep their identity; new exact unique member names
/// receive a uid unless explicitly picked as guests. Adds a missing duty.
Roster withPeople(
  Roster roster,
  String role,
  List<String> people, {
  required Map<String, String> nameIds,
  required StaffOrder order,
  Set<String> guestNames = const {},
}) {
  final previous = roster.duties.where((d) => d.role == role).firstOrNull;
  final cleaned = <String>[];
  for (final p in people) {
    final name = p.trim();
    if (name.isNotEmpty && !cleaned.contains(name)) cleaned.add(name);
  }
  final sorted = order.sort(role, cleaned);
  final duty = Duty(
    role: role,
    people: sorted,
    uids: {
      for (final name in sorted)
        if (!guestNames.contains(name))
          name: ?((previous?.people.contains(name) ?? false) ? previous!.uids[name] : nameIds[name]),
    },
  );
  final exists = roster.duties.any((d) => d.role == role);
  return roster.copyWith(
    duties: exists ? [for (final d in roster.duties) d.role == role ? duty : d] : [...roster.duties, duty],
  );
}

Roster withoutDuty(Roster roster, String role) => roster.copyWith(
  duties: [
    for (final d in roster.duties)
      if (d.role != role) d,
  ],
);

/// The person in one duty on one day, a side of a swap.
class SwapSide {
  const SwapSide(this.roster, this.person);

  final Roster roster;

  /// Null for a day where nobody has the duty yet: the other person moves
  /// there.
  final String? person;
}

/// Swaps [a] and [b] in [role]. Both days are returned and must be written
/// together. People are re-sorted by [order], so the main person stays
/// first wherever they land (self-host swapped in place, which left them
/// second).
(Roster, Roster) swapPeople(
  String role,
  SwapSide a,
  SwapSide b, {
  required Map<String, String> nameIds,
  required StaffOrder order,
}) {
  List<String> replaced(Roster r, String? out, String? into) {
    final people = [
      for (final d in r.duties)
        if (d.role == role) ...d.people,
    ];
    final next = [
      for (final p in people)
        if (p != out) p,
    ];
    if (into != null && !next.contains(into)) next.add(into);
    return next;
  }

  Map<String, String> transferredIds(SwapSide source) {
    final ids = {...nameIds};
    final person = source.person;
    if (person == null) return ids;
    ids.remove(person);
    final duty = source.roster.duties.where((d) => d.role == role).firstOrNull;
    final uid = duty?.uids[person];
    if (uid != null) ids[person] = uid;
    return ids;
  }

  final aNext = withPeople(
    a.roster,
    role,
    replaced(a.roster, a.person, b.person),
    nameIds: transferredIds(b),
    order: order,
  );
  final bNext = withPeople(
    b.roster,
    role,
    replaced(b.roster, b.person, a.person),
    nameIds: transferredIds(a),
    order: order,
  );
  return (aNext, bNext);
}

/// Swap targets for [person] in [role] on [from]: every other day's people
/// in that duty, plus days where the duty is empty. People already serving
/// [role] on [from] are left out (swapping with them changes nothing).
List<SwapSide> swapTargets(
  Iterable<Roster> days,
  Roster from,
  String role,
  String person,
) {
  final here = {
    for (final d in from.duties)
      if (d.role == role) ...d.people,
  };
  final result = <SwapSide>[];
  for (final r in days) {
    if (r.day == from.day) continue;
    final duty = r.duties.where((d) => d.role == role).firstOrNull;
    if (duty == null) continue;
    final others = [
      for (final p in duty.people)
        if (p != person && !here.contains(p)) p,
    ];
    if (duty.people.contains(person)) continue;
    if (duty.people.isEmpty) {
      result.add(SwapSide(r, null));
    } else {
      for (final p in others) {
        result.add(SwapSide(r, p));
      }
    }
  }
  return result;
}

/// Whether [role] on [from] can be traded with [to] (#90): another day
/// that has the duty, with other people on it, or nobody.
bool canSwapDuty(String role, Roster from, Roster to) {
  if (from.day == to.day) return false;
  final a = from.duties.where((d) => d.role == role).firstOrNull;
  final b = to.duties.where((d) => d.role == role).firstOrNull;
  return a != null && b != null && !setEquals(a.people.toSet(), b.people.toSet());
}

/// [a] and [b] with whoever is on [role] traded, as they are (names, and
/// the members among them): moved there when the other has nobody. Both
/// have the duty (canSwapDuty), and are written together.
(Roster, Roster) withDutySwapped(String role, Roster a, Roster b) {
  Duty of(Roster r) => r.duties.firstWhere((d) => d.role == role);
  Roster put(Roster r, Duty from) => r.copyWith(
    duties: [for (final d in r.duties) d.role == role ? from : d],
  );
  return (put(a, of(b)), put(b, of(a)));
}

/// The exact saved documents shown before a future bulk change. Neither
/// planning nor extending the draft horizon writes any document.
class FutureRosterPlan {
  FutureRosterPlan({
    required Map<String, Roster?> before,
    required Map<String, Roster?> after,
    List<Roster> conflicts = const [],
  }) : before = Map.unmodifiable(before),
       after = Map.unmodifiable(after),
       conflicts = List.unmodifiable(conflicts);

  final Map<String, Roster?> before;
  final Map<String, Roster?> after;
  final List<Roster> conflicts;
  bool get isEmpty => before.isEmpty;
}

/// Removes only an exact unbound guest from this duty after today. The
/// same text bound to a member, another duty/service, today and history stay.
FutureRosterPlan planGuestRemoval({
  required Iterable<Roster> saved,
  required String type,
  required String role,
  required String name,
  required Day today,
}) {
  final before = <String, Roster?>{};
  final after = <String, Roster?>{};
  for (final r in saved) {
    if (r.isEvent || r.type != type || !r.day.isAfter(today)) continue;
    final duty = r.duties.where((d) => d.role == role).firstOrNull;
    if (duty == null || !duty.people.contains(name) || duty.uids.containsKey(name)) continue;
    before[r.id] = r;
    after[r.id] = r.copyWith(
      duties: [
        for (final d in r.duties)
          if (d.role == role)
            Duty(
              role: role,
              people: [
                for (final p in d.people)
                  if (p != name) p,
              ],
              uids: d.uids,
            )
          else
            d,
      ],
    );
  }
  return FutureRosterPlan(before: before, after: after);
}

/// Explicitly updates wording only on saved future services. A destination
/// duty already present is a conflict, not an invitation to merge identities.
FutureRosterPlan planDutyRename({
  required Iterable<Roster> saved,
  required String type,
  required String from,
  required String to,
  required Day today,
}) {
  final before = <String, Roster?>{};
  final after = <String, Roster?>{};
  final conflicts = <Roster>[];
  if (from == to) return FutureRosterPlan(before: before, after: after);
  for (final r in saved) {
    if (r.isEvent || r.type != type || !r.day.isAfter(today) || !r.duties.any((d) => d.role == from)) continue;
    if (r.duties.any((d) => d.role == to)) {
      conflicts.add(r);
      continue;
    }
    before[r.id] = r;
    after[r.id] = r.copyWith(
      duties: [
        for (final d in r.duties) d.role == from ? Duty(role: to, people: d.people, uids: d.uids) : d,
      ],
    );
  }
  return FutureRosterPlan(before: before, after: after, conflicts: conflicts);
}

/// Renames only future saved tags, keeping each day's chosen color. A
/// same-name destination is a conflict rather than silently dropping a tag.
FutureRosterPlan planEventRename({
  required Iterable<Roster> saved,
  required String type,
  required String from,
  required String to,
  required Day today,
}) {
  final before = <String, Roster?>{};
  final after = <String, Roster?>{};
  final conflicts = <Roster>[];
  if (from == to) return FutureRosterPlan(before: before, after: after);
  for (final r in saved) {
    if (r.isEvent || r.type != type || !r.day.isAfter(today) || !r.events.any((e) => e.name == from)) continue;
    if (r.events.any((e) => e.name == to)) {
      conflicts.add(r);
      continue;
    }
    before[r.id] = r;
    after[r.id] = r.copyWith(
      events: [
        for (final e in r.events) e.name == from ? EventTag(name: to, color: e.color) : e,
      ],
    );
  }
  return FutureRosterPlan(before: before, after: after, conflicts: conflicts);
}

/// [candidates] not on [roster] yet; only those [arranges] lets them
/// add (a 事工's 負責人, those it leads).
List<String> addableDuties(Roster roster, Iterable<String> candidates, Arranges arranges) {
  final present = {for (final d in roster.duties) d.role};
  return [
    for (final d in candidates)
      if (!present.contains(d) && arranges.has(d)) d,
  ];
}

/// Whether picking [people] for [duty] (with [guestNames] kept as names,
/// not members) changes who is on it: someone put on or taken off, or a
/// member now a guest of the same name. Order is the staff order's, not
/// the pick's.
bool pickChanges(Duty duty, List<String> people, {Set<String> guestNames = const {}}) =>
    !setEquals(people.toSet(), duty.people.toSet()) || guestNames.any(duty.uids.containsKey);
