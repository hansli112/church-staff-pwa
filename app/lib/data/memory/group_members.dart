part of 'memory_backend.dart';

/// [MemoryChurchData] as functions/src/groupMembers.ts and
/// pendingMembers.ts do it.
mixin _MemoryGroupMembers on _MemoryChurchBase {
  @override
  Stream<List<PendingMember>> pendingMembers() => _b.watch(() {
    _requireRosterEditors();
    return (_b.pendingMembers[churchId] ?? const {}).values.toList();
  }, equals: _sameList);

  @override
  Future<void> deletePendingMember(String id) async {
    _requireAdmin();
    await _b.write(() {
      _b.pendingMembers[churchId]?.remove(id);
      _b.pendingRosterIds[churchId]?.remove(id);
      _b.claimAsks[churchId]?.removeWhere((_, a) => a.pendingId == id);
      _leaveFamilies(_b, churchId, id);
    });
  }

  @override
  Future<void> compareAndSetMember({required Member before, required Member after}) async {
    if (before.uid != after.uid) throw ArgumentError('member uid cannot change');
    _requireAdmin();
    if (after.uid == _uid && !after.isAdmin) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    _checkName(after.name);
    await _b.write(() {
      final members = _b.members[churchId]!;
      final current = members[after.uid];
      if (current == null) throw const CloudException(CloudErrorCode.notFound);
      if (!current.sameAdminFields(before)) {
        if (current.sameAdminFields(after)) return;
        throw const CloudException(CloudErrorCode.conflict);
      }
      // As memberToJson writes it.
      members[after.uid] = current.copyWith(
        name: after.name,
        role: after.role,
        groups: after.groups,
        zones: after.zones,
        identities: after.identities,
        smallGroups: after.smallGroups,
      );
    });
  }

  Future<void> setGroupMember(
    String uid,
    ChurchGroup group, {
    required bool member,
    List<String> duties = const [],
    List<String> smallGroups = const [],
  }) async {
    await _b.write(() {
      // As functions/src/groupMembers.ts: the group as it is now, then who
      // may move whom.
      final me = _b.requireMember(churchId);
      final members = _b.members[churchId]!;
      final service = switch (group) {
        ServiceGroup(:final id) => _b.services[churchId]!.byId(id),
        MinistryGroup() || SmallGroup() || GatheringGroup() => null,
      };
      final small = switch (group) {
        SmallGroup(:final id) => _b.smallGroups[churchId]?[id],
        _ => null,
      };
      final known = switch (group) {
        ServiceGroup() => service != null,
        // A 事工 has no 同工 of its own (#94), nor a 其他聚會.
        MinistryGroup() || GatheringGroup() => throw const CloudException(CloudErrorCode.unknown),
        SmallGroup() => small != null,
      };
      if (!known) throw const CloudException(CloudErrorCode.permissionDenied);
      final pending = _b.pendingMembers[churchId]?[uid];
      final them = members[uid] ?? (pending == null ? null : _pendingAsTarget(pending));
      if (them == null) throw const CloudException(CloudErrorCode.notFound);
      if (!me.mayMove(them, small?.group ?? group)) {
        throw const CloudException(CloudErrorCode.permissionDenied);
      }
      if (duties.any((d) => !(service?.duties.contains(d) ?? true))) throw const CloudException(CloudErrorCode.unknown);
      final next = them.inGroupAs(
        group,
        member: member,
        duties: duties.toSet().toList(),
        smallGroups: smallGroups.toSet().toList(),
      );
      if (pending == null) {
        members[uid] = next;
        return;
      }
      // One without an account may be in a 小組 by the name their move kept.
      _b.pendingMembers[churchId]![uid] = pending.copyWith(
        smallGroups: next.smallGroups,
        zones: [
          for (final z in next.zones)
            if (small != null && !member && z.serviceType == small.service)
              z.copyWith(
                smallGroups: [
                  for (final g in z.smallGroups)
                    if (g.trim() != small.name.trim()) g,
                ],
              )
            else
              z,
        ],
      );
    });
  }

  /// Pending member [p] as setGroupMember and setDuty read them: their own
  /// 小組 by ID, those their move named left in their zones.
  static Member _pendingAsTarget(PendingMember p) =>
      Member(uid: p.id, name: p.name, role: p.role, groups: p.groups, zones: p.zones, smallGroups: p.smallGroups);

  Future<String> addByName(String name, String serviceType) async {
    var id = '';
    await _b.write(() {
      // As functions/src/groupMembers.ts addByName.
      final me = _b.requireMember(churchId);
      final named = _text(name, TextLimits.profileName);
      if (_b.services[churchId]!.byId(serviceType) == null || !me.addsStaffTo(ServiceGroup(serviceType))) {
        throw const CloudException(CloudErrorCode.permissionDenied);
      }
      final key = nameKey(named);
      final pending = _b.pendingMembers[churchId] ??= {};
      if ([
        ..._b.members[churchId]!.values.map((m) => m.name),
        ...pending.values.map((p) => p.name),
      ].any((n) => nameKey(n) == key)) {
        throw const CloudException(CloudErrorCode.duplicateName);
      }
      id = 'named-${pending.length + 1}-${_b.clock().microsecondsSinceEpoch}';
      pending[id] = PendingMember(
        id: id,
        name: named,
        zones: [Zone(serviceType: serviceType)],
      );
    });
    return id;
  }

  Future<void> grantDuty(String uid, String serviceType, String duty) =>
      _setDuty(uid, serviceType, duty, (m) => m.withDuty(serviceType, duty), granting: true);

  Future<void> revokeDuty(String uid, String serviceType, String duty) =>
      _setDuty(uid, serviceType, duty, (m) => m.withoutDuty(serviceType, duty), granting: false);

  /// As functions/src/groupMembers.ts setDuty: [change] applied to member
  /// [uid] as they are when written, by whoever edits [duty]'s list.
  Future<void> _setDuty(
    String uid,
    String serviceType,
    String duty,
    Member Function(Member) change, {
    required bool granting,
  }) async {
    await _b.write(() {
      final me = _b.requireMember(churchId);
      final service = _b.services[churchId]!.byId(serviceType);
      final ministries = (_b.ministries[churchId] ?? const MinistrySettings()).ministries;
      if (service == null || !me.editsDutyList(ministries, serviceType, duty)) {
        throw const CloudException(CloudErrorCode.permissionDenied);
      }
      final pending = _b.pendingMembers[churchId]?[uid];
      final now = _b.members[churchId]![uid] ?? (pending == null ? null : _pendingAsTarget(pending));
      if (now == null) throw const CloudException(CloudErrorCode.notFound);
      if (granting && !service.duties.contains(duty)) throw const CloudException(CloudErrorCode.unknown);
      if (pending == null) {
        _b.members[churchId]![uid] = change(now);
      } else {
        _b.pendingMembers[churchId]![uid] = pending.copyWith(zones: change(now).zones);
      }
    });
  }

  @override
  Future<void> removeMember(String uid) async {
    final target = _b.memberOf(churchId, uid);
    // Leaving needs no open church: a member of a suspended one may go.
    final allowed = uid == _uid
        ? target != null && !target.isAdmin
        : _b.isActiveMember(churchId, _uid) && (_me?.isAdmin ?? false);
    if (!allowed) throw const CloudException(CloudErrorCode.permissionDenied);
    await _b.write(() {
      _b.members[churchId]!.remove(uid);
      // As onMemberDeleted: the church's notifications go with them, their
      // 不能服事的日子, and their place in a family.
      _b.notifications[uid]?.removeWhere((n) => n.churchId == churchId);
      _b.unavailable[churchId]?.remove(uid);
      _b.unavailableAsked[churchId]?.remove(uid);
      _b.unavailableSentAt[churchId]?.remove(uid);
      _b.unavailableChangedAt[churchId]?.remove(uid);
      _leaveFamilies(_b, churchId, uid);
    });
  }

  @override
  Future<void> setNotificationPrefs(
    String uid,
    Set<NotificationKind> muted,
  ) async {
    if (uid != _uid) throw const CloudException(CloudErrorCode.permissionDenied);
    final m = _b.requireMember(churchId);
    await _b.write(
      () => _b.members[churchId]![uid] = m.copyWith(mutedNotifications: muted),
    );
  }

  @override
  Future<void> setReminderTiming(String uid, ReminderTiming timing) async {
    if (uid != _uid) throw const CloudException(CloudErrorCode.permissionDenied);
    final m = _b.requireMember(churchId);
    await _b.write(
      () => _b.members[churchId]![uid] = m.copyWith(reminderTiming: timing),
    );
  }

  @override
  Future<void> setReminderHour(String uid, int hour) async {
    if (uid != _uid || !ReminderHours.valid(hour)) throw const CloudException(CloudErrorCode.permissionDenied);
    final m = _b.requireMember(churchId);
    await _b.write(() => _b.members[churchId]![uid] = m.copyWith(reminderHour: hour));
  }
}
