part of 'memory_backend.dart';

class MemoryCloud implements CloudApi {
  MemoryCloud(this._b);

  final MemoryBackend _b;

  final loggedErrors = <String>[];
  final stats = <DailyStats>[];

  @override
  Future<String> createChurch(
    String name, {
    ChurchTimeZone timeZone = ChurchTimeZone.fallback,
    AppLanguage? language,
  }) async {
    _b.requireNetwork();
    final user = _b.auth.currentUser;
    if (user == null || !user.verified) {
      throw const CloudException(CloudErrorCode.unverifiedEmail);
    }
    name = _text(name, TextLimits.churchName);
    final cid = _b.addChurch(name, timeZone: timeZone);
    // As the Cloud Function: the language asked for, else the one shown last.
    language ??= AppLanguage.fromTag(_b.users[user.uid]?.appLocale) ?? AppLanguage.zhHant;
    _b.setServices(cid, defaultServices[language]!);
    _b.addMember(
      cid,
      Member(
        uid: user.uid,
        name: _b.users[user.uid]?.name ?? user.displayName ?? '',
        email: user.email,
        role: Role.admin,
        joinedAt: _b.clock(),
      ),
    );
    return cid;
  }

  Invite _invite(String code) {
    final invite = _b.invites[code.trim().toUpperCase()];
    if (invite == null || invite.revoked) {
      throw const CloudException(CloudErrorCode.inviteInvalid);
    }
    if (!invite.usableAt(_b.clock())) {
      throw const CloudException(CloudErrorCode.inviteExpired);
    }
    if (!(_b.churches[invite.churchId]?.isActive ?? false)) {
      throw const CloudException(CloudErrorCode.inviteInvalid);
    }
    return invite;
  }

  @override
  Future<Invite> previewInvite(String code) async {
    await _b.invitePreviewHeld?.future;
    return _invite(code);
  }

  @override
  Future<String> invitedChurchName(String code) async => _invite(code).churchName;

  @override
  Future<String> redeemInvite(String code) async {
    _b.requireNetwork();
    final user = _b.auth.currentUser;
    if (user == null) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    final invite = _invite(code);
    final cid = invite.churchId;
    final waiting = user.claimEmails.contains(user.email.trim().toLowerCase());
    if (_b.memberOf(cid, user.uid) == null && !(waiting && _takeWaiting(_b, cid, user.uid, user.email))) {
      // The invite's 牧區 the church still has, each once (redeemInvite).
      final have = {for (final s in _b.services[cid]?.services ?? const <Service>[]) s.id};
      _b.addMember(
        cid,
        Member(
          uid: user.uid,
          name: _b.users[user.uid]?.name ?? user.displayName ?? '',
          email: user.email,
          joinedAt: _b.clock(),
          zones: [
            for (final t in {...invite.zoneTypes})
              if (have.contains(t)) Zone(serviceType: t),
          ],
        ),
      );
    }
    return cid;
  }

  /// Churches where [uid] is the only admin, not counting deleted ones.
  List<Church> soleAdminChurches(String uid) => [
    for (final entry in _b.members.entries)
      if (entry.value[uid]?.isAdmin ?? false)
        if (entry.value.values.where((m) => m.isAdmin).length == 1)
          if (_b.churches[entry.key]!.status != ChurchStatus.deleted) _b.churches[entry.key]!,
  ];

  @override
  Future<void> deleteAccount() async {
    _b.requireNetwork();
    final uid = _b.auth.currentUser?.uid;
    if (uid == null) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    // Those others are in must be handed over; those no one else is in go
    // with the account.
    final sole = soleAdminChurches(uid);
    final blocking = [
      for (final c in sole)
        if (_b.members[c.id]!.length > 1) c,
    ];
    if (blocking.isNotEmpty) {
      throw CloudException(CloudErrorCode.lastAdmin, churches: [for (final c in blocking) c.name]);
    }
    for (final c in sole) {
      if (c.status == ChurchStatus.active) {
        _b.churches[c.id] = _deleted(c, _b.clock());
      }
    }
    for (final m in _b.members.values) {
      m.remove(uid);
    }
    for (final r in _b.joinRequests.values) {
      r.remove(uid);
    }
    _b.users.remove(uid);
    _b.notifications.remove(uid);
    _b.notify();
    _b.auth.deleteCurrent();
  }

  @override
  Future<String> uploadMoveFile(List<int> bytes) async {
    _b.requireNetwork();
    final uid = _b.auth.currentUser?.uid;
    if (uid == null) throw const CloudException(CloudErrorCode.permissionDenied);
    final path = 'moves/$uid/${_b.moveFiles.length + 1}.json';
    _b.moveFiles[path] = bytes;
    return path;
  }

  /// The scripted [MemoryBackend.moveAnswer] for an uploaded file.
  MovePreview _readMove(String path) {
    if (!_b.moveFiles.containsKey(path)) throw const CloudException(CloudErrorCode.notFound);
    return switch (_b.moveAnswer) {
      final MovePreview preview => preview,
      final Object error => throw error,
    };
  }

  @override
  Future<MovePreview> movePreview(String path) async => _readMove(path);

  /// Only member metadata is read here; validation, counts and the rest of
  /// the import remain the scripted answer. Legacy names are converted once
  /// at this boundary, never by the runtime member codec. Tokens are not read.
  List<PendingMember> _movePeople(String path, MovePreview preview) {
    final Object? raw;
    try {
      raw = jsonDecode(utf8.decode(_b.moveFiles[path]!));
    } on FormatException {
      throw const CloudException(CloudErrorCode.moveInvalid);
    }
    if (raw is! Map) throw const CloudException(CloudErrorCode.moveInvalid);
    final users = raw['users'];
    final byId = {
      if (users is List)
        for (final user in users)
          if (user is Map && user['id'] is String && user['data'] is Map) user['id'] as String: user['data'] as Map,
    };
    return [
      for (final person in preview.people)
        movedMember(id: person.id, name: person.name, email: person.email, source: byId[person.id]),
    ];
  }

  /// The church is made as [createChurch] makes it; everyone in the
  /// scripted preview but [me] becomes a pending member.
  @override
  Future<String> moveCommit(
    String path, {
    required String churchName,
    String? me,
    ChurchTimeZone timeZone = ChurchTimeZone.fallback,
    AppLanguage? language,
  }) async {
    // [MemoryBackend.failNextWrite]: the request fails before anything is made.
    final failure = _b.failNextWrite;
    if (failure != null) {
      _b.failNextWrite = null;
      throw failure;
    }
    final preview = _readMove(path);
    final people = _movePeople(path, preview);
    final cid = await createChurch(churchName, timeZone: timeZone);
    final uid = _b.auth.currentUser!.uid;
    for (final person in people) {
      if (person.id == me) {
        final admin = _b.members[cid]![uid]!;
        _b.members[cid]![uid] = _absorb(admin.copyWith(name: person.name), person);
      }
    }
    _b.pendingMembers[cid] = {
      for (final person in people)
        if (person.id != me) person.id: person,
    };
    _b.moveFiles.remove(path);
    _b.notify();
    return cid;
  }

  @override
  Future<List<PendingClaim>> pendingClaims() async {
    final user = _b.auth.currentUser;
    final emails = user?.claimEmails ?? const [];
    return [
      for (final MapEntry(key: cid, value: pending) in _b.pendingMembers.entries)
        if (_b.churches[cid]?.isActive ?? false)
          for (final p in pending.values)
            if (emails.contains(p.email.trim().toLowerCase()) && !(_b.claiming[cid]?.contains(p.id) ?? false))
              PendingClaim(
                churchId: cid,
                churchName: _b.churches[cid]!.name,
                pendingId: p.id,
                name: p.name,
                serves: _servesOf(cid, p),
              ),
      for (final MapEntry(key: cid, value: pending) in _b.pendingMembers.entries)
        if ((_b.churches[cid]?.isActive ?? false) && user != null)
          if (_b.members[cid]?[user.uid] case final me?)
            if (_unclaimedNamed(pending.values, me.name) case final p?)
              PendingClaim(
                churchId: cid,
                churchName: _b.churches[cid]!.name,
                pendingId: p.id,
                name: p.name,
                byName: true,
                serves: _servesOf(cid, p),
              ),
    ];
  }

  /// A few of [p]'s duties, as functions/src/claim.ts finds them.
  List<ClaimServe> _servesOf(String cid, PendingMember p) => _servesOfPending(_b, cid, p);

  /// The one pending member with no email named [name], if just one.
  PendingMember? _unclaimedNamed(Iterable<PendingMember> pending, String name) => switch ([
    for (final p in pending)
      if (p.email.isEmpty && name.trim().isNotEmpty && p.name.trim() == name.trim()) p,
  ]) {
    [final only] => only,
    _ => null,
  };

  @override
  Future<String> claimPending(String churchId, String pendingId) async {
    final user = _b.auth.currentUser;
    if (user == null) throw const CloudException(CloudErrorCode.permissionDenied);
    final emails = user.claimEmails;
    final existing = _b.functionAccess(churchId, anyone: true);
    final p = _b.pendingMembers[churchId]?[pendingId];
    if (p == null) {
      // Claimed already (a double tap, a retry): fine if it was by them.
      if (existing != null) return churchId;
      throw const CloudException(CloudErrorCode.notFound);
    }
    final byName =
        existing != null && p.email.isEmpty && p.name.trim().isNotEmpty && p.name.trim() == existing.name.trim();
    if (!byName && !emails.contains(p.email.trim().toLowerCase())) {
      throw CloudException(emails.isEmpty ? CloudErrorCode.unverifiedEmail : CloudErrorCode.permissionDenied);
    }
    _b.members[churchId]![user.uid] = existing != null
        ? _absorb(existing, p)
        : _withClaimedLeads(
            Member(
              uid: user.uid,
              name: p.name,
              email: user.email,
              role: p.role,
              zones: p.zones,
              smallGroups: p.smallGroups,
              mutedNotifications: p.mutedNotifications,
              joinedAt: _b.clock(),
            ),
            p,
          );
    if (_b.claimRepointHeld case final held?) {
      (_b.claiming[churchId] ??= {}).add(pendingId);
      _b.notify();
      await held.future;
      _b.claiming[churchId]!.remove(pendingId);
    }
    _settlePending(_b, churchId, pendingId, user.uid);
    _b.notify();
    return churchId;
  }

  @override
  Future<ChurchPreview> churchPreview(String churchId) async {
    final c = _b.churches[churchId];
    if (c == null || !c.isActive) throw const CloudException(CloudErrorCode.notFound);
    final uid = _b.auth.currentUser?.uid;
    return ChurchPreview(
      id: c.id,
      name: c.name,
      logoUrl: c.logoUrl,
      takesJoinRequests: c.takesJoinRequests,
      joinRequest: uid == null ? null : _b.joinRequestState(churchId, uid),
    );
  }

  @override
  Future<void> requestToJoin(String churchId, {String note = ''}) async {
    _b.requireNetwork();
    final user = _b.auth.currentUser;
    if (user == null) throw const CloudException(CloudErrorCode.permissionDenied);
    note = note.trim();
    if (!withinTextLimit(note, TextLimits.joinNote)) throw const CloudException(CloudErrorCode.unknown);
    if (!user.verified) throw const CloudException(CloudErrorCode.unverifiedEmail);
    final c = _b.churches[churchId];
    if (c == null || !c.isActive) throw const CloudException(CloudErrorCode.notFound);
    if (_b.memberOf(churchId, user.uid) != null) return;
    if (!c.takesJoinRequests) throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.requestsClosed);
    if (_b.joinRequestState(churchId, user.uid) == JoinRequestState.pending) return;
    (_b.joinRequests[churchId] ??= {})[user.uid] = JoinRequest(
      uid: user.uid,
      name: _b.users[user.uid]?.name ?? user.displayName ?? '',
      email: user.email,
      note: note,
      createdAt: _b.clock(),
    );
    _b.notify();
  }

  @override
  Future<void> withdrawJoinRequest(String churchId) async {
    _b.requireNetwork();
    final uid = _b.auth.currentUser?.uid;
    if (uid == null) throw const CloudException(CloudErrorCode.permissionDenied);
    _b.joinRequests[churchId]?.remove(uid);
    _b.notify();
  }

  void _requireOperator() {
    _b.requireNetwork();
    if (!_b.auth.operators.contains(_b.auth.currentUser?.uid)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  @override
  Future<List<ChurchSummary>> adminSearchChurches(String query) async {
    _requireOperator();
    _b.adminSearches.add(query);
    return [
      for (final c in _b.churches.values)
        if (matchesSearch(c.name, query) || c.id == query.trim()) _summary(c),
    ];
  }

  /// Newest first: the last added.
  @override
  Future<ChurchPage> adminChurches({String? after}) async {
    _requireOperator();
    final listed = [
      for (final c in _b.churches.values.toList().reversed)
        if (c.status != ChurchStatus.deleted) c,
    ];
    final from = after == null ? 0 : listed.indexWhere((c) => c.id == after) + 1;
    if (after != null && from == 0) throw const CloudException(CloudErrorCode.notFound);
    final shown = listed.skip(from).take(adminChurchPage).toList();
    return ChurchPage(
      churches: [for (final c in shown) _summary(c)],
      total: listed.length,
      next: from + shown.length < listed.length ? shown.last.id : null,
    );
  }

  ChurchSummary _summary(Church c) => ChurchSummary(
    id: c.id,
    name: c.name,
    status: c.status,
    memberCount: _b.members[c.id]!.length,
    admins: [
      for (final m in _b.members[c.id]!.values)
        if (m.isAdmin) m,
    ],
  );

  @override
  Future<void> adminRenameChurch(String churchId, String name) async {
    _requireOperator();
    name = _text(name, TextLimits.churchName);
    _b.churches[churchId] = _b.churches[churchId]!.copyWith(name: name);
    _b.notify();
  }

  @override
  Future<List<Member>> adminChurchMembers(String churchId) async {
    _requireOperator();
    return _b.members[churchId]!.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<void> adminTransferAdmin(
    String churchId,
    String uid, {
    List<Identity> identities = const [AdminIdentity()],
  }) async {
    _requireOperator();
    await _b.adminChangeHeld?.future;
    final m = _b.memberOf(churchId, uid);
    if (m == null) throw const CloudException(CloudErrorCode.unknown);
    if (identities.isEmpty || identities.any((i) => !i.makesAdmin)) throw const CloudException(CloudErrorCode.unknown);
    _b.members[churchId]![uid] = m.withIdentities([...identities, ...m.identities]);
    _b.notify();
  }

  @override
  Future<List<Identity>> adminRevokeAdmin(String churchId, String uid) async {
    _requireOperator();
    await _b.adminChangeHeld?.future;
    final m = _b.memberOf(churchId, uid);
    if (m == null) throw const CloudException(CloudErrorCode.unknown);
    if (m.isAdmin && !_b.members[churchId]!.values.any((o) => o.uid != uid && o.isAdmin)) {
      throw const CloudException(CloudErrorCode.lastAdmin);
    }
    _b.members[churchId]![uid] = m.withIdentities([
      for (final i in m.identities)
        if (!i.makesAdmin) i,
    ]);
    _b.notify();
    return [
      for (final i in m.identities)
        if (i.makesAdmin) i,
    ];
  }

  @override
  Future<void> adminSetStatus(String churchId, ChurchStatus status) async {
    _requireOperator();
    if (status == ChurchStatus.deleted) throw const CloudException(CloudErrorCode.unknown);
    // A deleted church is its admin's to restore, not the operator's.
    if (_b.churches[churchId]?.status == ChurchStatus.deleted) {
      throw const CloudException(CloudErrorCode.churchClosed);
    }
    _b.churches[churchId] = _b.churches[churchId]!.copyWith(status: status);
    _b.notify();
  }

  @override
  Future<List<DailyStats>> adminStats({int days = 30}) async {
    _requireOperator();
    await _b.backOfficeReadsHeld?.future;
    return stats.take(days).toList();
  }

  @override
  Future<FundingOverview> adminFunding() async {
    _requireOperator();
    await _b.backOfficeReadsHeld?.future;
    return FundingOverview(
      costs: List.of(_b.fundingCosts),
      months: const [],
      funding: _b.funding,
      payments: List.of(_b.fundingPayments),
    );
  }

  @override
  Future<void> adminSetFundingCosts(List<CostItem> items) async {
    _requireOperator();
    for (final item in items) {
      _text(item.name, TextLimits.costName);
    }
    await _b.write(() {
      _b.fundingCosts = List.of(items);
      _b.funding = _b.publishFunding?.call(items) ?? _b.funding;
    });
  }

  @override
  Future<OnlinePayment> adminRefundOnlineSupport(String orderNo, {required bool refunded}) async {
    _requireOperator();
    final no = orderNo.trim();
    final payment = _b.onlinePayments[no];
    if (payment == null) throw const CloudException(CloudErrorCode.notFound);
    final already = refunded && _b.refundedOnline.contains(no);
    if (!already) await _b.write(() => refunded ? _b.refundedOnline.add(no) : _b.refundedOnline.remove(no));
    return (amount: payment.amount, month: payment.month, alreadyRefunded: already);
  }

  @override
  Future<void> logError({
    required String message,
    required String stack,
    String? churchId,
    String? screen,
    String? during,
    String? library,
    bool fatal = false,
    String? agent,
    String? trail,
    String? memory,
  }) async => loggedErrors.add(message);
}
