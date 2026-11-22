part of 'memory_backend.dart';

/// [MemoryChurchData] as functions/src/invites.ts and joinRequests.ts do
/// it.
mixin _MemoryInvites on _MemoryChurchBase implements JoiningData {
  @override
  Stream<List<JoinRequest>> requests() => _b.watch(() {
    _requireAdmin();
    return (_b.joinRequests[churchId] ?? const <String, JoinRequest>{}).values.toList();
  }, equals: _sameList);

  /// As answerJoinRequest: a no marks the request; a yes adds them as an
  /// invite would, unless the church takes no requests or it is not
  /// waiting.
  Future<void> answerJoinRequest(String uid, {required bool allow}) async {
    _functionAdmin();
    _b.requireNetwork();
    final requests = _b.joinRequests[churchId] ?? {};
    final r = requests[uid];
    if (!allow) {
      if (r?.stateAt(_b.clock()) == JoinRequestState.pending) {
        requests[uid] = JoinRequest(
          uid: r!.uid,
          name: r.name,
          email: r.email,
          note: r.note,
          createdAt: r.createdAt,
          rejectedAt: _b.clock(),
        );
      }
      _b.notify();
      return;
    }
    if (!_b.churches[churchId]!.takesJoinRequests) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.requestsClosed);
    }
    if (_b.memberOf(churchId, uid) == null) {
      if (r?.stateAt(_b.clock()) != JoinRequestState.pending) {
        throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.requestGone);
      }
      // Asked with a verified email that moved data waits for: joins as it.
      if (!_takeWaiting(_b, churchId, uid, r!.email)) {
        _b.addMember(churchId, Member(uid: uid, name: r.name, email: r.email, joinedAt: _b.clock()));
      }
    }
    requests.remove(uid);
    _b.notify();
  }

  @override
  Future<void> setTakesRequests(bool on) async {
    _requireAdmin();
    await _b.write(() => _b.churches[churchId] = _b.churches[churchId]!.copyWith(takesJoinRequests: on));
  }

  @override
  Stream<List<Invite>> invites() => _b.watch(() {
    _requireAdmin();
    return _b.invites.values.where((i) => i.churchId == churchId).toList()
      ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
  }, equals: _sameList);

  @override
  Future<Invite> createInvite({required Duration validFor, List<String> zoneTypes = const []}) async {
    _requireAdmin();
    if (validFor >= const Duration(days: Limits.inviteDays) || zoneTypes.length > Limits.services) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    final code = _randomCode();
    final invite = Invite(
      code: code,
      churchId: churchId,
      churchName: _b.churches[churchId]!.name,
      expiresAt: _b.clock().add(validFor),
      createdAt: _b.clock(),
      zoneTypes: zoneTypes,
    );
    await _b.write(() => _b.invites[code] = invite);
    return invite;
  }

  @override
  Future<void> revokeInvite(String code) async {
    _requireAdmin();
    final invite = _b.invites[code]!;
    await _b.write(
      () => _b.invites[code] = Invite(
        code: code,
        churchId: invite.churchId,
        churchName: invite.churchName,
        expiresAt: invite.expiresAt,
        createdAt: invite.createdAt,
        zoneTypes: invite.zoneTypes,
        revoked: true,
      ),
    );
  }
}
