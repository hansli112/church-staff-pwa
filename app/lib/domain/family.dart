/// 家人 (functions/src/family.ts): people of one church who see each
/// other's serving on 首頁, and hear about those of them without an account.
library;

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'schedule.dart';

/// One family, churches/{cid}/households/{id}: everyone in it ([people],
/// uids and IDs of the 同工 without an account, [noAccount] those), those
/// asked into it and not answered yet ([invited], each asked by
/// [invitedBy]), and everyone's name ([names]): not everyone may read the
/// member list.
@immutable
class Household {
  const Household({
    required this.id,
    required this.people,
    this.noAccount = const [],
    this.invited = const [],
    this.invitedBy = const {},
    this.names = const {},
  });

  final String id;
  final List<String> people;
  final List<String> noAccount;
  final List<String> invited;
  final Map<String, String> invitedBy;
  final Map<String, String> names;

  /// Who asked [uid] into it, by name.
  String askerOf(String uid) => names[invitedBy[uid]] ?? '';

  @override
  bool operator ==(Object other) =>
      other is Household &&
      other.id == id &&
      listEquals(other.people, people) &&
      listEquals(other.noAccount, noAccount) &&
      listEquals(other.invited, invited) &&
      mapEquals(other.invitedBy, invitedBy) &&
      mapEquals(other.names, names);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(people), Object.hashAll(invited));
}

/// Someone in the church to add as family, as 加入家人 lists them.
@immutable
class FamilyCandidate {
  const FamilyCandidate({required this.id, required this.name, required this.account});

  final String id;
  final String name;

  /// Has an account: asked, rather than in at once.
  final bool account;
}

/// One of my family: [asked] into it and not answered yet, or in it.
@immutable
class FamilyPerson {
  const FamilyPerson({required this.id, required this.name, required this.account, this.asked = false});

  final String id;
  final String name;
  final bool account;
  final bool asked;

  @override
  bool operator ==(Object other) =>
      other is FamilyPerson && other.id == id && other.name == name && other.account == account && other.asked == asked;

  @override
  int get hashCode => Object.hash(id, name, account, asked);
}

/// My family from the households I am in ([mine]), without me ([me]):
/// those in it, as listed, then those asked; each once.
List<FamilyPerson> familyOf(Iterable<Household> mine, String me) {
  final out = <String, FamilyPerson>{};
  for (final h in mine) {
    for (final id in h.people) {
      if (id == me) continue;
      out.putIfAbsent(
        id,
        () => FamilyPerson(id: id, name: h.names[id] ?? '', account: !h.noAccount.contains(id)),
      );
    }
  }
  for (final h in mine) {
    for (final id in h.invited) {
      if (id == me) continue;
      out.putIfAbsent(id, () => FamilyPerson(id: id, name: h.names[id] ?? '', account: true, asked: true));
    }
  }
  return out.values.toList();
}

/// A day someone serves on 首頁: mine ([who] null), or one of my family's.
typedef FamilyServing = ({MyService service, FamilyPerson? who});

/// The days [me] and my [family] serve on [rosters], soonest first; on a
/// day, mine first, then my family's as listed. Not those only asked.
/// [mySmallGroups]: mine, whose duties are mine too (服事交給小組); my
/// family's are not known here.
List<FamilyServing> servingWithFamily(
  Iterable<Roster> rosters, {
  required String me,
  required List<FamilyPerson> family,
  Set<String> mySmallGroups = const {},
}) {
  final out = <FamilyServing>[
    for (final s in myServices(rosters, uid: me, smallGroups: mySmallGroups)) (service: s, who: null),
    for (final p in family)
      if (!p.asked)
        for (final s in myServices(rosters, uid: p.id)) (service: s, who: p),
  ];
  // A stable sort: by day, keeping mine before my family's.
  final indexed = out.indexed.toList()
    ..sort((a, b) {
      final byDay = a.$2.service.roster.day.compareTo(b.$2.service.roster.day);
      return byDay != 0 ? byDay : a.$1.compareTo(b.$1);
    });
  return [for (final (_, s) in indexed) s];
}
