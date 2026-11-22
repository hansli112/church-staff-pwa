part of 'memory_backend.dart';

/// [MemoryChurchData] as functions/src/claim.ts and claimAsks.ts do it.
mixin _MemoryClaim on _MemoryChurchBase implements ClaimData {
  Future<void> renamePending(String id, String name) async {
    // As functions/src/claim.ts renamePending.
    _functionAdmin();
    final named = _text(name, TextLimits.profileName);
    final pending = _b.pendingMembers[churchId] ?? {};
    final p = pending[id];
    if (p == null) throw const CloudException(CloudErrorCode.notFound);
    final key = nameKey(named);
    if ([
      ..._b.members[churchId]!.values.map((m) => m.name),
      for (final o in pending.values)
        if (o.id != id) o.name,
    ].any((n) => nameKey(n) == key)) {
      throw const CloudException(CloudErrorCode.duplicateName);
    }
    final staffOrders = _b.staffOrders[churchId] ?? {};
    for (final e in [...staffOrders.entries]) {
      staffOrders[e.key] = StaffOrder({
        for (final r in e.value.rankingsByRole.entries) r.key: [for (final n in r.value) n == p.name ? named : n],
      });
    }
    pending[id] = PendingMember(
      id: p.id,
      name: named,
      email: p.email,
      role: p.role,
      groups: p.groups,
      zones: p.zones,
      smallGroups: p.smallGroups,
      mutedNotifications: p.mutedNotifications,
    );
    final rosters = _b.rosters[churchId]!;
    for (final key in [...rosters.keys]) {
      final value = rosters[key]!;
      if (!value.duties.any((d) => d.uids.containsValue(id))) continue;
      rosters[key] = value.copyWith(duties: [for (final d in value.duties) d.renamed(id, named)]);
    }
    _b.notify();
  }

  @override
  Stream<List<ClaimAsk>> asks() => _b.watch(() {
    _requireAdmin();
    return (_b.claimAsks[churchId] ?? const <String, ClaimAsk>{}).values.toList();
  }, equals: _sameList);

  @override
  Stream<ClaimAsk?> askOf(String uid) => _b.watch(() {
    // As firestore.rules: their own, or an admin.
    final me = _b.requireMember(churchId);
    if (me.uid != uid && !me.isAdmin) throw const CloudException(CloudErrorCode.permissionDenied);
    return _b.claimAsks[churchId]?[uid];
  });

  @override
  Future<List<ClaimCandidate>> candidates() async {
    // As functions/src/claimAsks.ts claimCandidates.
    _b.functionAccess(churchId, allowed: (_) => true);
    final groups = {for (final g in _b.smallGroups[churchId]?.values ?? const <SmallGroupDetails>[]) g.id: g.name};
    return [
      for (final p in (_b.pendingMembers[churchId] ?? const <String, PendingMember>{}).values)
        if (p.name.trim().isNotEmpty)
          ClaimCandidate(
            pendingId: p.id,
            name: p.name.trim(),
            smallGroups: {
              for (final id in p.smallGroups) ?groups[id],
              for (final z in p.zones) ...z.smallGroups,
            }.toList(),
            serves: _servesOfPending(_b, churchId, p),
          ),
    ];
  }

  Future<void> askClaim(String? pendingId) async {
    // As functions/src/claimAsks.ts askClaim (the admins' push aside).
    final me = _b.functionAccess(churchId, allowed: (_) => true)!;
    final asks = _b.claimAsks[churchId] ??= {};
    if (pendingId == null) {
      asks.remove(me.uid);
    } else {
      final p = _b.pendingMembers[churchId]?[pendingId];
      if (p == null) throw const CloudException(CloudErrorCode.notFound);
      asks[me.uid] = ClaimAsk(uid: me.uid, name: me.name, pendingId: pendingId, pendingName: p.name);
    }
    _b.notify();
  }

  Future<void> answerClaim(String uid, {required bool allow}) async {
    _functionAdmin();
    final ask = _b.claimAsks[churchId]?[uid];
    if (ask == null) throw const CloudException(CloudErrorCode.notFound);
    if (allow) await mergePending(ask.pendingId, uid);
    _b.claimAsks[churchId]?.remove(uid);
    _b.notify();
  }

  Future<void> mergePending(String pendingId, String uid) async {
    _functionAdmin();
    await _b.mergeHeld?.future;
    final p = _b.pendingMembers[churchId]?[pendingId];
    final m = _b.memberOf(churchId, uid);
    if (p == null || m == null) throw const CloudException(CloudErrorCode.notFound);
    _b.members[churchId]![uid] = _absorb(m, p);
    _settlePending(_b, churchId, pendingId, uid);
    _b.notify();
  }
}
