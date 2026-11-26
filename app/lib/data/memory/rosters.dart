part of 'memory_backend.dart';

/// [MemoryChurchData] as functions/src/rosterChange.ts and ledDuties.ts
/// do it, with firestore.rules for a day written directly.
mixin _MemoryRosters on _MemoryChurchBase {
  @override
  Stream<List<Roster>> rosters({required Day from}) => _b.watch(() {
    _requireMember();
    return (_b.rosters[churchId]!.values.where((r) => !r.lastDay.isBefore(from)).toList()
      ..sort((a, b) => a.day.compareTo(b.day)));
  }, equals: _sameList);

  @override
  Stream<StaffOrder> staffOrder(String serviceType) => _b.watch(() {
    _requireMember();
    return _b.staffOrders[churchId]![serviceType] ?? StaffOrder();
  });

  @override
  Future<List<Roster>> pastRosters({required Day from, required Day before}) async {
    _requireMember();
    return [
      for (final r in _b.rosters[churchId]!.values)
        if (!r.day.isBefore(from) && r.day.isBefore(before)) r,
    ];
  }

  @override
  Future<Roster?> rosterBefore({required String serviceType, required Day before}) async {
    _requireMember();
    Roster? latest;
    for (final r in _b.rosters[churchId]!.values) {
      if (r.forEvent != null || r.type != serviceType || !r.day.isBefore(before)) continue;
      if (latest == null || r.day.isAfter(latest.day)) latest = r;
    }
    return latest;
  }

  @override
  Future<List<Roster>> eventRosters() async {
    _requireMember();
    return [
      for (final r in _b.rosters[churchId]!.values)
        if (r.forEvent case final e? when !e.cancelled) r,
    ]..sort((a, b) => b.day.compareTo(a.day));
  }

  @override
  Future<void> compareAndSetRosters(RosterChange change) async {
    final RosterChange(:staffOrder) = change;
    final uid = _uid;
    await _b.write(() {
      if (_uid != uid) throw const CloudException(CloudErrorCode.permissionDenied);
      _requireMember();
      final saved = _b.rosters[churchId]!;
      final savedOrder = switch (staffOrder) {
        final o? => _b.staffOrders[churchId]![o.serviceType] ?? StaffOrder(),
        null => null,
      };
      if (!change.before.keys.every((id) => change.expects(id, saved[id])) || savedOrder != staffOrder?.before) {
        // Saved already: this change sent before, its answer lost.
        if (change.before.keys.every((id) => change.landed(id, saved[id])) && savedOrder == staffOrder?.after) return;
        throw const CloudException(CloudErrorCode.conflict);
      }
      if (staffOrder case final order?) _requireRosterEditor(order.serviceType);
      // Check every permission before changing anything (including deletes).
      for (final entry in change.after.entries) {
        final roster = entry.value ?? saved[entry.key];
        if (roster == null) continue;
        if (entry.value == null) {
          roster.isEvent ? _requireEventRosterEditor(roster.forEvent!.group) : _requireRosterEditor(roster.type);
        } else {
          _requireRosterWrite(roster);
        }
      }
      for (final entry in change.after.entries) {
        if (entry.value == null) {
          saved.remove(entry.key);
        } else {
          saved[entry.key] = entry.value!.copyWith(saved: true);
        }
      }
      _plan(change);
      if (staffOrder case final order?) _b.staffOrders[churchId]![order.serviceType] = order.after;
    });
  }

  @override
  Future<void> compareAndSetLedDuties(RosterChange change) async {
    if (change.staffOrder != null) throw ArgumentError('only rosters');
    final uid = _uid;
    await _b.write(() {
      // As functions/src/ledDuties.ts: compared first, then only the duties
      // the caller's 事工 lead.
      if (_uid != uid) throw const CloudException(CloudErrorCode.permissionDenied);
      final me = _b.requireMember(churchId);
      final saved = _b.rosters[churchId]!;
      for (final id in change.before.keys) {
        if (!change.expects(id, saved[id])) throw const CloudException(CloudErrorCode.conflict);
      }
      for (final entry in change.after.entries) {
        final next = entry.value;
        final was = change.before[entry.key];
        final day = next ?? was;
        if (day == null || (saved[entry.key]?.forEvent?.cancelled ?? false)) {
          throw const CloudException(CloudErrorCode.permissionDenied);
        }
        final roles = me.ledDuties(day.isEvent ? null : day.type);
        if (!mayChangeLedDuties(roles, was, next)) throw const CloudException(CloudErrorCode.permissionDenied);
        if (was == null && !day.isEvent && !_b.services[churchId]!.ids.contains(day.type)) {
          throw const CloudException(CloudErrorCode.unknown);
        }
      }
      _plan(change);
      for (final entry in change.after.entries) {
        saved[entry.key] = entry.value!.copyWith(saved: true);
      }
    });
  }

  /// Keeps whom a change made in 安排服事 puts on or takes off, but the
  /// editor, for 通知同工. A change told at once, their own, or on and off
  /// again leaves nothing waiting once they have what they had before.
  void _plan(RosterChange change) {
    final waiting = _b.planned[churchId] ??= {};
    for (final MapEntry(key: id, value: now) in change.after.entries) {
      final was = change.before[id];
      final day = now ?? was;
      if (day == null || day.isEvent) continue;
      final uids = {
        for (final r in [?was, ?now])
          for (final d in r.duties) ...d.uids.values,
      };
      for (final uid in uids) {
        // As functions/src/rosterChange.ts planRosterChange: one of the 同工
        // without an account yet has no member to tell.
        if (!_b.members[churchId]!.containsKey(uid)) continue;
        final before = was?.dutiesOf(uid: uid) ?? const <String>[];
        final after = now?.dutiesOf(uid: uid) ?? const <String>[];
        if (setEquals(before.toSet(), after.toSet())) continue;
        final key = '$id/$uid';
        final entry = waiting[key];
        final roles = plannedAfter(
          entry?.roles,
          before: before,
          after: after,
          told: !change.via.waitsForNotice || uid == _uid,
        );
        if (roles == null) {
          waiting.remove(key);
        } else {
          waiting[key] = (service: entry?.service ?? day.type, roles: roles);
        }
      }
    }
  }

  @override
  Stream<bool> plannedNews(String serviceType) => _b.watch(() {
    _requireRosterEditors();
    return _b.planned[churchId]?.values.any((p) => p.service == serviceType) ?? false;
  });

  Future<PlannedNotice> notifyPlanned(String serviceType) async {
    var people = 0;
    await _b.write(() {
      final me = _b.requireMember(churchId);
      if (!_b.services[churchId]!.ids.contains(serviceType) || !me.arranges(serviceType).any) {
        throw const CloudException(CloudErrorCode.permissionDenied);
      }
      final waiting = _b.planned[churchId] ?? {};
      final told = [
        for (final MapEntry(:key, :value) in waiting.entries)
          if (value.service == serviceType) key,
      ];
      people = {for (final key in told) key.split('/').last}.length;
      told.forEach(waiting.remove);
    });
    return (people: people, later: false);
  }
}
