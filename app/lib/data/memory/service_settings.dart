part of 'memory_backend.dart';

/// [MemoryChurchData] as functions/src/serviceSettings.ts and
/// ministries.ts do it.
mixin _MemoryServiceSettings on _MemoryChurchBase {
  @override
  Future<void> compareAndSetMinistries({required List<Ministry> before, required List<Ministry> after}) async {
    _requireAdmin();
    await _b.write(() {
      final current = _b.ministries[churchId] ?? const MinistrySettings();
      if (!listEquals(current.ministries, before)) {
        if (listEquals(current.ministries, after)) return;
        throw const CloudException(CloudErrorCode.conflict);
      }
      _b.ministries[churchId] = current.withMinistries(after);
    });
  }

  @override
  Future<void> compareAndSetServiceList({required List<Service> before, required List<Service> after}) async {
    _requireAdmin();
    if (after.length > Limits.services) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    await _b.write(() {
      final settings = _b.services[churchId]!;
      if (!listEquals(settings.services, before)) {
        if (listEquals(settings.services, after)) return;
        throw const CloudException(CloudErrorCode.conflict);
      }
      _b.services[churchId] = settings.withServices(after);
    });
  }

  @override
  Future<void> compareAndSetService({
    required Service before,
    required Service after,
    ({String from, String to})? dutyRename,
  }) async {
    if (before.id != after.id) throw ArgumentError('service id cannot change');
    await _b.write(() {
      _requireAdmin();
      if (![before, after].every((s) => validServiceShape(s) && validServiceTime(s))) {
        throw const CloudException(CloudErrorCode.unknown);
      }
      final settings = _b.services[churchId]!;
      if (settings.byId(before.id) != before) throw const CloudException(CloudErrorCode.conflict);
      if (dutyRename case final rename?) {
        if (!validDutyRename(before: before.duties, after: after.duties, from: rename.from, to: rename.to)) {
          throw const CloudException(CloudErrorCode.unknown);
        }
        final orders = _b.staffOrders[churchId]!;
        final order = orders[before.id];
        if (order?.rankingsByRole.containsKey(rename.to) ?? false) throw const CloudException(CloudErrorCode.conflict);
        bool affected(List<Zone> zones) =>
            zones.any((zone) => zone.serviceType == before.id && zone.duties.contains(rename.from));
        final changedMembers = _b.members[churchId]!.values.where((member) => affected(member.zones)).length;
        final changedPending = (_b.pendingMembers[churchId]?.values ?? const <PendingMember>[])
            .where((member) => affected(member.zones))
            .length;
        if (1 + changedMembers + changedPending + ((order?.rankingsByRole.containsKey(rename.from) ?? false) ? 1 : 0) >
            RosterChange.maxWrites) {
          throw const CloudException(CloudErrorCode.quotaExceeded, reason: CloudReason.tooManyChanges);
        }
        List<Zone> renamed(List<Zone> zones) => [
          for (final zone in zones)
            zone.serviceType == before.id
                ? zone.copyWith(
                    duties: {for (final duty in zone.duties) duty == rename.from ? rename.to : duty}.toList(),
                  )
                : zone,
        ];
        final members = _b.members[churchId]!;
        for (final entry in members.entries.toList()) {
          if (affected(entry.value.zones)) members[entry.key] = entry.value.copyWith(zones: renamed(entry.value.zones));
        }
        final pending = _b.pendingMembers[churchId];
        if (pending != null) {
          for (final entry in pending.entries.toList()) {
            final member = entry.value;
            if (!affected(member.zones)) continue;
            pending[entry.key] = PendingMember(
              id: member.id,
              name: member.name,
              email: member.email,
              role: member.role,
              groups: member.groups,
              zones: renamed(member.zones),
              mutedNotifications: member.mutedNotifications,
            );
          }
        }
        if (order?.rankingsByRole.containsKey(rename.from) ?? false) {
          orders[before.id] = order!.withRolesRenamed({rename.from: rename.to});
        }
        // The 事工 that link the duty keep leading it (#82).
        if (_b.ministries[churchId] case final m?) {
          _b.ministries[churchId] = MinistrySettings(
            ids: m.ids,
            ministries: [
              for (final ministry in m.ministries)
                ministry.copyWith(
                  duties: [
                    for (final d in ministry.duties)
                      d.service == before.id && d.duty == rename.from ? MinistryDuty(d.service, rename.to) : d,
                  ],
                ),
            ],
          );
        }
      }
      _b.services[churchId] = settings.withServices([
        for (final service in settings.services) service.id == before.id ? after : service,
      ]);
    });
  }
}
