part of 'memory_backend.dart';

/// [AttendanceData] of a [MemoryChurchData].
class _MemoryAttendance implements AttendanceData {
  _MemoryAttendance(this._c);

  final MemoryChurchData _c;

  @override
  Stream<AttendanceRecord> watch(String key) => _c._b.watch(() {
    final group = _c._group(key);
    final record = _c._b.attendance[_c.churchId]?[key] ?? const AttendanceRecord();
    if (group == null || !_c._b.requireMember(_c.churchId).readsAttendance(group, record.fillers)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    return record;
  });

  @override
  Stream<Set<String>> mine() => _c._b.watch(() {
    final me = _c._b.requireMember(_c.churchId).uid;
    return {
      for (final e in _all.entries)
        if (e.value.fillers.contains(me)) e.key,
    };
  }, equals: setEquals);

  @override
  Future<void> save(String key, Day day, AttendanceDay? value) async {
    _c._requireAttendanceFiller(key);
    _requireValid(value);
    await _c._b.write(() => _setDay(key, day, value));
  }

  void _requireValid(AttendanceDay? value) {
    if (value != null &&
        !value.none &&
        (value.count == null ||
            value.count! < 0 ||
            value.count! > Limits.attendanceCount ||
            !withinTextLimit(value.note, TextLimits.attendanceNote))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  Map<String, AttendanceRecord> get _all => _c._b.attendance.putIfAbsent(_c.churchId, () => {});

  void _setDay(String key, Day day, AttendanceDay? value) {
    final was = _all[key] ?? const AttendanceRecord();
    _all[key] = was.copyWith(days: {...was.days, day: ?value}..removeWhere((d, _) => d == day && value == null));
  }

  @override
  Future<void> saveTogether(String key, Day day, AttendanceDay value) async {
    _c._requireAttendanceFiller(key);
    _requireValid(value);
    final host = _c._group(key);
    final since = _c._b.churches[_c.churchId]!.attendanceSince;
    final others = value.together;
    if (host is! SmallGroup ||
        since == null ||
        others.length > Limits.attendanceTogether ||
        others.toSet().length != others.length ||
        others.contains(key)) {
      throw const CloudException(CloudErrorCode.unknown);
    }
    await _c._b.write(() {
      for (final k in others) {
        final details = switch (_c._group(k)) {
          SmallGroup(:final id) => _c._b.smallGroups[_c.churchId]?[id],
          _ => null,
        };
        final record = _all[k] ?? const AttendanceRecord();
        if (details == null ||
            details.service != host.service ||
            !attendanceDue(details.meets, since: since, pauses: record.pauses, day: day)) {
          throw const CloudException(CloudErrorCode.unknown);
        }
        final had = record.days[day];
        if (had != null && had.withGroup != key) {
          throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.togetherFilled);
        }
      }
      for (final k in (_all[key]?.days[day]?.together ?? const <String>[])) {
        if (!others.contains(k) && _all[k]?.days[day]?.withGroup == key) _setDay(k, day, null);
      }
      _setDay(key, day, value);
      for (final k in others) {
        _setDay(k, day, AttendanceDay.joined(key));
      }
    });
  }

  @override
  Future<void> savePauses(String key, List<AttendancePause> pauses) async {
    _c._requireAttendanceWriter(key);
    if (pauses.length > Limits.attendancePauses) throw const CloudException(CloudErrorCode.permissionDenied);
    await _c._b.write(() => _all[key] = (_all[key] ?? const AttendanceRecord()).copyWith(pauses: pauses));
  }

  @override
  Future<void> saveFillers(String key, List<String> fillers) async {
    _c._requireAttendanceWriter(key);
    if (fillers.length > Limits.attendanceFillers) throw const CloudException(CloudErrorCode.permissionDenied);
    await _c._b.write(() => _all[key] = (_all[key] ?? const AttendanceRecord()).copyWith(fillers: [...fillers]));
  }

  @override
  Future<void> saveTime(String key, MeetingTime? time) async {
    _c._requireAttendanceWriter(key);
    if (_c._group(key) is! ServiceGroup) throw const CloudException(CloudErrorCode.unknown);
    _requireValidTime(time);
    await _c._b.write(
      () => _all[key] = (_all[key] ?? const AttendanceRecord()).copyWith(
        time: () =>
            time == null ? null : MeetingTime(every: time.every, startsOn: time.startsOn, monthWeeks: time.monthWeeks),
      ),
    );
  }

  void _requireValidTime(MeetingTime? time) {
    if (time != null &&
        (!(time.every == 1 || time.every == 2) ||
            time.monthWeeks.length > Limits.monthWeeks ||
            time.monthWeeks.any((w) => w < 1 || w > Limits.monthWeeks))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  Map<String, Gathering> get _gatherings => _c._b.gatherings.putIfAbsent(_c.churchId, () => {});

  @override
  Stream<List<Gathering>> gatherings() => _c._b.watch(() {
    _c._b.requireMember(_c.churchId);
    return [..._gatherings.values]..sort((a, b) => byOrder(a.place, b.place));
  }, equals: listEquals);

  @override
  Future<String> saveGathering(Gathering gathering) async {
    if (!_c._b.requireMember(_c.churchId).overseesAttendance) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    final name = gathering.name.trim();
    if (name.isEmpty || !withinTextLimit(name, TextLimits.profileName)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    _requireValidTime(gathering.time);
    final id = gathering.id.isEmpty ? 'gathering${++_c._b._gatheringIds}' : gathering.id;
    await _c._b.write(
      () => _gatherings[id] = Gathering(id: id, name: name, time: gathering.time, order: _gatherings[id]?.order),
    );
    return id;
  }

  @override
  Future<void> orderGatherings(List<String> ids) async {
    if (!_c._b.requireMember(_c.churchId).overseesAttendance) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    // The rules allow no further place.
    if (ids.length > Limits.ordered) throw const CloudException(CloudErrorCode.permissionDenied);
    if (ids.length != _gatherings.length || !setEquals(ids.toSet(), _gatherings.keys.toSet())) {
      throw const CloudException(CloudErrorCode.conflict);
    }
    await _c._b.write(() {
      for (final (i, id) in ids.indexed) {
        _gatherings[id] = _gatherings[id]!.copyWith(order: () => i);
      }
    });
  }

  @override
  Future<void> deleteGathering(String id) async {
    if (!_c._b.requireMember(_c.churchId).overseesAttendance) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    await _c._b.write(() => _gatherings.remove(id));
  }

  @override
  Future<int> remind(String key, Day day) async {
    final b = _c._b;
    final cid = _c.churchId;
    // Who fills in its 人數: a service's 負責人 and 牧者 too (#95).
    _c._requireAttendanceWriter(key);
    final church = b.churches[cid]!;
    final today = church.timeZone.today(b.clock());
    final since = church.attendanceSince;
    final record = _all[key] ?? const AttendanceRecord();
    final meets = switch (_c._group(key)) {
      ServiceGroup(:final id) => switch (b.services[cid]!.byId(id)) {
        final s? when record.time != null => Meets(
          weekdays: s.weekdays,
          every: record.time!.every,
          startsOn: record.time!.startsOn,
          monthWeeks: record.time!.monthWeeks,
          roster: record.time!.startsOn == null ? null : b.rosters[cid]!.containsKey(Roster.idFor(id, day)),
        ),
        final s? => Meets(weekdays: s.weekdays, roster: b.rosters[cid]!.containsKey(Roster.idFor(id, day))),
        null => null,
      },
      SmallGroup(:final id) => b.smallGroups[cid]?[id]?.meets,
      GatheringGroup(:final id) => _gatherings[id]?.time.meets(),
      _ => null,
    };
    if (since == null ||
        day.isAfter(today) ||
        meets == null ||
        record.days.containsKey(day) ||
        !attendanceDue(meets, since: since, pauses: record.pauses, day: day)) {
      throw const CloudException(CloudErrorCode.conflict);
    }
    if (b.attendanceReminders[cid]?[key]?.on == today) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.remindedToday);
    }
    final told = [
      for (final m in b.members[cid]!.values)
        if (m.remindedOf(key, record.fillers)) m.uid,
    ];
    await b.write(() => (b.attendanceReminders[cid] ??= {})[key] = (on: today, day: day, told: told));
    return told.length;
  }

  @override
  Future<void> saveSince(Day? since) async {
    _c._requireAdmin();
    await _c._b.write(
      () => _c._b.churches[_c.churchId] = _c._b.churches[_c.churchId]!.copyWith(attendanceSince: () => since),
    );
  }
}
