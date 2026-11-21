part of 'memory_backend.dart';

/// [MemoryChurchData] as functions/src/smallGroups.ts does it.
mixin _MemorySmallGroups on _MemoryChurchBase {
  @override
  Stream<List<SmallGroupDetails>> smallGroups() => _b.watch(() {
    _requireMember();
    return (_b.smallGroups[churchId] ?? const {}).values.toList();
  }, equals: _sameList);

  /// As functions/src/smallGroups.ts.
  @override
  Future<String> saveSmallGroup(
    SmallGroupDetails group, {
    SmallGroupDetails? before,
    List<String>? leads,
    List<String>? leadsBefore,
  }) async {
    await _b.smallGroupSaveHeld?.future;
    final me = _b.functionAccess(churchId)!;
    final groups = _b.smallGroups.putIfAbsent(churchId, () => {});
    final was = group.id.isEmpty ? null : groups[group.id];
    if (group.id.isNotEmpty && was == null) throw const CloudException(CloudErrorCode.notFound);
    // Its 小組長 set when it meets, and nothing else.
    final scheduling =
        was != null &&
        leads == null &&
        group.name == was.name &&
        group.service == was.service &&
        me.schedulesSmallGroup(was.group);
    if (!scheduling && !me.mayEditSmallGroup(was?.service, group.service)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    // Where it is was not the app's to change, nor is it a change made over the undo.
    if (before != null && was != null && _stored(before.copyWith(order: () => was.order)) != was) {
      throw const CloudException(CloudErrorCode.conflict);
    }
    final members = _b.members[churchId]!;
    if (leadsBefore != null &&
        !setEquals(leadsBefore.toSet(), {
          for (final m in members.values)
            if (m.leadSmallGroups.contains(group.id)) m.uid,
        })) {
      throw const CloudException(CloudErrorCode.conflict);
    }
    if (_b.services[churchId]!.byId(group.service) == null) throw const CloudException(CloudErrorCode.unknown);
    // A day it meets: on its weekday. Those weeks of each month, the first four.
    if (group.startsOn case final start? when group.weekday == null || start.weekday != group.weekday) {
      throw const CloudException(CloudErrorCode.unknown);
    }
    if (group.monthWeeks.length > Limits.monthWeeks ||
        group.monthWeeks.toSet().length != group.monthWeeks.length ||
        group.monthWeeks.any((w) => w < 1 || w > Limits.monthWeeks)) {
      throw const CloudException(CloudErrorCode.unknown);
    }
    final name = group.name.trim();
    if (name.isEmpty || !withinTextLimit(name, TextLimits.profileName)) {
      throw const CloudException(CloudErrorCode.unknown);
    }
    if (leads != null && leads.any((u) => members[u] == null)) throw const CloudException(CloudErrorCode.notFound);
    final id = group.id.isEmpty ? 'sg${++_b._smallGroupIds}' : group.id;
    await _b.write(() {
      groups[id] = _stored(
        SmallGroupDetails(
          id: id,
          name: name,
          service: group.service,
          weekday: group.weekday,
          every: group.every,
          startsOn: group.startsOn,
          monthWeeks: group.monthWeeks,
          // Moved to another service: last there, till placed.
          order: was?.service == group.service ? was?.order : null,
        ),
      );
      if (leads == null) return;
      for (final m in [...members.values]) {
        members[m.uid] = m.withSmallGroupLead(id, lead: leads.contains(m.uid));
      }
    });
    return id;
  }

  /// [g] as the backend keeps it: when it meets only with a weekday.
  SmallGroupDetails _stored(SmallGroupDetails g) => SmallGroupDetails(
    id: g.id,
    name: g.name.trim(),
    service: g.service,
    weekday: g.weekday,
    every: g.weekday == null || g.monthWeeks.isNotEmpty ? 1 : g.every,
    startsOn: g.weekday == null ? null : g.startsOn,
    monthWeeks: g.weekday == null ? const [] : ([...g.monthWeeks]..sort()),
    order: g.order,
  );

  Future<void> orderSmallGroups(String service, List<String> ids) async {
    final me = _b.functionAccess(churchId)!;
    if (!me.mayEditSmallGroup(service, service)) throw const CloudException(CloudErrorCode.permissionDenied);
    if (ids.length > Limits.ordered) throw const CloudException(CloudErrorCode.unknown);
    final groups = _b.smallGroups.putIfAbsent(churchId, () => {});
    final now = {
      for (final g in groups.values)
        if (g.service == service) g.id,
    };
    if (ids.length != now.length || !setEquals(ids.toSet(), now)) throw const CloudException(CloudErrorCode.conflict);
    await _b.write(() {
      for (final (i, id) in ids.indexed) {
        groups[id] = groups[id]!.copyWith(order: () => i);
      }
    });
  }

  Future<void> deleteSmallGroup(String id) async {
    final me = _b.functionAccess(churchId)!;
    final was = _b.smallGroups[churchId]?[id];
    if (was == null) throw const CloudException(CloudErrorCode.notFound);
    if (!me.mayEditSmallGroup(was.service, null)) throw const CloudException(CloudErrorCode.permissionDenied);
    await _b.write(() {
      _b.smallGroups[churchId]!.remove(id);
      final members = _b.members[churchId]!;
      for (final m in [...members.values]) {
        if (!m.leadSmallGroups.contains(id) && !m.smallGroups.contains(id)) continue;
        members[m.uid] = m.withSmallGroupLead(id, lead: false).copyWith(smallGroups: {...m.smallGroups}..remove(id));
      }
      // The 同工 without an account put in it too.
      final pending = _b.pendingMembers[churchId] ?? {};
      for (final p in [...pending.values]) {
        if (p.smallGroups.contains(id)) pending[p.id] = p.copyWith(smallGroups: {...p.smallGroups}..remove(id));
      }
    });
  }
}
