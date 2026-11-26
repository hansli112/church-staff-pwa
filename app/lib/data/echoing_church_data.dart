import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/day.dart';
import '../domain/models.dart';
import '../domain/staff_order.dart';
import 'backend.dart';

/// [ChurchData] that shows a change the moment it is made, while the
/// backend still writes it: rosters, members, services, staff orders, 小組,
/// the church's settings, 人數, 其他聚會, 備註 and the webhook. What has
/// nothing to show early (a calendar event, 不能服事的日子, kept by their
/// pages) still counts as [saving].
///
/// Writes stay online compare-and-sets (docs/design.md): only what is shown
/// changes early. They go one at a time, so a change made on top of one
/// still being written is compared against what that one wrote. A refused
/// change goes off the screen again at once; a written one stays until the
/// backend's copy shows it, or for [linger] at most.
class EchoingChurchData implements ChurchData {
  EchoingChurchData(this._inner, {DateTime Function()? clock, void Function() Function()? beginWrite})
    : _clock = clock ?? DateTime.now,
      _beginWrite = beginWrite;

  /// How long a written change keeps showing over a backend copy that does
  /// not show it: two changes landing together, or someone else's right
  /// after. Then the backend's copy wins.
  static const linger = Duration(seconds: 5);

  final ChurchData _inner;
  final DateTime Function() _clock;

  /// A lease from the moment a change is made until it is written or
  /// refused, so the app does not update over it.
  final void Function() Function()? _beginWrite;

  /// Changes being written or just written, oldest first.
  final _echoes = <_Echo>[];
  final _changed = StreamController<void>.broadcast(sync: true);
  Future<void> _queue = Future.value();

  /// Ends each written change's [linger], should nothing else come by.
  final _timers = <Timer>{};

  /// Stops showing anything early. For when the church is no longer shown.
  void close() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _changed.close();
  }

  void _dropExpired() => _echoes.removeWhere((e) => e.until?.isBefore(_clock()) ?? false);

  /// Whether a change is still on its way to the backend.
  bool get saving => _echoes.any((e) => e.until == null);

  Stream<bool> watchSaving() => Stream.multi((out) {
    var last = saving;
    out.add(last);
    final sub = _changed.stream.listen((_) {
      if (saving != last) out.add(last = saving);
    });
    out.onCancel = sub.cancel;
  });

  /// Shows [echo] while [write] writes it, after the writes before it
  /// unless [queued] is false (one that compares nothing, sent at once).
  Future<void> _send(_Echo echo, Future<void> Function() write, {bool queued = true}) {
    final release = _beginWrite?.call();
    _dropExpired();
    _echoes.add(echo);
    _changed.add(null);
    final Future<void> done;
    if (queued) {
      done = _queue.then((_) => write());
      _queue = done.then((_) {}, onError: (_) {});
    } else {
      done = Future.sync(write);
    }
    done
        .then<void>(
          (_) {
            echo.until = _clock().add(linger);
            late final Timer timer;
            timer = Timer(linger, () {
              _timers.remove(timer);
              if (_echoes.remove(echo) && !_changed.isClosed) _changed.add(null);
            });
            _timers.add(timer);
          },
          onError: (Object _) {
            _echoes.remove(echo);
          },
        )
        .whenComplete(() {
          release?.call();
          if (!_changed.isClosed) _changed.add(null);
        });
    return done;
  }

  /// [server] with the changes not yet in it. Each stream keeps its own
  /// record of the changes it has seen arrive, which then no longer apply.
  Stream<T> _echoed<T>(Stream<T> server, T Function(T server, Set<Object> arrived) apply) {
    late final StreamController<T> out;
    StreamSubscription<T>? serverSub;
    StreamSubscription<void>? changedSub;
    final arrived = <Object>{};
    (T,)? last;
    Object? shown;
    void emit({required bool fromServer}) {
      if (last case (final value,)) {
        _dropExpired();
        // Changes no longer kept are not looked up again.
        arrived.removeWhere((id) => id is (_Echo, Object) && !_echoes.contains(id.$1));
        final next = apply(value, arrived);
        if (!fromServer && identical(next, shown)) return;
        shown = next;
        out.add(next);
      }
    }

    out = StreamController<T>(
      onListen: () {
        serverSub = server.listen(
          (value) {
            last = (value,);
            emit(fromServer: true);
          },
          onError: out.addError,
          onDone: () {
            unawaited(changedSub?.cancel());
            changedSub = null;
            out.close();
          },
        );
        changedSub = _changed.stream.listen((_) => emit(fromServer: false));
      },
      onPause: () {
        serverSub?.pause();
        changedSub?.pause();
      },
      onResume: () {
        serverSub?.resume();
        changedSub?.resume();
      },
      // Not awaited, as the backend's own streams: `first` would wait on it.
      onCancel: () {
        unawaited(serverSub?.cancel());
        unawaited(changedSub?.cancel());
        serverSub = null;
        changedSub = null;
      },
    );
    return out.stream;
  }

  /// Whether [echo]'s change at [key] still shows over [server]'s copy,
  /// noting in [arrived] once the backend's copy has it.
  bool _shows(_Echo echo, Object key, bool inServer, Set<Object> arrived) {
    final id = (echo, key);
    if (arrived.contains(id)) return false;
    if (echo.until != null && inServer) {
      arrived.add(id);
      return false;
    }
    return true;
  }

  /// [server] with each change at [at] not yet in it.
  Stream<T> _echoedAt<T>(Stream<T> server, Object at) =>
      _echoed(server, (server, arrived) => _changedAt(server, server, at, arrived));

  /// [shown] with each change at [at] that [server] does not have yet.
  T _changedAt<T>(T shown, T server, Object at, Set<Object> arrived) {
    for (final echo in _echoes) {
      final change = echo.at[at] as _Change<T>?;
      if (change == null) continue;
      if (!_shows(echo, at, change.arrivedIn(server), arrived)) continue;
      shown = change.apply(shown);
    }
    return shown;
  }

  /// [write], counted as [saving] while on its way, with nothing to show
  /// early: sent at once, as before, whatever else is on its way.
  Future<T> _counted<T>(Future<T> Function() write) async {
    late final T answer;
    await _send(_Echo(), () async => answer = await write(), queued: false);
    return answer;
  }

  @override
  late final CalendarData calendar = _CountedCalendar(this);

  @override
  late final ChurchLinkData churchLink = _CountedChurchLink(this);

  @override
  late final WebhookData webhook = _EchoingWebhook(this);

  // Shown as the backend has them: none of these echo.
  @override
  PhotoData get photos => _inner.photos;

  @override
  late final AttendanceData attendance = _EchoingAttendance(this);

  @override
  late final RosterNoteData rosterNotes = _EchoingRosterNotes(this);

  @override
  ReadOnceData get readOnce => _inner.readOnce;

  @override
  late final UnavailableData unavailable = _CountedUnavailable(this);

  @override
  SwapData get swaps => _inner.swaps;

  @override
  ClaimData get claims => _inner.claims;

  @override
  FamilyData get family => _inner.family;

  @override
  late final JoiningData joining = _EchoingJoining(this);

  /// The calls that change what is listed show it at once: who is in a
  /// group, on a duty's list, added by name, renamed (seconds on the
  /// backend, over every roster); the rest as the backend has them, counted
  /// as [saving] while on their way and sent at once, not after the
  /// changes before them.
  @override
  Future<R> run<R>(ChurchCall<R> call) async {
    final echo = switch (call) {
      SetGroupMember(:final uid, :final group, :final member, :final duties, :final smallGroups) => _Echo(
        members: {uid: (m) => m.inGroupAs(group, member: member, duties: duties, smallGroups: smallGroups)},
      ),
      SetDuty(:final uid, :final serviceType, :final duty, :final on) => _Echo(
        members: {uid: (m) => on ? m.withDuty(serviceType, duty) : m.withoutDuty(serviceType, duty)},
        pending: {uid: (p) => on ? p?.withDuty(serviceType, duty) : p?.withoutDuty(serviceType, duty)},
      ),
      RenameMember(:final uid, :final name) => _Echo(members: {uid: (m) => m.copyWith(name: name.trim())}),
      RenamePending(:final id, :final name) => _Echo(pending: {id: (p) => p?.copyWith(name: name.trim())}),
      // The new 同工 shows once the backend gives them an ID.
      AddByName() => _Echo(pending: {}),
      // Seconds on the backend, shown on its way (儲存中…) with nothing to echo.
      MergePending() || AddFamily() || RemoveFamily() || RemoveFromHousehold() => _Echo(),
      DeleteSmallGroup(:final id) => _Echo(smallGroups: {id: null}),
      OrderSmallGroups(:final ids) => _Echo(
        at: {
          _smallGroupsAt: _Change<List<SmallGroupDetails>>(
            (list) => [for (final g in list) ids.contains(g.id) ? g.copyWith(order: () => ids.indexOf(g.id)) : g],
            (list) => list.every((g) => !ids.contains(g.id) || g.order == ids.indexOf(g.id)),
          ),
        },
      ),
      RenameChurch(:final name) => _Echo(
        at: {
          _churchAt: _Change<Church?>((c) => c?.copyWith(name: name.trim()), (c) => c?.name == name.trim()),
        },
      ),
      SetTimeZone(:final timeZone) => _Echo(
        at: {
          _churchAt: _Change<Church?>((c) => c?.copyWith(timeZone: timeZone), (c) => c?.timeZone == timeZone),
        },
      ),
      _ => null,
    };
    // A read saves nothing.
    if (call is CoverCandidates) return _inner.run(call);
    if (echo == null) return _counted(() => _inner.run(call));
    late final R answer;
    await _send(echo, () async {
      answer = await _inner.run(call);
      if (call case AddByName(:final name, :final serviceType)) {
        final id = answer as String;
        echo.pending[id] = (p) =>
            p ??
            PendingMember(
              id: id,
              name: name.trim(),
              zones: [Zone(serviceType: serviceType)],
            );
      }
    });
    return answer;
  }

  @override
  Stream<List<Roster>> rosters({required Day from}) => _echoed(_inner.rosters(from: from), (server, arrived) {
    Map<String, Roster>? byId;
    for (final echo in _echoes) {
      for (final MapEntry(key: id, value: after) in echo.rosters.entries) {
        final current = server.where((r) => r.id == id).firstOrNull;
        final inServer = current?.copyWith(saved: true) == after;
        if (!_shows(echo, ('roster', id), inServer, arrived)) continue;
        byId ??= {for (final r in server) r.id: r};
        // As the backend reads them: none ending before [from].
        if (after == null || after.lastDay.isBefore(from)) {
          byId.remove(id);
        } else {
          byId[id] = after;
        }
      }
    }
    if (byId == null) return server;
    return byId.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  });

  Member? _memberEchoed(Member server, Set<Object> arrived) {
    Member? shown = server;
    for (final echo in _echoes) {
      final change = echo.members[server.uid] ?? echo.everyMember;
      if (change == null) continue;
      final next = change(server);
      final inServer = next != null && _sameMember(next, server);
      if (!_shows(echo, ('member', server.uid), inServer, arrived)) continue;
      shown = shown == null ? null : change(shown);
    }
    return shown;
  }

  @override
  Stream<Member?> member(String uid) => _echoed(_inner.member(uid), (server, arrived) {
    if (server == null) return null;
    final shown = _memberEchoed(server, arrived);
    return _sameMember(shown, server) ? server : shown;
  });

  @override
  Stream<List<Member>> members() => _echoed(_inner.members(), (server, arrived) {
    if (!_echoes.any((e) => e.members.isNotEmpty || e.everyMember != null)) return server;
    final shown = [for (final m in server) ?_memberEchoed(m, arrived)];
    return listEquals(shown, server) ? server : shown;
  });

  @override
  Stream<ServiceSettings> services() => _echoed(_inner.services(), (server, arrived) {
    var shown = server;
    for (final echo in _echoes) {
      final change = echo.services;
      if (change == null) continue;
      final inServer = listEquals(change(server).services, server.services);
      if (!_shows(echo, 'services', inServer, arrived)) continue;
      shown = change(shown);
    }
    return shown;
  });

  @override
  Stream<MinistrySettings> ministries() => _echoed(_inner.ministries(), (server, arrived) {
    var shown = server;
    for (final echo in _echoes) {
      final after = echo.ministries;
      if (after == null) continue;
      if (!_shows(echo, 'ministries', listEquals(server.ministries, after), arrived)) continue;
      shown = shown.withMinistries(after);
    }
    return shown;
  });

  @override
  Stream<StaffOrder> staffOrder(String serviceType) => _echoed(_inner.staffOrder(serviceType), (server, arrived) {
    var shown = server;
    for (final echo in _echoes) {
      final after = echo.staffOrders[serviceType];
      if (after == null) continue;
      if (!_shows(echo, ('staffOrder', serviceType), server == after, arrived)) continue;
      shown = after;
    }
    return shown;
  });

  @override
  Future<void> compareAndSetRosters(RosterChange change) => _send(
    _Echo(
      rosters: {for (final e in change.after.entries) e.key: e.value?.copyWith(saved: true)},
      staffOrders: {if (change.staffOrder case final o?) o.serviceType: o.after},
    ),
    () => _inner.compareAndSetRosters(change),
  );

  @override
  Future<void> compareAndSetLedDuties(RosterChange change) => _send(
    _Echo(rosters: {for (final e in change.after.entries) e.key: e.value?.copyWith(saved: true)}),
    () => _inner.compareAndSetLedDuties(change),
  );

  @override
  Stream<bool> plannedNews(String serviceType) => _inner.plannedNews(serviceType);

  @override
  Future<void> compareAndSetMinistries({required List<Ministry> before, required List<Ministry> after}) => _send(
    _Echo(ministries: after),
    () => _inner.compareAndSetMinistries(before: before, after: after),
  );

  @override
  Future<void> compareAndSetServiceList({required List<Service> before, required List<Service> after}) => _send(
    _Echo(services: (settings) => settings.withServices(after)),
    () => _inner.compareAndSetServiceList(before: before, after: after),
  );

  @override
  Future<void> compareAndSetService({
    required Service before,
    required Service after,
    ({String from, String to})? dutyRename,
  }) => _send(
    _Echo(services: (settings) => _withService(settings, after)),
    () => _inner.compareAndSetService(before: before, after: after, dutyRename: dutyRename),
  );

  @override
  Future<void> compareAndSetMember({required Member before, required Member after}) => _send(
    _Echo(members: {after.uid: (_) => after}),
    () => _inner.compareAndSetMember(before: before, after: after),
  );

  @override
  Future<void> removeMember(String uid) => _send(_Echo(members: {uid: (_) => null}), () => _inner.removeMember(uid));

  @override
  Future<void> setNotificationPrefs(String uid, Set<NotificationKind> muted) => _send(
    _Echo(members: {uid: (m) => m.copyWith(mutedNotifications: muted)}),
    () => _inner.setNotificationPrefs(uid, muted),
  );

  @override
  Future<void> setReminderTiming(String uid, ReminderTiming timing) => _send(
    _Echo(members: {uid: (m) => m.copyWith(reminderTiming: timing)}),
    () => _inner.setReminderTiming(uid, timing),
  );

  @override
  Future<void> setReminderHour(String uid, int hour) => _send(
    _Echo(members: {uid: (m) => m.copyWith(reminderHour: hour)}),
    () => _inner.setReminderHour(uid, hour),
  );

  @override
  Future<void> setReminderDays(String uid, int days) => _send(
    _Echo(members: {uid: (m) => m.copyWith(reminderDays: days)}),
    () => _inner.setReminderDays(uid, days),
  );

  // Everything else as the backend has it.

  @override
  String get churchId => _inner.churchId;

  @override
  Stream<Church?> church() => _echoedAt(_inner.church(), _churchAt);

  @override
  Stream<List<PendingMember>> pendingMembers() => _echoed(_inner.pendingMembers(), (server, arrived) {
    List<PendingMember>? shown;
    for (final echo in _echoes) {
      for (final MapEntry(key: id, value: change) in echo.pending.entries) {
        final list = shown ?? server;
        final current = list.where((p) => p.id == id).firstOrNull;
        final next = change(current);
        if (next == null) continue;
        final inServer = server.where((p) => p.id == id).firstOrNull == next;
        if (!_shows(echo, ('pending', id), inServer, arrived)) continue;
        shown = current == null ? [...list, next] : [for (final p in list) p.id == id ? next : p];
      }
      for (final id in echo.pendingGone) {
        if (!_shows(echo, ('pending', id), !server.any((p) => p.id == id), arrived)) continue;
        shown = [
          for (final p in shown ?? server)
            if (p.id != id) p,
        ];
      }
    }
    return shown ?? server;
  });

  @override
  Future<void> deletePendingMember(String id) => _send(_Echo(pendingGone: {id}), () => _inner.deletePendingMember(id));

  @override
  Future<List<Roster>> pastRosters({required Day from, required Day before}) =>
      _inner.pastRosters(from: from, before: before);

  @override
  Future<Roster?> rosterBefore({required String serviceType, required Day before}) =>
      _inner.rosterBefore(serviceType: serviceType, before: before);

  @override
  Future<List<Roster>> eventRosters() => _inner.eventRosters();

  @override
  Future<void> setHomeName(String? name) => _inner.setHomeName(name);

  @override
  Stream<List<SmallGroupDetails>> smallGroups() => _echoed(_inner.smallGroups(), (server, arrived) {
    var shown = server;
    for (final echo in _echoes) {
      for (final MapEntry(key: id, value: after) in echo.smallGroups.entries) {
        if (!_shows(echo, ('smallGroup', id), server.byId(id) == after, arrived)) continue;
        shown = [
          for (final g in shown)
            if (g.id != id) g else ?after,
        ];
      }
    }
    return _changedAt(shown, server, _smallGroupsAt, arrived);
  });

  /// A 小組 changed, and its new 小組長, show at once.
  @override
  Future<String> saveSmallGroup(
    SmallGroupDetails group, {
    SmallGroupDetails? before,
    List<String>? leads,
    List<String>? leadsBefore,
  }) async {
    Future<String> write() => _inner.saveSmallGroup(group, before: before, leads: leads, leadsBefore: leadsBefore);
    // A new 小組 has no id to show or lead until the backend gives it one.
    if (group.id.isEmpty) return write();
    late final String id;
    await _send(
      _Echo(
        smallGroups: {group.id: group},
        everyMember: leads == null ? null : (m) => m.withSmallGroupLead(group.id, lead: leads.contains(m.uid)),
      ),
      () async => id = await write(),
    );
    return id;
  }

  @override
  Future<void> uploadLogo(List<int> bytes) => _inner.uploadLogo(bytes);
}

/// What one change makes of the documents it writes.
class _Echo {
  _Echo({
    this.rosters = const {},
    this.members = const {},
    this.services,
    this.ministries,
    this.staffOrders = const {},
    this.everyMember,
    this.smallGroups = const {},
    this.pending = const {},
    this.pendingGone = const {},
    this.at = const {},
  });

  /// Each roster written, null for one deleted.
  final Map<String, Roster?> rosters;

  /// Each member changed, null for one removed.
  final Map<String, Member? Function(Member)> members;
  final ServiceSettings Function(ServiceSettings)? services;

  /// The 事工 list written.
  final List<Ministry>? ministries;
  final Map<String, StaffOrder> staffOrders;

  /// A change to whichever members it touches, for one the backend makes
  /// knowing who they are.
  final Member Function(Member)? everyMember;

  /// Each 小組 changed.
  /// Each changed, or (null) deleted.
  final Map<String, SmallGroupDetails?> smallGroups;

  /// Each 同工 without an account changed or added, from what is shown of
  /// them (null: not yet).
  final Map<String, PendingMember? Function(PendingMember?)> pending;

  /// Each 同工 without an account deleted.
  final Set<String> pendingGone;

  /// The rest it changes, by where it shows: [_churchAt], [_smallGroupsAt]
  /// (their order), [_gatheringsAt], [_notesAt], [_webhookAt], [_linkAt], or a
  /// group's 人數 at `('attendance', key)`.
  final Map<Object, _Change<Object?>> at;

  /// Null while being written; once written, until when it may still show.
  DateTime? until;
}

const _churchAt = 'church';
const _smallGroupsAt = 'smallGroups';
const _gatheringsAt = 'gatherings';
const _notesAt = 'notes';
const _webhookAt = 'webhook';
const _linkAt = 'link';

/// One change at an [_Echo.at]: what it makes of what is shown, and
/// whether the backend's copy has it (by default, when it makes nothing
/// new of it).
class _Change<T> {
  _Change(this._apply, [this._arrived]);

  final T Function(T shown) _apply;
  final bool Function(T server)? _arrived;

  T apply(T shown) => _apply(shown);

  bool arrivedIn(T server) => _arrived?.call(server) ?? apply(server) == server;
}

/// 人數 and 其他聚會, shown at once.
class _EchoingAttendance implements AttendanceData {
  _EchoingAttendance(this._d);

  final EchoingChurchData _d;
  AttendanceData get _inner => _d._inner.attendance;

  static (String, String) _at(String key) => ('attendance', key);

  static _Change<AttendanceRecord> _record(
    AttendanceRecord Function(AttendanceRecord) apply,
    bool Function(AttendanceRecord) arrived,
  ) => _Change<AttendanceRecord>(apply, arrived);

  static _Change<AttendanceRecord> _day(Day day, AttendanceDay? value) => _record(
    (r) => r.copyWith(days: {...r.days, day: ?value}..removeWhere((d, _) => d == day && value == null)),
    (r) => r.days[day] == value,
  );

  static _Change<List<Gathering>> _gatherings(
    List<Gathering> Function(List<Gathering>) apply,
    bool Function(List<Gathering>) arrived,
  ) => _Change<List<Gathering>>((list) => apply(list)..sort((a, b) => byOrder(a.place, b.place)), arrived);

  @override
  Stream<AttendanceRecord> watch(String key) => _d._echoedAt(_inner.watch(key), _at(key));

  @override
  Stream<Set<String>> mine() => _inner.mine();

  @override
  Future<void> save(String key, Day day, AttendanceDay? value) =>
      _d._send(_Echo(at: {_at(key): _day(day, value)}), () => _inner.save(key, day, value));

  @override
  Future<void> saveTogether(String key, Day day, AttendanceDay value) => _d._send(
    _Echo(
      at: {
        _at(key): _day(day, value),
        for (final other in value.together) _at(other): _day(day, AttendanceDay.joined(key)),
      },
    ),
    () => _inner.saveTogether(key, day, value),
  );

  @override
  Future<void> saveFillers(String key, List<String> fillers) => _d._send(
    _Echo(at: {_at(key): _record((r) => r.copyWith(fillers: fillers), (r) => listEquals(r.fillers, fillers))}),
    () => _inner.saveFillers(key, fillers),
  );

  @override
  Future<void> savePauses(String key, List<AttendancePause> pauses) => _d._send(
    _Echo(at: {_at(key): _record((r) => r.copyWith(pauses: pauses), (r) => listEquals(r.pauses, pauses))}),
    () => _inner.savePauses(key, pauses),
  );

  @override
  Stream<List<Gathering>> gatherings() => _d._echoedAt(_inner.gatherings(), _gatheringsAt);

  /// A new one shows once the backend gives it an ID; one changed, at once,
  /// where it was.
  @override
  Future<String> saveGathering(Gathering gathering) async {
    if (gathering.id.isEmpty) return _d._counted(() => _inner.saveGathering(gathering));
    final name = gathering.name.trim();
    late final String id;
    await _d._send(
      _Echo(
        at: {
          _gatheringsAt: _gatherings(
            (list) => [for (final g in list) g.id == gathering.id ? g.copyWith(name: name, time: gathering.time) : g],
            (list) => list.any((g) => g.id == gathering.id && g.name == name && g.time == gathering.time),
          ),
        },
      ),
      () async => id = await _inner.saveGathering(gathering),
    );
    return id;
  }

  @override
  Future<void> orderGatherings(List<String> ids) => _d._send(
    _Echo(
      at: {
        _gatheringsAt: _gatherings(
          (list) => [for (final g in list) ids.contains(g.id) ? g.copyWith(order: () => ids.indexOf(g.id)) : g],
          (list) => list.every((g) => !ids.contains(g.id) || g.order == ids.indexOf(g.id)),
        ),
      },
    ),
    () => _inner.orderGatherings(ids),
  );

  @override
  Future<void> deleteGathering(String id) => _d._send(
    _Echo(
      at: {
        _gatheringsAt: _gatherings(
          (list) => [
            for (final g in list)
              if (g.id != id) g,
          ],
          (list) => !list.any((g) => g.id == id),
        ),
      },
    ),
    () => _inner.deleteGathering(id),
  );

  @override
  Future<int> remind(String key, Day day) => _d._counted(() => _inner.remind(key, day));

  @override
  Future<void> saveSince(Day? since) => _d._send(
    _Echo(
      at: {
        _churchAt: _Change<Church?>(
          (c) => c?.copyWith(attendanceSince: () => since),
          (c) => c?.attendanceSince == since,
        ),
      },
    ),
    () => _inner.saveSince(since),
  );
}

/// 備註, shown at once; its files go up as they are picked.
class _EchoingRosterNotes implements RosterNoteData {
  _EchoingRosterNotes(this._d);

  final EchoingChurchData _d;
  RosterNoteData get _inner => _d._inner.rosterNotes;

  @override
  Stream<Map<String, RosterNote>> watch() => _d._echoedAt(_inner.watch(), _notesAt);

  @override
  Future<NoteFile> upload(
    String rosterId, {
    required String name,
    required String type,
    required Uint8List bytes,
    void Function(double done)? onProgress,
  }) => _inner.upload(rosterId, name: name, type: type, bytes: bytes, onProgress: onProgress);

  @override
  Future<void> discard(String rosterId, NoteFile file) => _inner.discard(rosterId, file);

  @override
  Future<void> save(String rosterId, RosterNote note) {
    final kept = RosterNote(text: note.text.trim(), files: note.files);
    return _d._send(
      _Echo(
        at: {
          _notesAt: _Change<Map<String, RosterNote>>(
            (notes) => {...notes, rosterId: kept}..removeWhere((id, n) => id == rosterId && n.isEmpty),
            (notes) => notes[rosterId] == (kept.isEmpty ? null : kept),
          ),
        },
      ),
      () => _inner.save(rosterId, note),
    );
  }
}

/// The webhook's switches and turning it off, shown at once.
class _EchoingWebhook implements WebhookData {
  _EchoingWebhook(this._d);

  final EchoingChurchData _d;
  WebhookData get _inner => _d._inner.webhook;

  @override
  Stream<WebhookSettings?> watch() => _d._echoedAt(_inner.watch(), _webhookAt);

  @override
  Future<String?> save({required String? url, bool calendar = false, bool roster = false, String? secret}) {
    Future<String?> write() => _inner.save(url: url, calendar: calendar, roster: roster, secret: secret);
    bool same(WebhookSettings? w) =>
        url == null ? w == null : w != null && w.url == url && w.calendar == calendar && w.roster == roster;
    late final String? answer;
    return _d
        ._send(
          _Echo(
            at: {
              _webhookAt: _Change<WebhookSettings?>(
                // A first one shows once the backend has it: its secret is
                // said then.
                (w) => url == null || w == null
                    ? (url == null ? null : w)
                    : WebhookSettings(url: url, calendar: calendar, roster: roster, lastDelivery: w.lastDelivery),
                same,
              ),
            },
          ),
          () async => answer = await write(),
        )
        .then((_) => answer);
  }

  @override
  Future<String?> rotateSecret({String? secret}) => _d._counted(() => _inner.rotateSecret(secret: secret));

  @override
  Future<WebhookDelivery> test() => _inner.test();
}

/// Whether anyone may ask to join, shown at once.
class _EchoingJoining implements JoiningData {
  _EchoingJoining(this._d);

  final EchoingChurchData _d;
  JoiningData get _inner => _d._inner.joining;

  @override
  Stream<List<JoinRequest>> requests() => _inner.requests();

  @override
  Future<void> setTakesRequests(bool on) => _d._send(
    _Echo(
      at: {
        _churchAt: _Change<Church?>((c) => c?.copyWith(takesJoinRequests: on), (c) => c?.takesJoinRequests == on),
      },
    ),
    () => _inner.setTakesRequests(on),
  );

  @override
  Stream<List<Invite>> invites() => _inner.invites();

  @override
  Future<Invite> createInvite({required Duration validFor, List<String> zoneTypes = const []}) =>
      _d._counted(() => _inner.createInvite(validFor: validFor, zoneTypes: zoneTypes));

  @override
  Future<Invite> renewInvite(String code, {required Duration validFor}) =>
      _d._counted(() => _inner.renewInvite(code, validFor: validFor));

  @override
  Future<void> revokeInvite(String code) => _d._counted(() => _inner.revokeInvite(code));
}

/// Calendar events, shown at once by the calendar's own months
/// (CalendarMonths.write), counted here as [EchoingChurchData.saving].
class _CountedCalendar implements CalendarData {
  _CountedCalendar(this._d);

  final EchoingChurchData _d;
  CalendarData get _inner => _d._inner.calendar;

  @override
  Stream<CalendarSettings> settings() => _inner.settings();

  @override
  Future<Uri> authUrl() => _inner.authUrl();

  @override
  Future<List<CalendarChoice>> choices() => _inner.choices();

  @override
  Future<void> select(String calendarId, String calendarName) =>
      _d._counted(() => _inner.select(calendarId, calendarName));

  @override
  Future<void> disconnect() => _d._counted(_inner.disconnect);

  @override
  Future<List<CalendarEvent>> events(String month) => _inner.events(month);

  @override
  Future<CalendarEvent> save(CalendarEvent event, {CalendarEvent? previous, String? restoreRosterOf}) =>
      _d._counted(() => _inner.save(event, previous: previous, restoreRosterOf: restoreRosterOf));

  @override
  Future<void> delete(CalendarEvent event) => _d._counted(() => _inner.delete(event));
}

/// The church's 連結, counted as [EchoingChurchData.saving] while saved.
class _CountedChurchLink implements ChurchLinkData {
  _CountedChurchLink(this._d);

  final EchoingChurchData _d;
  ChurchLinkData get _inner => _d._inner.churchLink;

  @override
  Stream<ChurchLink?> watch() => _d._echoedAt(_inner.watch(), _linkAt);

  /// One set shows once the backend has fetched it; one taken off goes at
  /// once.
  @override
  Future<LinkSourceResult> save(ChurchLink? link) async {
    if (link != null) return _d._counted(() => _inner.save(link));
    late final LinkSourceResult result;
    await _d._send(
      _Echo(at: {_linkAt: _Change<ChurchLink?>((_) => null)}),
      () async => result = await _inner.save(null),
    );
    return result;
  }

  @override
  Future<LinkSourceResult> refresh() => _inner.refresh();

  @override
  Stream<LinkContent?> content() => _inner.content();
}

/// 不能服事的日子, shown at once by their page, counted here as
/// [EchoingChurchData.saving].
class _CountedUnavailable implements UnavailableData {
  _CountedUnavailable(this._d);

  final EchoingChurchData _d;
  UnavailableData get _inner => _d._inner.unavailable;

  @override
  Stream<UnavailableDays> of(String uid) => _inner.of(uid);

  @override
  Stream<Map<String, UnavailableDays>> everyones() => _inner.everyones();

  @override
  Future<void> saveMine(UnavailableDays days) => _d._counted(() => _inner.saveMine(days));

  @override
  Future<void> send() => _d._counted(_inner.send);

  @override
  Stream<UnavailableAsked?> askedOfMe() => _inner.askedOfMe();

  @override
  Stream<UnavailableRound?> round(String serviceType) => _inner.round(serviceType);
}

ServiceSettings _withService(ServiceSettings settings, Service after) =>
    settings.withServices([for (final s in settings.services) s.id == after.id ? after : s]);

bool _sameMember(Member? a, Member? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.sameAdminFields(b) &&
        a.email == b.email &&
        a.reminderTiming == b.reminderTiming &&
        a.reminderHour == b.reminderHour &&
        a.reminderDays == b.reminderDays &&
        setEquals(a.mutedNotifications, b.mutedNotifications));
