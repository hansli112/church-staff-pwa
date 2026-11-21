part of 'memory_backend.dart';

/// [ReadOnceData] of a [MemoryChurchData].
class _MemoryReadOnce implements ReadOnceData {
  _MemoryReadOnce(this._c);

  final MemoryChurchData _c;

  @override
  Future<List<Member>> members() async {
    _c._requireRosterEditors();
    return _c._b.members[_c.churchId]!.values.toList();
  }

  @override
  Future<List<PendingMember>> pendingMembers() async {
    _c._requireRosterEditors();
    return (_c._b.pendingMembers[_c.churchId] ?? const {}).values.toList();
  }

  @override
  Future<List<Roster>> rosters() async {
    _c._requireMember();
    return _c._b.rosters[_c.churchId]!.values.toList();
  }

  @override
  Future<Map<String, StaffOrder>> staffOrders() async {
    _c._requireMember();
    return Map.of(_c._b.staffOrders[_c.churchId]!);
  }
}

class _Platform implements PlatformData {
  _Platform(this._b);
  final MemoryBackend _b;

  @override
  Stream<Funding?> funding() => _b.watch(() => _b.funding);

  @override
  Stream<MinimumBuilds> minimumBuilds() {
    _b.minimumBuildsReads++;
    return _b.watch(() => _b.minimumBuilds);
  }
}
