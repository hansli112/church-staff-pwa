part of 'memory_backend.dart';

/// [MemoryChurchData] as functions/src/swaps.ts does it.
mixin _MemorySwaps on _MemoryChurchBase implements SwapData {
  /// [r] as the backend keeps it: an open one the rosters no longer bear,
  /// or whose day went by, is void (functions/src/swaps.ts voidStaleSwaps).
  SwapRequest _current(SwapRequest r) {
    if (!r.isOpen) return r;
    final rosters = _b.rosters[churchId]!;
    final today = _b.churches[churchId]!.timeZone.today(_b.clock());
    final holds =
        !r.day.isBefore(today) &&
        swapStillHolds(r, rosters[r.rosterId], r.toRosterId == null ? null : rosters[r.toRosterId]);
    return holds ? r : r.copyWith(status: SwapStatus.voided);
  }

  @override
  Stream<List<SwapRequest>> mineOpen() => _b.watch(() {
    _requireMember();
    return [
      for (final r in _b.swapRequests[churchId]?.values ?? const <SwapRequest>[])
        if (r.from == _uid && _current(r).isOpen) r,
    ];
  }, equals: listEquals);

  @override
  Stream<List<SwapRequest>> toMe() => _b.watch(() {
    _requireMember();
    return [
      for (final r in _b.swapRequests[churchId]?.values ?? const <SwapRequest>[])
        if (r.canAnswer(_uid ?? '') && _current(r).isOpen) r,
    ]..sort((a, b) => a.day.compareTo(b.day));
  }, equals: listEquals);

  @override
  Stream<SwapRequest?> request(String id) => _b.watch(() {
    _requireMember();
    final r = _b.swapRequests[churchId]?[id];
    if (r != null && r.from != _uid && !r.canAnswer(_uid ?? '')) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    return r == null ? null : _current(r);
  });

  /// As functions/src/swaps.ts asker: my duty on a service's day from
  /// today on, with no request of mine open for it.
  ({Member me, Roster saved}) _asking(Roster roster, String duty) {
    final me = _b.requireMember(churchId);
    final saved = _b.rosters[churchId]![roster.id];
    final today = _b.churches[churchId]!.timeZone.today(_b.clock());
    if (roster.isEvent || saved == null || saved.day.isBefore(today) || !isOnDuty(saved, duty, me.uid)) {
      throw const CloudException(CloudErrorCode.unknown);
    }
    final open = _b.swapRequests[churchId]?.values ?? const <SwapRequest>[];
    if (open.any((r) => r.isOpen && r.from == me.uid && r.rosterId == roster.id && r.duty == duty)) {
      throw const CloudException(CloudErrorCode.unknown);
    }
    return (me: me, saved: saved);
  }

  String _nameOn(Roster roster, String duty, String uid) =>
      roster.duties.firstWhere((d) => d.role == duty).uids.entries.firstWhere((e) => e.value == uid).key;

  Future<int> askCover(Roster roster, String duty) async {
    var asked = 0;
    await _b.write(() {
      final (:me, :saved) = _asking(roster, duty);
      final who = coverAsked(
        _b.members[churchId]!.values,
        saved,
        duty,
        me.uid,
        unavailable: _b.unavailable[churchId] ?? const {},
      );
      final id = 'swap${++_b._swapIds}';
      (_b.swapRequests[churchId] ??= {})[id] = SwapRequest(
        id: id,
        kind: SwapKind.cover,
        serviceId: saved.type,
        day: saved.day,
        duty: duty,
        from: me.uid,
        fromName: _nameOn(saved, duty, me.uid),
        asked: who,
      );
      asked = who.length;
    });
    return asked;
  }

  Future<void> askSwap(Roster roster, String duty, Roster other, String uid) async {
    await _b.write(() {
      final (:me, :saved) = _asking(roster, duty);
      final theirs = _b.rosters[churchId]![other.id];
      final today = _b.churches[churchId]!.timeZone.today(_b.clock());
      if (theirs == null || theirs.type != saved.type || !theirs.day.isAfter(today) || theirs.id == saved.id) {
        throw const CloudException(CloudErrorCode.unknown);
      }
      final id = 'swap${++_b._swapIds}';
      final request = SwapRequest(
        id: id,
        kind: SwapKind.swap,
        serviceId: saved.type,
        day: saved.day,
        duty: duty,
        from: me.uid,
        fromName: _nameOn(saved, duty, me.uid),
        to: uid,
        toName: isOnDuty(theirs, duty, uid) ? _nameOn(theirs, duty, uid) : null,
        toDay: theirs.day,
      );
      if (!swapStillHolds(request, saved, theirs)) throw const CloudException(CloudErrorCode.unknown);
      // As functions/src/swaps.ts askSwap: one of the 同工 without an
      // account could never answer.
      if (!_b.members[churchId]!.containsKey(uid)) throw const CloudException(CloudErrorCode.notFound);
      (_b.swapRequests[churchId] ??= {})[id] = request;
    });
  }

  /// Request [id] of this church; [CloudReason.swapClosed] unless it is open.
  SwapRequest _openRequest(String id) {
    final r = _b.swapRequests[churchId]?[id];
    if (r == null) throw const CloudException(CloudErrorCode.notFound);
    if (!_current(r).isOpen) throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.swapClosed);
    return r;
  }

  Future<void> answerSwap(String id, {required bool yes}) async {
    await _b.write(() {
      final me = _b.requireMember(churchId);
      final r = _b.swapRequests[churchId]?[id];
      if (r == null) throw const CloudException(CloudErrorCode.notFound);
      if (!r.canAnswer(me.uid)) throw const CloudException(CloudErrorCode.permissionDenied);
      _openRequest(id);
      final requests = _b.swapRequests[churchId]!;
      if (!yes) {
        requests[id] = r.kind == SwapKind.cover
            ? r.copyWith(passed: [...r.passed, me.uid])
            : r.copyWith(status: SwapStatus.declined);
        return;
      }
      final rosters = _b.rosters[churchId]!;
      final roster = rosters[r.rosterId];
      final other = r.toRosterId == null ? null : rosters[r.toRosterId];
      final today = _b.churches[churchId]!.timeZone.today(_b.clock());
      if (r.day.isBefore(today) || !swapStillHolds(r, roster, other)) {
        throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.swapClosed);
      }
      final taker = r.kind == SwapKind.cover ? me.name : r.toName!;
      // As functions/src/swaps.ts answerSwap: still on the list, free that
      // day, not on it already, and no one else of that name there.
      if (r.kind == SwapKind.cover &&
          (!me.serves(r.serviceId, r.duty) ||
              _b.unavailable[churchId]?[me.uid]?.on(r.day) != null ||
              taker.isEmpty ||
              isOnDuty(roster, r.duty, me.uid) ||
              roster!.duties.firstWhere((d) => d.role == r.duty).people.contains(taker))) {
        throw const CloudException(CloudErrorCode.unknown);
      }
      rosters[r.rosterId] = replacedOnDuty(roster!, r.duty, r.from, me.uid, taker);
      if (other != null) rosters[other.id] = replacedOnDuty(other, r.duty, me.uid, r.from, r.fromName);
      requests[id] = r.copyWith(status: SwapStatus.taken, taker: me.uid, takerName: taker);
      _b.swapTakenAt[id] = _b.clock();
    });
  }

  Future<void> undoSwap(String id) async {
    await _b.write(() {
      final me = _b.requireMember(churchId);
      final r = _b.swapRequests[churchId]?[id];
      if (r == null) throw const CloudException(CloudErrorCode.notFound);
      if (r.taker != me.uid) throw const CloudException(CloudErrorCode.permissionDenied);
      final takenAt = _b.swapTakenAt[id];
      if (r.status != SwapStatus.taken || takenAt == null || _b.clock().difference(takenAt) > swapUndoWindow) {
        throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.swapClosed);
      }
      final rosters = _b.rosters[churchId]!;
      final roster = rosters[r.rosterId];
      final other = r.toRosterId == null ? null : rosters[r.toRosterId];
      if (!swapAsTaken(r, roster, other)) throw const CloudException(CloudErrorCode.conflict);
      rosters[r.rosterId] = replacedOnDuty(roster!, r.duty, me.uid, r.from, r.fromName);
      if (other != null) rosters[other.id] = replacedOnDuty(other, r.duty, r.from, me.uid, r.toName!);
      // 請人代 opens again, without who gave it back; 交換 ends as if they
      // had said 不方便.
      _b.swapRequests[churchId]![id] = r.kind == SwapKind.cover
          ? r.reopened.copyWith(passed: [...r.passed, me.uid])
          : r.reopened.copyWith(status: SwapStatus.declined);
    });
  }

  Future<void> withdrawSwap(String id) async {
    await _b.write(() {
      final me = _b.requireMember(churchId);
      final r = _b.swapRequests[churchId]?[id];
      if (r == null) throw const CloudException(CloudErrorCode.notFound);
      if (r.from != me.uid) throw const CloudException(CloudErrorCode.permissionDenied);
      _b.swapRequests[churchId]![id] = _openRequest(id).copyWith(status: SwapStatus.withdrawn);
    });
  }
}
