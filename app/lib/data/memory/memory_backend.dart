import 'dart:async';
import 'dart:math';

import '../../domain/day.dart';
import '../../domain/event_roster.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../domain/staff_order.dart';
import '../../domain/text.dart';
import '../backend.dart';

/// An in-memory [Backend] for widget tests and the offline demo: a verified
/// fake.
///
/// It keeps only the rules the screens depend on (who may read or write
/// what, invites, the last admin, an unverified email, a closed church),
/// and every one of them is checked against the real backend by the
/// contract tests in test/contract, which run the same cases on this class
/// and on the Firebase emulators. Whatever the backend computes beyond that
/// (reading a move file, fetching a church link's source, sending a
/// webhook, Google Calendar, photo recognition, the funding target) is not
/// imitated: those answers are scripted through the fields below.
class MemoryBackend implements Backend {
  MemoryBackend({DateTime Function()? clock}) : clock = clock ?? DateTime.now {
    auth = MemoryAuth();
    profiles = _Profiles(this);
    memberships = _Memberships(this);
    cloud = MemoryCloud(this);
    platform = _Platform(this);
  }

  @override
  final DateTime Function() clock;

  @override
  late final MemoryAuth auth;
  @override
  late final ProfileRepository profiles;
  @override
  late final MembershipRepository memberships;
  @override
  late final MemoryCloud cloud;
  @override
  late final PlatformData platform;

  /// What the backend last published for the support page.
  Funding? funding;

  /// The operator's cost list.
  List<CostItem> fundingCosts = [];

  /// Scripted: what the backend publishes once the operator changes the
  /// costs. Null leaves [funding] as it is.
  Funding Function(List<CostItem> costs)? publishFunding;

  final churches = <String, Church>{};
  final members = <String, Map<String, Member>>{};
  final services = <String, ServiceSettings>{};
  final rosters = <String, Map<String, Roster>>{};
  final staffOrders = <String, Map<String, StaffOrder>>{};
  final invites = <String, Invite>{};
  final users = <String, UserProfile>{};
  final calendars = <String, CalendarSettings>{};
  final churchLinks = <String, ChurchLink>{};
  final linkContents = <String, LinkContent>{};

  /// Pending members per church, by ID.
  final pendingMembers = <String, Map<String, PendingMember>>{};

  /// Uploaded move files by path.
  final moveFiles = <String, List<int>>{};

  /// Scripted: what reading any uploaded move file gives, a [MovePreview]
  /// or the [CloudException] the backend would throw.
  Object moveAnswer = const CloudException(CloudErrorCode.moveInvalid);
  final webhooks = <String, WebhookSettings>{};

  /// The webhook secret per church: only the backend has it.
  final webhookSecrets = <String, String>{};

  /// Scripted: what the receiver does with the next notices.
  WebhookDelivery webhookAnswer = const WebhookDelivery(ok: true, status: 200);

  /// Notices sent, as (church, event).
  final webhookSent = <(String, String)>[];

  /// Scripted: what fetching each content source URL gives, a
  /// [LinkContent] (its title, body and link) or a [LinkFetchError].
  /// Unknown URLs fail with [LinkFetchError.network].
  final linkSourceAnswers = <String, Object>{};

  /// Sources fetched by [ChurchData.setChurchLink], in order.
  final linkSourceFetches = <String>[];

  /// Scripted: while set, the link content stream delivers nothing until
  /// this completes, as on a slow network. Completing it with an error
  /// fails the stream instead.
  Completer<void>? linkContentHeld;

  /// Scripted Google Calendar: the events per church, and its calendars
  /// ([connectCalendar] stands in for the OAuth callback).
  final calendarEvents = <String, List<CalendarEvent>>{};

  /// Scripted: while set, reading a month's events waits for this to
  /// complete, as on a slow network. Completing it with an error fails it.
  Completer<void>? calendarEventsHeld;

  /// Scripted: photos used this month per church, the limit, whether the
  /// platform's budget is left, and what recognition returns.
  final photosUsed = <String, int>{};
  int photoLimit = 30;
  bool photoPlatformOpen = true;
  List<dynamic> recognized = const [];

  /// Set to make the next write fail, to test error handling.
  Object? failNextWrite;

  /// Simulated latency for every write.
  Duration writeDelay = Duration.zero;

  final _changes = StreamController<void>.broadcast(sync: true);

  void notify() => _changes.add(null);

  /// A stream of [read]'s value now and after every change, without
  /// repeats. A read that throws emits the error.
  Stream<T> watch<T>(T Function() read, {bool Function(T a, T b)? equals}) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    var hasLast = false;
    T? last;
    void emit() {
      try {
        final value = read();
        final same = hasLast && (equals != null ? equals(last as T, value) : last == value);
        if (same) return;
        hasLast = true;
        last = value;
        controller.add(value);
      } catch (e, st) {
        hasLast = false;
        controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        scheduleMicrotask(emit);
        sub = _changes.stream.listen((_) => emit());
      },
      // Not awaited: `first` would wait on it, and fake-async tests never
      // finish that future.
      onCancel: () {
        sub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> write(void Function() change) async {
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    final failure = failNextWrite;
    if (failure != null) {
      failNextWrite = null;
      throw failure;
    }
    change();
    notify();
  }

  @override
  ChurchData church(String churchId) => MemoryChurchData(this, churchId);

  // Seeding helpers for tests and the demo.

  String addChurch(
    String name, {
    String? id,
    ChurchStatus status = ChurchStatus.active,
  }) {
    final cid = id ?? 'c${churches.length + 1}';
    churches[cid] = Church(id: cid, name: name, status: status);
    members[cid] = {};
    rosters[cid] = {};
    staffOrders[cid] = {};
    services[cid] = const ServiceSettings(services: [], ids: []);
    notify();
    return cid;
  }

  void addMember(String cid, Member member) {
    members[cid]![member.uid] = member;
    notify();
  }

  void setServices(String cid, List<Service> list) {
    services[cid] = (services[cid] ?? const ServiceSettings(services: [])).withServices(list);
    notify();
  }

  Member? memberOf(String cid, String? uid) => uid == null ? null : members[cid]?[uid];

  bool isActiveMember(String cid, String? uid) =>
      memberOf(cid, uid) != null && churches[cid]?.status == ChurchStatus.active;

  /// The signed-in member of [cid], which must be open.
  Member requireMember(String cid) {
    final uid = auth.currentUser?.uid;
    if (!isActiveMember(cid, uid)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    return memberOf(cid, uid)!;
  }

  /// The signed-in admin of [cid], which must be open.
  Member requireAdmin(String cid) {
    final me = requireMember(cid);
    if (!me.isAdmin) throw const CloudException(CloudErrorCode.permissionDenied);
    return me;
  }

  /// The caller's access to [cid], decided as functions/src/access.ts does
  /// for every function that acts in a church: a non-member is refused, a
  /// member of a closed church is told it is closed, then [allowed] decides.
  /// [anyone] lets in non-members (claiming a pending member), [allowClosed]
  /// a closed church (restoring it).
  Member? functionAccess(
    String cid, {
    bool Function(Member me)? allowed,
    bool anyone = false,
    bool allowClosed = false,
  }) {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw const CloudException(CloudErrorCode.permissionDenied);
    final church = churches[cid];
    final me = memberOf(cid, uid);
    if (anyone) {
      if (church == null) throw const CloudException(CloudErrorCode.notFound);
    } else if (me == null) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    if (!(church?.isActive ?? false) && !allowClosed) {
      throw const CloudException(CloudErrorCode.churchClosed);
    }
    if (allowed != null && (me == null || !allowed(me))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    return me;
  }

  /// Simulates Google Calendar's OAuth callback for [cid].
  void connectCalendar(String cid, {String? calendarName}) {
    calendars[cid] = CalendarSettings(
      connected: true,
      calendarName: calendarName,
      calendarId: calendarName == null ? null : 'cal-$cid',
    );
    notify();
  }

  int _secrets = 0;
  String newWebhookSecret() => 'whsec_memory${++_secrets}';

  int _events = 0;
  String newEventId() => 'ev${++_events}';
}

class MemoryAuth implements AuthGateway {
  MemoryAuth();

  final _accounts = <String, ({String uid, String password, bool google, bool verified, String name})>{};
  final _state = StreamController<AuthUser?>.broadcast(sync: true);
  AuthUser? _current;
  int _next = 1;

  /// Email of the account the next Google sign-in picks; null cancels.
  String? googleAccount = 'google@example.com';

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> authState() async* {
    yield _current;
    yield* _state.stream;
  }

  void _set(AuthUser? user) {
    _current = user;
    _state.add(user);
  }

  AuthUser _user(String email) {
    final a = _accounts[email]!;
    return AuthUser(
      uid: a.uid,
      email: email,
      emailVerified: a.verified || a.google,
      displayName: a.name,
      usesPassword: !a.google,
    );
  }

  /// Signs in [email] directly, creating the account if needed.
  AuthUser signInAs(
    String email, {
    String? uid,
    String name = '',
    bool verified = true,
  }) {
    _accounts[email] ??= (
      uid: uid ?? 'u${_next++}',
      password: '',
      google: true,
      verified: verified,
      name: name,
    );
    final user = _user(email);
    _set(user);
    return user;
  }

  @override
  Future<void> signInWithGoogle() async {
    final email = googleAccount;
    if (email == null) throw const AuthException(AuthErrorCode.cancelled);
    final existing = _accounts[email];
    // One account per email: Google takes over a password account.
    _accounts[email] = (
      uid: existing?.uid ?? 'u${_next++}',
      password: existing?.password ?? '',
      google: true,
      verified: true,
      name: existing?.name ?? email.split('@').first,
    );
    _set(_user(email));
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    final a = _accounts[email.trim()];
    if (a == null || a.password.isEmpty || a.password != password) {
      throw const AuthException(AuthErrorCode.invalidCredential);
    }
    _set(_user(email.trim()));
  }

  @override
  Future<void> registerWithEmail(
    String name,
    String email,
    String password,
  ) async {
    email = email.trim();
    if (!email.contains('@')) {
      throw const AuthException(AuthErrorCode.invalidEmail);
    }
    if (password.length < 6) {
      throw const AuthException(AuthErrorCode.weakPassword);
    }
    if (_accounts.containsKey(email)) {
      throw AuthException(AuthErrorCode.emailInUse, email);
    }
    _accounts[email] = (
      uid: 'u${_next++}',
      password: password,
      google: false,
      verified: false,
      name: name,
    );
    _set(_user(email));
  }

  int verificationEmailsSent = 0;
  final resetEmails = <String>[];

  @override
  Future<void> sendEmailVerification() async => verificationEmailsSent++;

  @override
  Future<void> sendPasswordReset(String email) async => resetEmails.add(email);

  /// Marks [email] verified, as if its owner clicked the link.
  void verify(String email) {
    final a = _accounts[email]!;
    _accounts[email] = (
      uid: a.uid,
      password: a.password,
      google: a.google,
      verified: true,
      name: a.name,
    );
  }

  @override
  Future<void> reload() async {
    final email = _current?.email;
    if (email != null && _accounts.containsKey(email)) _set(_user(email));
  }

  @override
  Future<void> signOut() async => _set(null);

  /// uids that hold the platform operator claim.
  final operators = <String>{};

  @override
  Future<bool> isOperator() async => operators.contains(_current?.uid);

  void deleteCurrent() {
    final email = _current?.email;
    if (email != null) _accounts.remove(email);
    _set(null);
  }
}

class _Profiles implements ProfileRepository {
  _Profiles(this._b);
  final MemoryBackend _b;

  @override
  Stream<UserProfile?> watch(String uid) => _b.watch(() => _b.users[uid]);

  @override
  Future<void> save(UserProfile profile) async {
    _checkName(profile.name);
    await _b.write(() => _b.users[profile.uid] = profile);
  }

  @override
  Future<void> ensure(UserProfile profile) async {
    _checkName(profile.name);
    await _b.write(() => _b.users.putIfAbsent(profile.uid, () => profile));
  }
}

/// A person's name, on a profile or a member: refused past
/// [TextLimits.profileName] as firestore.rules refuses past its guard.
void _checkName(String name) {
  if (!withinTextLimit(name, TextLimits.profileName)) throw const CloudException(CloudErrorCode.permissionDenied);
}

class _Memberships implements MembershipRepository {
  _Memberships(this._b);
  final MemoryBackend _b;

  @override
  Stream<List<Membership>> watchMine(String uid) => _b.watch(
    () => [
      for (final entry in _b.members.entries)
        if (entry.value[uid] case final member?) Membership(churchId: entry.key, member: member),
    ],
    equals: (a, b) =>
        a.length == b.length &&
        List.generate(
          a.length,
          (i) => a[i].churchId == b[i].churchId && identical(a[i].member, b[i].member),
        ).every((x) => x),
  );
}

class MemoryChurchData implements ChurchData {
  MemoryChurchData(this._b, this.churchId);

  final MemoryBackend _b;

  @override
  final String churchId;

  String? get _uid => _b.auth.currentUser?.uid;
  Member? get _me => _b.memberOf(churchId, _uid);

  void _requireMember() => _b.requireMember(churchId);

  void _requireAdmin() => _b.requireAdmin(churchId);

  /// Admins and roster editors: the member list and pending members.
  void _requireRosterEditors() {
    if (!_b.requireMember(churchId).inGroup(Group.rosterEditors)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  /// A service the church has configured, which the member may edit.
  void _requireRosterEditor(String type) {
    final me = _b.requireMember(churchId);
    if (!_b.services[churchId]!.ids.contains(type) || !me.canEditRosters(type)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  /// Writing [r] over what is saved at its ID, as firestore.rules allow: a
  /// service's day by its zone, an event's roster by any roster editor. One
  /// never turns into the other, and a cancelled event's is the backend's.
  void _requireRosterWrite(Roster r) {
    final saved = _b.rosters[churchId]![r.id];
    if (saved != null && saved.isEvent != r.isEvent) throw const CloudException(CloudErrorCode.permissionDenied);
    if (!r.isEvent) return _requireRosterEditor(r.type);
    _requireRosterEditors();
    // The title and days are the calendar's: the app sets them only when
    // making the roster.
    final was = saved?.forEvent;
    if (was != null &&
        (was.cancelled || was.title != r.forEvent!.title || saved!.day != r.day || was.lastDay != r.lastDay)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
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
  Stream<List<PendingMember>> pendingMembers() => _b.watch(() {
    _requireRosterEditors();
    return (_b.pendingMembers[churchId] ?? const {}).values.toList();
  }, equals: _sameList);

  @override
  Future<void> deletePendingMember(String id) async {
    _requireAdmin();
    await _b.write(() => _b.pendingMembers[churchId]?.remove(id));
  }

  @override
  Stream<ServiceSettings> services() => _b.watch(() {
    _requireMember();
    return _b.services[churchId]!;
  });

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
  Future<List<Member>> allMembers() async {
    _requireRosterEditors();
    return _b.members[churchId]!.values.toList();
  }

  @override
  Future<List<PendingMember>> allPendingMembers() async {
    _requireRosterEditors();
    return (_b.pendingMembers[churchId] ?? const {}).values.toList();
  }

  @override
  Future<List<Roster>> allRosters() async {
    _requireMember();
    return _b.rosters[churchId]!.values.toList();
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
  Future<Map<String, StaffOrder>> allStaffOrders() async {
    _requireMember();
    return Map.of(_b.staffOrders[churchId]!);
  }

  @override
  Future<void> saveRoster(Roster roster) => saveRosters([roster]);

  @override
  Future<void> saveRosters(List<Roster> rosters, {String via = 'app'}) async {
    for (final r in rosters) {
      _requireRosterWrite(r);
    }
    await _b.write(() {
      for (final r in rosters) {
        _b.rosters[churchId]![r.id] = r.copyWith(saved: true);
      }
    });
  }

  @override
  Future<void> deleteRoster(Roster roster) async {
    roster.isEvent ? _requireRosterEditors() : _requireRosterEditor(roster.type);
    await _b.write(() => _b.rosters[churchId]!.remove(roster.id));
  }

  @override
  Future<void> updateStaffOrder(
    String serviceType,
    Map<String, List<String>?> changes,
  ) async {
    _requireRosterEditor(serviceType);
    await _b.write(() {
      final orders = _b.staffOrders[churchId]!;
      orders[serviceType] = (orders[serviceType] ?? StaffOrder()).withChanges(
        changes,
      );
    });
  }

  @override
  Future<void> saveServices(List<Service> services) async {
    _requireAdmin();
    if (services.isEmpty || services.length > 20) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    await _b.write(() {
      _b.services[churchId] = _b.services[churchId]!.withServices(services);
    });
  }

  @override
  Future<void> saveMember(Member member) async {
    _requireAdmin();
    if (member.uid == _uid && !member.isAdmin) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    _checkName(member.name);
    await _b.write(() => _b.members[churchId]![member.uid] = member);
  }

  @override
  Future<void> removeMember(String uid) async {
    final target = _b.memberOf(churchId, uid);
    // Leaving needs no open church: a member of a suspended one may go.
    final allowed = uid == _uid
        ? target != null && !target.isAdmin
        : _b.isActiveMember(churchId, _uid) && (_me?.isAdmin ?? false);
    if (!allowed) throw const CloudException(CloudErrorCode.permissionDenied);
    await _b.write(() => _b.members[churchId]!.remove(uid));
  }

  @override
  Future<void> setNotificationPrefs(
    String uid,
    Set<NotificationKind> muted,
  ) async {
    if (uid != _uid) throw const CloudException(CloudErrorCode.permissionDenied);
    final m = _b.requireMember(churchId);
    await _b.write(
      () => _b.members[churchId]![uid] = m.copyWith(mutedNotifications: muted),
    );
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
    if (validFor >= _inviteMax || zoneTypes.length > Limits.services) {
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

  @override
  Stream<CalendarSettings> calendarSettings() => _b.watch(() {
    _requireMember();
    return _b.calendars[churchId] ?? const CalendarSettings();
  });

  @override
  Stream<ChurchLink?> churchLink() => _b.watch(() {
    _requireMember();
    return _b.churchLinks[churchId];
  });

  @override
  Future<LinkSourceResult> setChurchLink(ChurchLink? link) async {
    _requireAdmin();
    if (link != null &&
        (link.title.isEmpty ||
            !withinTextLimit(link.title, TextLimits.linkTitle) ||
            !withinTextLimit(link.body, TextLimits.linkBody) ||
            link.url.length > Limits.url ||
            !ChurchLink.validUrl(link.url))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    final saved = _b.churchLinks[churchId];
    await _b.write(() {
      if (link == null) {
        _b.churchLinks.remove(churchId);
        return;
      }
      // Like the merge in Firestore: the source is set by the function below.
      _b.churchLinks[churchId] = ChurchLink(
        title: link.title,
        body: link.body,
        url: link.url,
        source: saved?.source,
        fetchMinute: saved?.fetchMinute ?? ChurchLink.defaultFetchMinute,
      );
    });
    if (link == null ||
        (link.source == saved?.source && (link.source == null || link.fetchMinute == saved?.fetchMinute))) {
      return const LinkSourceResult();
    }
    return _setLinkSource(link.source, link.fetchMinute);
  }

  @override
  Stream<LinkContent?> linkContent() {
    final content = _b.watch(() {
      _requireMember();
      return _b.linkContents[churchId];
    });
    final held = _b.linkContentHeld;
    if (held == null) return content;
    return Stream.fromFuture(held.future).asyncExpand((_) => content);
  }

  @override
  Stream<WebhookSettings?> webhook() => _b.watch(() {
    _requireAdmin();
    return _b.webhooks[churchId];
  });

  @override
  Future<void> setHomeName(String? name) async {
    _requireAdmin();
    if (name != null && (name.isEmpty || !withinTextLimit(name, TextLimits.homeName))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    await _b.write(() => _b.churches[churchId] = _b.churches[churchId]!.copyWith(homeName: () => name));
  }

  @override
  Future<void> uploadLogo(List<int> bytes) async {
    _requireAdmin();
    await _b.write(() {
      _b.churches[churchId] = _b.churches[churchId]!.copyWith(
        logoUrl: 'memory://logo/$churchId/${bytes.length}',
      );
    });
  }

  // What the Cloud Functions do for the church: refused as
  // functions/src/access.ts refuses ([MemoryBackend.functionAccess]).

  Member _functionAdmin({bool allowClosed = false}) =>
      _b.functionAccess(churchId, allowed: (me) => me.isAdmin, allowClosed: allowClosed)!;

  @override
  Future<void> deleteChurch() async {
    // Only an open church: deleting and restoring a suspended one would
    // reopen it.
    _functionAdmin();
    final c = _b.churches[churchId]!;
    _b.churches[churchId] = Church(
      id: c.id,
      name: c.name,
      status: ChurchStatus.deleted,
      logoUrl: c.logoUrl,
      homeName: c.homeName,
      deletedAt: _b.clock(),
    );
    _b.notify();
  }

  @override
  Future<void> restoreChurch() async {
    _functionAdmin(allowClosed: true);
    final c = _b.churches[churchId]!;
    if (c.isActive) return;
    final until = c.restorableUntil;
    if (c.status != ChurchStatus.deleted || (until != null && _b.clock().isAfter(until))) {
      throw const CloudException(CloudErrorCode.churchClosed);
    }
    _b.churches[churchId] = Church(id: c.id, name: c.name, logoUrl: c.logoUrl, homeName: c.homeName);
    _b.notify();
  }

  @override
  Future<void> mergePending(String pendingId, String uid) async {
    _functionAdmin();
    final p = _b.pendingMembers[churchId]?[pendingId];
    final m = _b.memberOf(churchId, uid);
    if (p == null || m == null) throw const CloudException(CloudErrorCode.notFound);
    _b.members[churchId]![uid] = _absorb(m, p);
    _repoint(_b, churchId, pendingId, uid);
    _b.pendingMembers[churchId]!.remove(pendingId);
    _b.notify();
  }

  /// The setLinkSource function.
  Future<LinkSourceResult> _setLinkSource(String? source, int fetchMinute) async {
    _functionAdmin();
    final link = _b.churchLinks[churchId];
    if (link == null) throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.noLink);
    ChurchLink next(String? s, int m) =>
        ChurchLink(title: link.title, body: link.body, url: link.url, source: s, fetchMinute: m);
    if (source == null) {
      _b.churchLinks[churchId] = next(null, ChurchLink.defaultFetchMinute);
      _b.linkContents.remove(churchId);
      _b.notify();
      return const LinkSourceResult();
    }
    if (source.length > Limits.url || !ChurchLink.validUrl(source)) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.notHttps);
    }
    final changed = link.source != source;
    _b.churchLinks[churchId] = next(source, fetchMinute);
    if (!changed) {
      _b.notify();
      return const LinkSourceResult();
    }
    // A new source is fetched at once; what it gives is scripted.
    _b.linkSourceFetches.add(source);
    final answer = _b.linkSourceAnswers[source] ?? LinkFetchError.network;
    final now = _b.clock();
    final LinkSourceResult result;
    if (answer is LinkContent) {
      _b.linkContents[churchId] = LinkContent(
        source: source,
        title: answer.title,
        body: answer.body,
        link: answer.link,
        fetchedAt: now,
      );
      result = LinkSourceResult(content: _b.linkContents[churchId]);
    } else {
      final error = answer as LinkFetchError;
      _b.linkContents[churchId] = LinkContent(source: source, error: error, errorAt: now);
      result = LinkSourceResult(error: error);
    }
    _b.notify();
    return result;
  }

  @override
  Future<String?> webhookSave({
    required String? url,
    bool calendar = false,
    bool roster = false,
    String? secret,
  }) async {
    _functionAdmin();
    if (url == null) {
      _b.webhooks.remove(churchId);
      _b.webhookSecrets.remove(churchId);
      _b.notify();
      return null;
    }
    if (url.length > Limits.url || !ChurchLink.validUrl(url)) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.notHttps);
    }
    _checkSecret(secret);
    String? generated;
    if (secret != null) {
      _b.webhookSecrets[churchId] = secret;
    } else if (!_b.webhookSecrets.containsKey(churchId)) {
      generated = _b.newWebhookSecret();
      _b.webhookSecrets[churchId] = generated;
    }
    _b.webhooks[churchId] = WebhookSettings(
      url: url.trim(),
      calendar: calendar,
      roster: roster,
      lastDelivery: _b.webhooks[churchId]?.lastDelivery,
    );
    _b.notify();
    return generated;
  }

  @override
  Future<String?> webhookRotateSecret({String? secret}) async {
    _functionAdmin();
    if (!_b.webhooks.containsKey(churchId)) throw const CloudException(CloudErrorCode.unknown);
    _checkSecret(secret);
    final next = secret ?? _b.newWebhookSecret();
    _b.webhookSecrets[churchId] = next;
    return secret == null ? next : null;
  }

  @override
  Future<WebhookDelivery> webhookTest() async {
    _functionAdmin();
    final hook = _b.webhooks[churchId];
    if (hook == null) throw const CloudException(CloudErrorCode.unknown);
    _b.webhookSent.add((churchId, 'ping'));
    final a = _b.webhookAnswer;
    final delivery = WebhookDelivery(ok: a.ok, status: a.status, error: a.error, event: 'ping', at: _b.clock());
    _b.webhooks[churchId] = WebhookSettings(
      url: hook.url,
      calendar: hook.calendar,
      roster: hook.roster,
      lastDelivery: delivery,
    );
    _b.notify();
    return delivery;
  }

  // Google Calendar itself is scripted: [MemoryBackend.connectCalendar], the
  // calendars [calendarList] offers and the events in
  // [MemoryBackend.calendarEvents].

  void _requireCalendarEditor() => _b.functionAccess(churchId, allowed: (me) => me.inGroup(Group.calendarEditors));

  @override
  Future<Uri> calendarAuthUrl() async {
    _functionAdmin();
    return Uri.parse('https://accounts.google.com/o/oauth2/v2/auth?state=memory');
  }

  @override
  Future<List<({String id, String name})>> calendarList() async {
    _functionAdmin();
    return const [(id: 'cal-1', name: '教會行事曆'), (id: 'cal-2', name: '青年行事曆')];
  }

  @override
  Future<void> calendarSelect(String calendarId, String calendarName) async {
    _functionAdmin();
    _b.calendars[churchId] = CalendarSettings(connected: true, calendarName: calendarName, calendarId: calendarId);
    _b.notify();
  }

  @override
  Future<void> calendarDisconnect() async {
    _functionAdmin();
    _b.calendars.remove(churchId);
    _b.calendarEvents.remove(churchId);
    _b.notify();
  }

  @override
  Future<List<CalendarEvent>> calendarEvents(String month) async {
    _b.functionAccess(churchId);
    if (_b.calendars[churchId]?.needsReconnect ?? false) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.reconnect);
    }
    await _b.calendarEventsHeld?.future;
    // Like Google: every event that overlaps the month, including one that
    // began the month before.
    final first = Day.parse('$month-01');
    final last = first.lastOfMonth;
    return [
      for (final e in _b.calendarEvents[churchId] ?? const <CalendarEvent>[])
        if (e.daysWithin(first, last) != null) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  @override
  Future<CalendarEvent> calendarSave(CalendarEvent event, {CalendarEvent? previous, String? restoreRosterOf}) async {
    _requireCalendarEditor();
    final list = _b.calendarEvents.putIfAbsent(churchId, () => []);
    final saved = event.id == null
        ? CalendarEvent(
            id: _b.newEventId(),
            title: event.title,
            start: event.start,
            end: event.end,
            allDay: event.allDay,
            location: event.location,
            description: event.description,
          )
        : event;
    list.removeWhere((e) => e.id == saved.id);
    list.add(saved);
    // As calendarWrite: the event's roster follows it, and undoing a delete
    // moves the cancelled roster to the event made again.
    final rosters = _b.rosters[churchId]!;
    final from = rosters[Roster.idForEvent(restoreRosterOf ?? saved.id!)];
    if (from != null && (restoreRosterOf == null) != from.forEvent!.cancelled) {
      final moved = eventRoster(
        saved,
        duties: from.duties,
        calendarId: from.forEvent!.calendarId,
      ).copyWith(saved: true);
      await _b.write(() {
        if (restoreRosterOf != null) rosters.remove(from.id);
        rosters[moved.id] = moved;
      });
    }
    return saved;
  }

  @override
  Future<void> calendarDelete(CalendarEvent event) async {
    _requireCalendarEditor();
    _b.calendarEvents[churchId]?.removeWhere((e) => e.id == event.id);
    // As calendarWrite: its roster is cancelled, kept for undo.
    final rosters = _b.rosters[churchId]!;
    final r = rosters[Roster.idForEvent(event.id!)];
    if (r != null) {
      await _b.write(
        () => rosters[r.id] = r.copyWith(forEvent: r.forEvent!.copyWith(cancelled: true)),
      );
    }
  }

  @override
  Future<PhotoQuota> photoQuota() async {
    _b.functionAccess(churchId);
    return PhotoQuota(
      remaining: max(0, _b.photoLimit - (_b.photosUsed[churchId] ?? 0)),
      limit: _b.photoLimit,
      platformOpen: _b.photoPlatformOpen,
    );
  }

  @override
  Future<List<dynamic>> recognizeRoster(String serviceType, List<PhotoInput> images) async {
    _b.functionAccess(
      churchId,
      allowed: (me) => _b.services[churchId]!.ids.contains(serviceType) && me.canEditRosters(serviceType),
    );
    if (images.any((i) => i.bytes.length > _photoMaxBytes)) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.tooLarge);
    }
    if (!_b.photoPlatformOpen) throw const CloudException(CloudErrorCode.quotaExceeded, reason: CloudReason.platform);
    final used = _b.photosUsed[churchId] ?? 0;
    if (used >= _b.photoLimit) throw const CloudException(CloudErrorCode.quotaExceeded, reason: CloudReason.church);
    _b.photosUsed[churchId] = used + 1;
    return _b.recognized;
  }
}

/// The most a photo can be: MAX_IMAGE_BYTES in functions/src/photo.ts.
const _photoMaxBytes = 2 * 1024 * 1024;

/// Invites must expire sooner than this (firestore.rules).
const _inviteMax = Duration(days: 31);

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final _random = Random();
const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String _randomCode() => List.generate(
  8,
  (_) => _alphabet[_random.nextInt(_alphabet.length)],
).join();

class _Platform implements PlatformData {
  _Platform(this._b);
  final MemoryBackend _b;

  @override
  Stream<Funding?> funding() => _b.watch(() => _b.funding);
}

class MemoryCloud implements CloudApi {
  MemoryCloud(this._b);

  final MemoryBackend _b;

  final loggedErrors = <String>[];
  final stats = <DailyStats>[];

  @override
  Future<String> createChurch(String name) async {
    final user = _b.auth.currentUser;
    if (user == null || !user.verified) {
      throw const CloudException(CloudErrorCode.unverifiedEmail);
    }
    name = _text(name, TextLimits.churchName);
    final key = nameKey(name);
    if (_b.churches.values.any((c) => nameKey(c.name) == key)) {
      throw const CloudException(CloudErrorCode.duplicateName);
    }
    final cid = _b.addChurch(name);
    _b.setServices(cid, defaultServices);
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
  Future<Invite> previewInvite(String code) async => _invite(code);

  @override
  Future<String> invitedChurchName(String code) async => _invite(code).churchName;

  @override
  Future<String> redeemInvite(String code) async {
    final user = _b.auth.currentUser;
    if (user == null) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    final invite = _invite(code);
    final cid = invite.churchId;
    if (_b.memberOf(cid, user.uid) == null) {
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

  /// Churches where [uid] is the only admin.
  List<Church> soleAdminChurches(String uid) => [
    for (final entry in _b.members.entries)
      if (entry.value[uid]?.isAdmin ?? false)
        if (entry.value.values.where((m) => m.isAdmin).length == 1)
          if (_b.churches[entry.key]!.status != ChurchStatus.deleted) _b.churches[entry.key]!,
  ];

  @override
  Future<void> deleteAccount() async {
    final uid = _b.auth.currentUser?.uid;
    if (uid == null) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    final blocking = soleAdminChurches(uid);
    if (blocking.isNotEmpty) {
      throw CloudException(CloudErrorCode.lastAdmin, churches: [for (final c in blocking) c.name]);
    }
    for (final m in _b.members.values) {
      m.remove(uid);
    }
    _b.users.remove(uid);
    _b.notify();
    _b.auth.deleteCurrent();
  }

  @override
  Future<String> uploadMoveFile(List<int> bytes) async {
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

  /// The church is made as [createChurch] makes it; everyone in the
  /// scripted preview but [me] becomes a pending member.
  @override
  Future<String> moveCommit(String path, {required String churchName, String? me}) async {
    final m = _readMove(path);
    final cid = await createChurch(churchName);
    final uid = _b.auth.currentUser!.uid;
    for (final p in m.people) {
      if (p.id == me) _b.members[cid]![uid] = _b.members[cid]![uid]!.copyWith(name: p.name);
    }
    _b.pendingMembers[cid] = {
      for (final p in m.people)
        if (p.id != me) p.id: PendingMember(id: p.id, name: p.name, email: p.email),
    };
    _b.moveFiles.remove(path);
    _b.notify();
    return cid;
  }

  @override
  Future<List<PendingClaim>> pendingClaims() async {
    final user = _b.auth.currentUser;
    if (user == null || !user.verified) return const [];
    final email = user.email.trim().toLowerCase();
    return [
      for (final MapEntry(key: cid, value: pending) in _b.pendingMembers.entries)
        if (_b.churches[cid]?.isActive ?? false)
          for (final p in pending.values)
            if (p.email.trim().toLowerCase() == email)
              PendingClaim(churchId: cid, churchName: _b.churches[cid]!.name, pendingId: p.id, name: p.name),
    ];
  }

  @override
  Future<String> claimPending(String churchId, String pendingId) async {
    final user = _b.auth.currentUser;
    if (user == null || !user.verified) throw const CloudException(CloudErrorCode.unverifiedEmail);
    final existing = _b.functionAccess(churchId, anyone: true);
    final p = _b.pendingMembers[churchId]?[pendingId];
    if (p == null) {
      // Claimed already (a double tap, a retry): fine if it was by them.
      if (existing != null) return churchId;
      throw const CloudException(CloudErrorCode.notFound);
    }
    if (p.email.trim().toLowerCase() != user.email.trim().toLowerCase()) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    _b.members[churchId]![user.uid] = existing != null
        ? _absorb(existing, p)
        : Member(
            uid: user.uid,
            name: p.name,
            email: user.email,
            role: p.role,
            groups: p.groups,
            zones: p.zones,
            joinedAt: _b.clock(),
          );
    _repoint(_b, churchId, pendingId, user.uid);
    _b.pendingMembers[churchId]!.remove(pendingId);
    _b.notify();
    return churchId;
  }

  @override
  Future<ChurchPreview> churchPreview(String churchId) async {
    final c = _b.churches[churchId];
    if (c == null || !c.isActive) throw const CloudException(CloudErrorCode.notFound);
    return ChurchPreview(id: c.id, name: c.name, logoUrl: c.logoUrl);
  }

  void _requireOperator() {
    if (!_b.auth.operators.contains(_b.auth.currentUser?.uid)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  @override
  Future<List<ChurchSummary>> adminSearchChurches(String query) async {
    _requireOperator();
    return [
      for (final c in _b.churches.values)
        if (matchesSearch(c.name, query) || c.id == query.trim())
          ChurchSummary(
            id: c.id,
            name: c.name,
            status: c.status,
            memberCount: _b.members[c.id]!.length,
            admins: [
              for (final m in _b.members[c.id]!.values)
                if (m.isAdmin) m,
            ],
          ),
    ];
  }

  @override
  Future<void> adminRenameChurch(String churchId, String name) async {
    _requireOperator();
    name = _text(name, TextLimits.churchName);
    final key = nameKey(name);
    if (_b.churches.values.any(
      (c) => c.id != churchId && nameKey(c.name) == key,
    )) {
      throw const CloudException(CloudErrorCode.duplicateName);
    }
    _b.churches[churchId] = _b.churches[churchId]!.copyWith(name: name);
    _b.notify();
  }

  @override
  Future<List<Member>> adminChurchMembers(String churchId) async {
    _requireOperator();
    return _b.members[churchId]!.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<void> adminTransferAdmin(String churchId, String uid) async {
    _requireOperator();
    final m = _b.memberOf(churchId, uid);
    if (m == null) throw const CloudException(CloudErrorCode.unknown);
    _b.members[churchId]![uid] = m.copyWith(role: Role.admin);
    _b.notify();
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
    return stats.take(days).toList();
  }

  @override
  Future<FundingOverview> adminFunding() async {
    _requireOperator();
    return FundingOverview(costs: List.of(_b.fundingCosts), months: const [], funding: _b.funding);
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
  Future<void> logError({
    required String message,
    required String stack,
    String? churchId,
  }) async => loggedErrors.add(message);
}

/// Points [cid]'s rosters at [uid] instead of pending member [pid].
void _repoint(MemoryBackend b, String cid, String pid, String uid) {
  final rosters = b.rosters[cid]!;
  for (final MapEntry(:key, :value) in rosters.entries.toList()) {
    rosters[key] = value.copyWith(
      duties: [
        for (final d in value.duties)
          d.copyWith(uids: {for (final e in d.uids.entries) e.key: e.value == pid ? uid : e.value}),
      ],
    );
  }
}

/// [value] trimmed, if it is 1 to [max] characters; what `text()` in
/// functions/src/common.ts takes.
String _text(String value, int max) {
  final t = value.trim();
  if (t.isEmpty || !withinTextLimit(t, max)) throw const CloudException(CloudErrorCode.unknown);
  return t;
}

/// A webhook secret the admin typed, as functions/src/webhook.ts takes it.
void _checkSecret(String? secret) {
  if (secret != null && (secret.length < Limits.webhookSecretMin || secret.length > Limits.webhookSecretMax)) {
    throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.secret);
  }
}

/// [m] with the groups and zones of pending member [p] added.
Member _absorb(Member m, PendingMember p) => m.copyWith(
  groups: {...m.groups, ...p.groups},
  zones: [
    for (final type in {...m.zoneTypes, for (final z in p.zones) z.serviceType})
      Zone(
        serviceType: type,
        duties: {
          for (final z in [...m.zones, ...p.zones])
            if (z.serviceType == type) ...z.duties,
        }.toList(),
      ),
  ],
);

/// The services a new church starts with. The Cloud Function seeds the same
/// list (functions/src/church.ts).
const defaultServices = [
  Service(
    id: 'sunday',
    name: '主日崇拜',
    weekday: DateTime.sunday,
    duties: ['司會', '敬拜', '司琴', '音控', '投影', '招待'],
    events: [
      EventTag(name: '聖餐', color: 0),
      EventTag(name: '浸禮', color: 4),
    ],
  ),
];
