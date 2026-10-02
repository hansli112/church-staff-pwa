import 'package:flutter/foundation.dart';

import 'models.dart';

/// Per duty, who comes first: the main person is listed before the backup.
///
/// Ported from self-host (pure logic). Order belongs to the person, not to
/// the day: every day's names are sorted by this, so swapping someone into
/// another week does not leave the main person in second place.
@immutable
class StaffOrder {
  StaffOrder([Map<String, List<String>> rankingsByRole = const {}])
    : _byRole = Map.unmodifiable({
        for (final entry in rankingsByRole.entries)
          if (entry.key.trim().isNotEmpty)
            entry.key.trim(): List<String>.unmodifiable(
              _cleanNames(entry.value),
            ),
      });

  final Map<String, List<String>> _byRole;

  Map<String, List<String>> get rankingsByRole => _byRole;

  bool get isEmpty => _byRole.isEmpty;

  /// The ranking of [role], empty when nobody has ordered it.
  List<String> rankingOf(String role) => _byRole[role.trim()] ?? const [];

  /// [people] sorted by the ranking of [role].
  ///
  /// People not in the ranking (a visiting speaker, a new member) go after
  /// everyone ranked, keeping their relative order. Returns the same list
  /// when nothing moves, so callers can test with `identical`.
  List<String> sort(String role, List<String> people) {
    if (people.length < 2) return people;
    final ranking = rankingOf(role);
    if (ranking.isEmpty) return people;
    final rank = {for (var i = 0; i < ranking.length; i++) ranking[i]: i};
    final indexed = [
      for (var i = 0; i < people.length; i++) (name: people[i], at: i),
    ];
    // Original position as the tie-break: Dart's sort is not stable.
    indexed.sort((a, b) {
      final ra = rank[a.name.trim()] ?? ranking.length;
      final rb = rank[b.name.trim()] ?? ranking.length;
      if (ra != rb) return ra.compareTo(rb);
      return a.at.compareTo(b.at);
    });
    for (var i = 0; i < indexed.length; i++) {
      if (indexed[i].at != i) return [for (final e in indexed) e.name];
    }
    return people;
  }

  /// [roster] with every duty's people sorted. Same object when unchanged.
  Roster applyTo(Roster roster) {
    if (isEmpty) return roster;
    var changed = false;
    final duties = [
      for (final duty in roster.duties)
        () {
          final sorted = sort(duty.role, duty.people);
          if (identical(sorted, duty.people)) return duty;
          changed = true;
          return duty.copyWith(people: sorted);
        }(),
    ];
    return changed ? roster.copyWith(duties: duties) : roster;
  }

  /// This order with [role]'s ranking replaced. An empty [ranking] removes
  /// the role.
  StaffOrder withRanking(String role, List<String> ranking) {
    final next = Map<String, List<String>>.of(_byRole);
    final cleaned = _cleanNames(ranking);
    if (cleaned.isEmpty) {
      next.remove(role.trim());
    } else {
      next[role.trim()] = cleaned;
    }
    return StaffOrder(next);
  }

  /// The ranking shown in the picker for [role]: everyone ranked first, then
  /// [candidates] not yet ranked, in the order given (new members last).
  List<String> orderedCandidates(String role, Iterable<String> candidates) {
    final pool = candidates.toList();
    final set = pool.toSet();
    return [
      for (final name in rankingOf(role))
        if (set.contains(name)) name,
      for (final name in pool)
        if (!rankingOf(role).contains(name)) name,
    ];
  }

  /// Merge the roles [newer] ranks: people [newer] mentions follow its
  /// order; people it does not mention keep their place.
  ///
  /// Keeping their place rather than moving them last: a main person who is
  /// away for a season and missing from an imported sheet is still the main
  /// person when they come back.
  StaffOrder mergedWith(StaffOrder newer) {
    final next = Map<String, List<String>>.of(_byRole);
    for (final entry in newer._byRole.entries) {
      next[entry.key] = _merge(next[entry.key] ?? const [], entry.value);
    }
    return StaffOrder(next);
  }

  static List<String> _merge(List<String> base, List<String> newer) {
    final baseSet = base.toSet();
    final newerSet = newer.toSet();
    final known = newer.where(baseSet.contains).iterator;
    final result = [
      for (final name in base)
        if (newerSet.contains(name)) (known..moveNext()).current else name,
    ];
    for (var i = 0; i < newer.length; i++) {
      final name = newer[i];
      if (baseSet.contains(name)) continue;
      if (i > 0) {
        result.insert(result.indexOf(newer[i - 1]) + 1, name);
        continue;
      }
      final following = newer.skip(1).where(baseSet.contains).firstOrNull;
      if (following == null) {
        result.add(name);
      } else {
        result.insert(result.indexOf(following), name);
      }
    }
    return result;
  }

  /// Only the people [keep] accepts.
  StaffOrder where(bool Function(String name) keep) => StaffOrder({
    for (final entry in _byRole.entries)
      entry.key: entry.value.where(keep).toList(),
  });

  /// The roles that change going to [next]: the new ranking, or null for a
  /// role [next] drops.
  ///
  /// Writes send only these, never the whole document: this device's copy
  /// may be stale, and overwriting it would undo someone else's change.
  Map<String, List<String>?> changesTo(StaffOrder next) {
    final changes = <String, List<String>?>{};
    for (final entry in next._byRole.entries) {
      if (!listEquals(_byRole[entry.key], entry.value)) {
        changes[entry.key] = entry.value;
      }
    }
    for (final role in _byRole.keys) {
      if (!next._byRole.containsKey(role)) changes[role] = null;
    }
    return changes;
  }

  StaffOrder withChanges(Map<String, List<String>?> changes) {
    final next = Map<String, List<String>>.of(_byRole);
    for (final entry in changes.entries) {
      final ranking = entry.value;
      if (ranking == null) {
        next.remove(entry.key);
      } else {
        next[entry.key] = ranking;
      }
    }
    return StaffOrder(next);
  }

  /// Move rankings to the new names when duties are renamed.
  StaffOrder withRolesRenamed(Map<String, String> renamed) {
    if (renamed.isEmpty) return this;
    return StaffOrder({
      for (final entry in _byRole.entries)
        renamed[entry.key] ?? entry.key: entry.value,
    });
  }

  /// Learn a ranking from existing rosters: each person's average position
  /// in each duty. Used by the import, where old rosters already list the
  /// main person first.
  ///
  /// Average, not "latest": one sheet with two names swapped should not
  /// override the other weeks. Ties go to whoever appeared first. Days with
  /// a single person are skipped; they say nothing about order.
  static StaffOrder learnFrom(Iterable<Roster> rosters) {
    final totals = <String, Map<String, ({int sum, int count, int first})>>{};
    var seen = 0;
    for (final roster in rosters) {
      for (final duty in roster.duties) {
        final people = _cleanNames(duty.people);
        if (people.length < 2) continue;
        final byName = totals.putIfAbsent(duty.role.trim(), () => {});
        for (var i = 0; i < people.length; i++) {
          final prev = byName[people[i]];
          byName[people[i]] = (
            sum: (prev?.sum ?? 0) + i,
            count: (prev?.count ?? 0) + 1,
            first: prev?.first ?? seen,
          );
          seen++;
        }
      }
    }
    return StaffOrder({
      for (final entry in totals.entries)
        entry.key:
            (entry.value.entries.toList()..sort((a, b) {
                  final avgA = a.value.sum / a.value.count;
                  final avgB = b.value.sum / b.value.count;
                  if (avgA != avgB) return avgA.compareTo(avgB);
                  return a.value.first.compareTo(b.value.first);
                }))
                .map((e) => e.key)
                .toList(),
    });
  }

  factory StaffOrder.fromJson(Map<String, dynamic> json) {
    final roles = json['roles'];
    if (roles is! Map) return StaffOrder();
    return StaffOrder({
      for (final entry in roles.entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: [
            for (final name in entry.value as List<dynamic>)
              if (name is String) name,
          ],
    });
  }

  Map<String, dynamic> toJson() => {'roles': _byRole};

  @override
  bool operator ==(Object other) {
    if (other is! StaffOrder || other._byRole.length != _byRole.length) {
      return false;
    }
    for (final entry in _byRole.entries) {
      if (!listEquals(other._byRole[entry.key], entry.value)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(
    _byRole.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
  );

  /// Trimmed, without blanks or duplicates, order kept.
  static List<String> _cleanNames(Iterable<String> names) {
    final result = <String>[];
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty || result.contains(name)) continue;
      result.add(name);
    }
    return result;
  }
}
