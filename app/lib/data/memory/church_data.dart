part of 'memory_backend.dart';

class MemoryChurchData extends _MemoryChurchBase
    with
        _MemorySmallGroups,
        _MemoryRosters,
        _MemoryUnavailable,
        _MemorySwaps,
        _MemoryServiceSettings,
        _MemoryGroupMembers,
        _MemoryInvites,
        _MemoryChurch,
        _MemoryClaim {
  MemoryChurchData(super._b, super.churchId);

  @override
  late final CalendarData calendar = MemoryCalendarData(this);

  @override
  late final ChurchLinkData churchLink = _MemoryChurchLink(this);

  @override
  late final WebhookData webhook = _MemoryWebhook(this);

  @override
  late final PhotoData photos = _MemoryPhotos(this);

  @override
  late final AttendanceData attendance = _MemoryAttendance(this);

  @override
  late final RosterNoteData rosterNotes = _MemoryRosterNotes(this);

  @override
  late final ReadOnceData readOnce = _MemoryReadOnce(this);
}

/// What every part of [MemoryChurchData] reads: the backend, who is asking,
/// and the checks the rules and functions/src/access.ts make.
abstract class _MemoryChurchBase implements ChurchData {
  _MemoryChurchBase(this._b, this.churchId);

  final MemoryBackend _b;

  @override
  final String churchId;

  String? get _uid => _b.auth.currentUser?.uid;
  Member? get _me => _b.memberOf(churchId, _uid);

  void _requireMember() => _b.requireMember(churchId);

  void _requireAdmin() => _b.requireAdmin(churchId);

  /// Admins and roster editors: the member list and pending members.
  /// The member list: admins, 行政 and whoever leads something
  /// (firestore.rules readsMembers).
  void _requireRosterEditors() {
    if (!_b.requireMember(churchId).readsMembers) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  /// A service the church has configured, which the member may edit.
  void _requireRosterEditor(String type) {
    final me = _b.requireMember(churchId);
    if (!me.editsRostersOf(type, _b.services[churchId]!.ids)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  /// Events' rosters, which are in no service.
  void _requireEventRosterEditor([String? group]) {
    if (!_b.requireMember(churchId).canEditEventRoster(group)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  /// Writing [r] over what is saved at its ID, as firestore.rules allow: a
  /// service's day by whoever arranges it, an event's roster by 行政, admins
  /// and its group's 負責人 (the saved group; a new one's as given), and
  /// only as [appMayWriteRoster] lets the app.
  void _requireRosterWrite(Roster r) {
    final saved = _b.rosters[churchId]![r.id];
    if (!appMayWriteRoster(saved, r)) throw const CloudException(CloudErrorCode.permissionDenied);
    if (!r.isEvent) return _requireRosterEditor(r.type);
    _requireEventRosterEditor((saved ?? r).forEvent!.group);
  }

  @override
  Stream<Church?> church() => _b.watch(() {
    if (_b.memberOf(churchId, _uid) == null) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    return _b.churches[churchId];
  });

  @override
  Stream<Member?> member(String uid) => _b.watch(() => _b.memberOf(churchId, uid));

  @override
  Stream<List<Member>> members() => _b.watch(() {
    _requireRosterEditors();
    return _b.members[churchId]!.values.toList();
  }, equals: _sameList);

  @override
  Stream<ServiceSettings> services() => _b.watch(() {
    _requireMember();
    return _b.services[churchId]!;
  });

  @override
  Stream<MinistrySettings> ministries() => _b.watch(() {
    _requireMember();
    return _b.ministries[churchId] ?? const MinistrySettings();
  });

  /// The group [key] names, a 小組 with its service, for who may see it.
  ChurchGroup? _group(String key) => switch (ChurchGroup.parse(key)) {
    SmallGroup(:final id) => _b.smallGroups[churchId]?[id]?.group ?? SmallGroup(id),
    final g => g,
  };

  void _requireAttendanceWriter(String key) {
    final group = _group(key);
    if (group == null || !_b.requireMember(churchId).writesAttendance(group)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  /// As [_requireAttendanceWriter], or one the group asked to (fillers).
  void _requireAttendanceFiller(String key) {
    final group = _group(key);
    final fillers = _b.attendance[churchId]?[key]?.fillers ?? const <String>[];
    if (group == null || !_b.requireMember(churchId).fillsAttendance(group, fillers)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  /// Who sees everyone's 不能服事的日子 (firestore.rules arrangesRosters).
  void _requireArrangesRosters() {
    if (!_b.requireMember(churchId).arrangesRosters) throw const CloudException(CloudErrorCode.permissionDenied);
  }

  // What the Cloud Functions do for the church: refused as
  // functions/src/access.ts refuses ([MemoryBackend.functionAccess]).

  Member _functionAdmin({bool allowClosed = false}) =>
      _b.functionAccess(churchId, allowed: (me) => me.isAdmin, allowClosed: allowClosed)!;

  /// As calendarWrite: an event of group [before] (null: none yet) becoming
  /// [after] (null: deleted), judged by the event as the calendar has it
  /// (Member.mayWriteEvent).
  void _requireEventWrite(String? Function() before, String? after) {
    _b.functionAccess(
      churchId,
      // Admins and 行政 write any event: whose it was is looked up for
      // others, and anyone who leads nothing is refused before that.
      allowed: (me) => me.inGroup(Group.calendarEditors) || (me.makesEvents && me.mayWriteEvent(before(), after)),
    );
    if (after != null && after.isNotEmpty && ChurchGroup.parse(after) == null) {
      throw const CloudException(CloudErrorCode.unknown);
    }
  }

  /// As Google: one of its own events (CalendarEvent.googleOnly) is
  /// neither changed nor deleted here.
  void _requireChangeable(String? id) {
    if ((_b.calendarEvents[churchId] ?? const <CalendarEvent>[]).any((e) => e.id == id && e.googleOnly)) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.googleOnly);
    }
  }

  /// Undoing a delete takes the cancelled roster of [restoreRosterOf]
  /// along: for a 負責人, only one of an event they could have deleted.
  void _requireRestore(String? restoreRosterOf) {
    if (restoreRosterOf == null) return;
    final from = _b.rosters[churchId]![Roster.idForEvent(restoreRosterOf)];
    if (from != null) _requireEventWrite(() => from.forEvent!.group ?? '', null);
  }

  /// Event [id]'s group as the calendar has it now, '' the church's.
  String? _groupNow(String? id) {
    if (id == null) return null;
    for (final e in _b.calendarEvents[churchId] ?? const <CalendarEvent>[]) {
      if (e.id == id) return e.group ?? '';
    }
    throw const CloudException(CloudErrorCode.notFound);
  }

  /// As the backend's photo calls (access.ts `arranges`): someone who
  /// arranges any of a service the church has.
  void _rosterEditorOf(String serviceType) => _b.functionAccess(
    churchId,
    allowed: (me) =>
        _b.services[churchId]!.ids.contains(serviceType) &&
        me.arranges((_b.ministries[churchId] ?? const MinistrySettings()).ministries, serviceType).any,
  );
}
