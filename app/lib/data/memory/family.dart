part of 'memory_backend.dart';

/// [MemoryChurchData] as functions/src/family.ts does it (the pushes aside).
mixin _MemoryFamily on _MemoryChurchBase implements FamilyData {
  Map<String, Household> get _households => _b.households[churchId] ??= {};

  @override
  Stream<List<Household>> mine() => _b.watch(() {
    _requireMember();
    return [
      for (final h in _households.values)
        if (h.people.contains(_uid)) h,
    ];
  }, equals: listEquals);

  @override
  Stream<List<Household>> asking() => _b.watch(() {
    _requireMember();
    return [
      for (final h in _households.values)
        if (h.invited.contains(_uid)) h,
    ];
  }, equals: listEquals);

  @override
  Future<List<FamilyCandidate>> addable() async {
    final me = _b.functionAccess(churchId, allowed: (_) => true)!;
    return [
      for (final m in _b.members[churchId]!.values)
        if (m.uid != me.uid && m.name.trim().isNotEmpty) FamilyCandidate(id: m.uid, name: m.name.trim(), account: true),
      for (final p in (_b.pendingMembers[churchId] ?? const <String, PendingMember>{}).values)
        if (p.name.trim().isNotEmpty) FamilyCandidate(id: p.id, name: p.name.trim(), account: false),
    ];
  }

  Future<void> addFamily(String id) async {
    final me = _b.functionAccess(churchId, allowed: (_) => true)!;
    if (id == me.uid) throw const CloudException(CloudErrorCode.unknown);
    final member = _b.memberOf(churchId, id);
    final pending = _b.pendingMembers[churchId]?[id];
    if (member == null && pending == null) throw const CloudException(CloudErrorCode.notFound);
    final mine = [
      for (final h in _households.values)
        if (h.people.contains(me.uid)) h,
    ];
    if (mine.any((h) => h.people.contains(id) || h.invited.contains(id))) return;
    final h = mine.firstOrNull ?? Household(id: 'family${++_b._familyIds}', people: [me.uid], names: {me.uid: me.name});
    _households[h.id] = member != null
        ? Household(
            id: h.id,
            people: h.people,
            noAccount: h.noAccount,
            invited: [...h.invited, id],
            invitedBy: {...h.invitedBy, id: me.uid},
            names: {...h.names, id: member.name},
          )
        : Household(
            id: h.id,
            people: [...h.people, id],
            noAccount: [...h.noAccount, id],
            invited: h.invited,
            invitedBy: h.invitedBy,
            names: {...h.names, id: pending!.name},
          );
    _b.notify();
  }

  Future<void> answerFamily(String householdId, {required bool yes}) async {
    final me = _b.functionAccess(churchId, allowed: (_) => true)!;
    final h = _households[householdId];
    if (h == null || !h.invited.contains(me.uid)) throw const CloudException(CloudErrorCode.notFound);
    final asked = _without(h, me.uid);
    if (!yes) {
      _put(asked);
    } else {
      final others = [
        for (final o in _households.values)
          if (o.id != h.id && o.people.contains(me.uid)) o,
      ];
      final people = [...asked.people, me.uid];
      final noAccount = [...asked.noAccount];
      final invited = [...asked.invited];
      final invitedBy = {...asked.invitedBy};
      var names = {...h.names};
      for (final o in others) {
        for (final p in o.people) {
          if (!people.contains(p)) people.add(p);
        }
        for (final p in o.noAccount) {
          if (!noAccount.contains(p)) noAccount.add(p);
        }
        for (final p in o.invited) {
          if (people.contains(p) || invited.contains(p)) continue;
          invited.add(p);
          invitedBy[p] = o.invitedBy[p] ?? '';
        }
        names = {...o.names, ...names};
        _households.remove(o.id);
      }
      _households[h.id] = Household(
        id: h.id,
        people: people,
        noAccount: noAccount,
        invited: [
          for (final p in invited)
            if (!people.contains(p)) p,
        ],
        invitedBy: {
          for (final e in invitedBy.entries)
            if (!people.contains(e.key)) e.key: e.value,
        },
        names: names,
      );
    }
    _b.notify();
  }

  Future<void> removeFamily(String id) async {
    final me = _b.functionAccess(churchId, allowed: (_) => true)!;
    for (final h in [..._households.values]) {
      if (h.people.contains(me.uid)) _put(_without(h, id));
    }
    _b.notify();
  }

  void _put(Household h) {
    if (_lasts(h)) {
      _households[h.id] = h;
    } else {
      _households.remove(h.id);
    }
  }
}

/// [h] without [who]: out of it, or no longer asked; so go the asks
/// [who] made.
Household _without(Household h, String who) {
  final gone = {who, ...h.invited.where((p) => h.invitedBy[p] == who)};
  return Household(
    id: h.id,
    people: [
      for (final p in h.people)
        if (p != who) p,
    ],
    noAccount: [
      for (final p in h.noAccount)
        if (p != who) p,
    ],
    invited: [
      for (final p in h.invited)
        if (!gone.contains(p)) p,
    ],
    invitedBy: {
      for (final e in h.invitedBy.entries)
        if (!gone.contains(e.key)) e.key: e.value,
    },
    names: {
      for (final e in h.names.entries)
        if (e.key != who && (!gone.contains(e.key) || h.people.contains(e.key))) e.key: e.value,
    },
  );
}

/// Whether [h] is a family still: someone with an account in it, and someone besides.
bool _lasts(Household h) => h.people.any((p) => !h.noAccount.contains(p)) && h.people.length + h.invited.length > 1;

/// [who] left church [cid], or was deleted: out of every family, as
/// functions/src/family.ts leaveFamilies.
void _leaveFamilies(MemoryBackend b, String cid, String who) {
  final households = b.households[cid];
  if (households == null) return;
  for (final h in [...households.values]) {
    if (!h.people.contains(who) && !h.invited.contains(who)) continue;
    final next = _without(h, who);
    if (_lasts(next)) {
      households[h.id] = next;
    } else {
      households.remove(h.id);
    }
  }
}

/// [who] is called [name] now, in their families too.
void _renameInFamilies(MemoryBackend b, String cid, String who, String name) {
  final households = b.households[cid];
  if (households == null) return;
  for (final h in [...households.values]) {
    if (!h.names.containsKey(who)) continue;
    households[h.id] = Household(
      id: h.id,
      people: h.people,
      noAccount: h.noAccount,
      invited: h.invited,
      invitedBy: h.invitedBy,
      names: {...h.names, who: name},
    );
  }
}

/// Pending member [pid] is member [uid] now: their families keep them, as
/// functions/src/family.ts repointFamily.
void _repointFamily(MemoryBackend b, String cid, String pid, String uid, String name) {
  final households = b.households[cid];
  if (households == null) return;
  for (final h in [...households.values]) {
    if (!h.people.contains(pid)) continue;
    final next = _without(h, pid);
    households[h.id] = Household(
      id: h.id,
      people: [...next.people, if (!next.people.contains(uid)) uid],
      noAccount: next.noAccount,
      invited: [
        for (final p in next.invited)
          if (p != uid) p,
      ],
      invitedBy: {
        for (final e in next.invitedBy.entries)
          if (e.key != uid) e.key: e.value,
      },
      names: {...next.names, uid: name},
    );
  }
}
