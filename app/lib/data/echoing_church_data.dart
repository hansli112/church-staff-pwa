import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/day.dart';
import '../domain/models.dart';
import '../domain/staff_order.dart';
import 'backend.dart';

/// [ChurchData] that shows a change to rosters, members, services, staff
/// orders or 小組 the moment it is made, while the backend still writes it.
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

  Future<void> _send(_Echo echo, Future<void> Function() write) {
    final release = _beginWrite?.call();
    _dropExpired();
    _echoes.add(echo);
    _changed.add(null);
    final done = _queue.then((_) => write());
    _queue = done.then((_) {}, onError: (_) {});
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

  // Shown as the backend has them: none of these echo.
  @override
  CalendarData get calendar => _inner.calendar;

  @override
  ChurchLinkData get churchLink => _inner.churchLink;

  @override
  WebhookData get webhook => _inner.webhook;

  @override
  PhotoData get photos => _inner.photos;

  @override
  AttendanceData get attendance => _inner.attendance;

  @override
  ReadOnceData get readOnce => _inner.readOnce;

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
      services: switch (change.serviceChange) {
        final s? => (settings) => _withService(settings, s.after),
        null => null,
      },
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
  Future<PlannedNotice> notifyPlanned(String serviceType) => _inner.notifyPlanned(serviceType);

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
  Future<void> setGroupMember(
    String uid,
    ChurchGroup group, {
    required bool member,
    List<String> duties = const [],
    List<String> smallGroups = const [],
  }) => _send(
    _Echo(
      members: {uid: (m) => m.inGroupAs(group, member: member, duties: duties, smallGroups: smallGroups)},
    ),
    () => _inner.setGroupMember(uid, group, member: member, duties: duties, smallGroups: smallGroups),
  );

  @override
  Future<void> grantDuty(String uid, String serviceType, String duty) => _send(
    _Echo(members: {uid: (m) => m.withDuty(serviceType, duty)}),
    () => _inner.grantDuty(uid, serviceType, duty),
  );

  @override
  Future<void> revokeDuty(String uid, String serviceType, String duty) => _send(
    _Echo(members: {uid: (m) => m.withoutDuty(serviceType, duty)}),
    () => _inner.revokeDuty(uid, serviceType, duty),
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

  // Everything else as the backend has it.

  @override
  String get churchId => _inner.churchId;

  @override
  Stream<Church?> church() => _inner.church();

  @override
  Stream<List<PendingMember>> pendingMembers() => _inner.pendingMembers();

  @override
  Future<void> deletePendingMember(String id) => _inner.deletePendingMember(id);

  @override
  Stream<List<JoinRequest>> joinRequests() => _inner.joinRequests();

  @override
  Future<void> answerJoinRequest(String uid, {required bool allow}) => _inner.answerJoinRequest(uid, allow: allow);

  @override
  Future<void> setTakesJoinRequests(bool on) => _inner.setTakesJoinRequests(on);

  @override
  Future<List<Roster>> pastRosters({required Day from, required Day before}) =>
      _inner.pastRosters(from: from, before: before);

  @override
  Future<List<Roster>> eventRosters() => _inner.eventRosters();

  @override
  Stream<List<Invite>> invites() => _inner.invites();

  @override
  Future<Invite> createInvite({required Duration validFor, List<String> zoneTypes = const []}) =>
      _inner.createInvite(validFor: validFor, zoneTypes: zoneTypes);

  @override
  Future<void> revokeInvite(String code) => _inner.revokeInvite(code);

  @override
  Future<void> setHomeName(String? name) => _inner.setHomeName(name);

  @override
  Stream<List<SmallGroupDetails>> smallGroups() => _echoed(_inner.smallGroups(), (server, arrived) {
    var shown = server;
    for (final echo in _echoes) {
      for (final MapEntry(key: id, value: after) in echo.smallGroups.entries) {
        if (!_shows(echo, ('smallGroup', id), server.byId(id) == after, arrived)) continue;
        shown = [for (final g in shown) g.id == id ? after : g];
      }
    }
    return shown;
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
  Future<void> deleteSmallGroup(String id) => _inner.deleteSmallGroup(id);

  @override
  Future<void> setTimeZone(ChurchTimeZone timeZone) => _inner.setTimeZone(timeZone);

  @override
  Future<void> uploadLogo(List<int> bytes) => _inner.uploadLogo(bytes);

  @override
  Future<void> deleteChurch() => _inner.deleteChurch();

  @override
  Future<void> restoreChurch() => _inner.restoreChurch();

  @override
  Future<void> mergePending(String pendingId, String uid) => _inner.mergePending(pendingId, uid);
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
  final Map<String, SmallGroupDetails> smallGroups;

  /// Null while being written; once written, until when it may still show.
  DateTime? until;
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
        setEquals(a.mutedNotifications, b.mutedNotifications));
