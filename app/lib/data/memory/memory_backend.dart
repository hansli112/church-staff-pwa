import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;

import '../../core/languages.dart';
import '../../domain/day.dart';
import '../../domain/event_roster.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../domain/staff_order.dart';
import '../../domain/text.dart';
import '../backend.dart';
import '../connectivity.dart';

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
  final TransportConnectivity connectivity = TransportConnectivity();

  /// Whether the simulated network reaches the backend. What the app last
  /// observed ([connectivity]) can lag behind it, as on a phone.
  bool _network = true;

  void setOnline(bool online) {
    _network = online;
    connectivity.observe(online);
  }

  /// Like a real request: refused while the network is down, and a reply
  /// tells the app it is online again.
  void requireNetwork() {
    if (!_network) {
      connectivity.observe(false);
      throw offlineReadOnly;
    }
    connectivity.observe(true);
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

  /// The oldest store builds still allowed to run.
  MinimumBuilds minimumBuilds = const MinimumBuilds();

  /// The operator's cost list.
  List<CostItem> fundingCosts = [];

  /// Scripted: what the backend publishes once the operator changes the
  /// costs. Null leaves [funding] as it is.
  Funding Function(List<CostItem> costs)? publishFunding;

  /// 線上支持 payments by order number, and those the operator took off.
  final onlinePayments = <String, ({int amount, String month})>{};
  final refundedOnline = <String>{};

  final churches = <String, Church>{};
  final members = <String, Map<String, Member>>{};
  final services = <String, ServiceSettings>{};

  /// settings/ministries per church (#82); none until an admin makes one.
  final ministries = <String, MinistrySettings>{};

  /// churches/{cid}/smallGroups per church (#85), by id.
  final smallGroups = <String, Map<String, SmallGroupDetails>>{};

  /// 回報人數 per church and group key (#85).
  final attendance = <String, Map<String, AttendanceRecord>>{};
  var _smallGroupIds = 0;
  final rosters = <String, Map<String, Roster>>{};
  final staffOrders = <String, Map<String, StaffOrder>>{};
  final invites = <String, Invite>{};
  final users = <String, UserProfile>{};
  final calendars = <String, CalendarSettings>{};

  /// What the Google account offers to pick from (calendarList).
  List<CalendarChoice> calendarChoices = const [
    (id: 'cal-1', name: '教會行事曆', timeZone: 'Asia/Taipei'),
    (id: 'cal-2', name: '青年行事曆', timeZone: 'Asia/Taipei'),
  ];
  final churchLinks = <String, ChurchLink>{};
  final linkContents = <String, LinkContent>{};

  /// Pending members per church, by ID.
  final pendingMembers = <String, Map<String, PendingMember>>{};

  /// The rosters a move recorded naming each pending member, per church:
  /// the only days a claim or a merge points at the member instead.
  final pendingRosterIds = <String, Map<String, List<String>>>{};

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

  /// One explicit source-fetch reply, used by the next set/retry operation.
  LinkSourceResult? nextLinkResult;

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

  /// Scripted: while set, saving an event waits for this to complete, as
  /// on a slow network.
  Completer<void>? calendarSaveHeld;

  /// Scripted: while set, previewing an invite waits for this to complete,
  /// as on a slow network.
  Completer<void>? invitePreviewHeld;

  /// Scripted: while set, the back office's stats and costs wait for this
  /// to complete, as on a slow network.
  Completer<void>? backOfficeReadsHeld;

  /// Scripted: while set, an account's memberships deliver nothing until
  /// this completes, as on a slow network.
  Completer<void>? membershipsHeld;

  /// Scripted: photos used this month per church, the limit, whether the
  /// platform's budget is left, and what recognition returns.
  final photosUsed = <String, int>{};
  int photoLimit = Limits.photosPerMonth;
  bool photoPlatformOpen = true;
  List<dynamic> recognized = const [];

  /// Scripted: photo recognition answers once this completes.
  Future<void>? recognizing;

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
    final release = connectivity.beginWrite();
    try {
      requireNetwork();
      final uid = auth.currentUser?.uid;
      if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
      requireNetwork();
      if (auth.currentUser?.uid != uid) throw const CloudException(CloudErrorCode.permissionDenied);
      final failure = failNextWrite;
      if (failure != null) {
        failNextWrite = null;
        throw failure;
      }
      change();
      notify();
    } finally {
      release();
    }
  }

  @override
  ChurchData church(String churchId) => MemoryChurchData(this, churchId);

  /// What pages have warmed up, oldest first. Nothing here needs starting.
  final warmedUp = <WarmUp>[];

  @override
  void warmUp(WarmUp what) => warmedUp.add(what);

  // Seeding helpers for tests and the demo.

  String addChurch(
    String name, {
    String? id,
    ChurchStatus status = ChurchStatus.active,
    ChurchTimeZone timeZone = ChurchTimeZone.fallback,
  }) {
    final cid = id ?? 'c${churches.length + 1}';
    churches[cid] = Church(id: cid, name: name, status: status, timeZone: timeZone);
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

  /// A member moved from self-host who has not signed in yet, named on the
  /// rosters [rosterIds] (what a move records).
  void addPending(String cid, PendingMember pending, {List<String> rosterIds = const []}) {
    (pendingMembers[cid] ??= {})[pending.id] = pending;
    (pendingRosterIds[cid] ??= {})[pending.id] = rosterIds;
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
    requireNetwork();
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

  int _calendarRevision = 0;

  /// Simulates Google Calendar's OAuth callback for [cid].
  void connectCalendar(String cid, {String? calendarName, String? calendarId}) {
    calendars[cid] = CalendarSettings(
      connected: true,
      calendarName: calendarName,
      calendarId: calendarName == null ? null : (calendarId ?? 'cal-$cid'),
      revision: 'memory:${++_calendarRevision}',
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

  /// Accounts by their own email. [password] is empty when they have none.
  final _accounts = <String, ({String uid, String password, bool verified, String name})>{};

  /// The Google account each account signs in with, by the account's own
  /// email: that same email, or a linked one.
  final _google = <String, String>{};
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
    final signIns = [
      if (a.password.isNotEmpty) SignIn(SignInMethod.password, email),
      if (_google[email] case final google?) SignIn(SignInMethod.google, google),
      if (appleIds[email] case final apple?) SignIn(SignInMethod.apple, apple),
    ];
    final vouched = signIns.any((s) => s.vouches && s.email == email);
    return AuthUser(
      uid: a.uid,
      email: email,
      emailVerified: a.verified || vouched,
      displayName: a.name,
      usesPassword: !vouched,
      signIns: signIns,
    );
  }

  /// Signs in [email] directly, creating the account if needed.
  AuthUser signInAs(
    String email, {
    String? uid,
    String name = '',
    bool verified = true,
  }) {
    if (!_accounts.containsKey(email)) {
      _accounts[email] = (uid: uid ?? 'u${_next++}', password: '', verified: verified, name: name);
      _google[email] = email;
    }
    final user = _user(email);
    _set(user);
    return user;
  }

  @override
  Future<void> signInWithGoogle() async {
    final email = googleAccount;
    if (email == null) throw const AuthException(AuthErrorCode.cancelled);
    // Linked to an account under another email: that account.
    final linked = _googleOwner(email);
    if (linked != null) return _signedIn(linked);
    final existing = _accounts[email];
    // One account per email: Google takes over a password account.
    _accounts[email] = (
      uid: existing?.uid ?? 'u${_next++}',
      password: existing?.password ?? '',
      verified: true,
      name: existing?.name ?? email.split('@').first,
    );
    _google[email] = email;
    _signedIn(email);
  }

  /// The account [google] signs in to, if any.
  String? _googleOwner(String google) => _google.entries.where((e) => e.value == google).firstOrNull?.key;

  @override
  Future<void> linkGoogle() async {
    final me = _current?.email;
    if (me == null) return;
    final email = googleAccount;
    if (email == null) throw const AuthException(AuthErrorCode.cancelled);
    final owner = _googleOwner(email) ?? (_accounts.containsKey(email) ? email : null);
    if (owner != null && owner != me) throw const AuthException(AuthErrorCode.credentialInUse);
    _google[me] = email;
    _set(_user(me));
  }

  @override
  Future<void> linkApple() async {
    final me = _current?.email;
    if (me == null) return;
    final email = appleAccount;
    if (email == null) throw const AuthException(AuthErrorCode.cancelled);
    final owner = _appleOwner(email) ?? (_accounts.containsKey(email) ? email : null);
    if (owner != null && owner != me) throw const AuthException(AuthErrorCode.credentialInUse);
    appleIds[me] = email;
    _set(_user(me));
  }

  @override
  Future<void> unlink(SignInMethod method) async {
    final me = _current?.email;
    if (me == null) return;
    switch (method) {
      case SignInMethod.password:
        setPassword(me, '');
      case SignInMethod.google:
        _google.remove(me);
      case SignInMethod.apple:
        appleIds.remove(me);
    }
    _set(_user(me));
  }

  @override
  bool offersApple = false;

  /// Email of the Apple ID the next Apple sign-in uses; null closes Apple's
  /// sheet.
  String? appleAccount;

  /// The name Apple shares the first time; null when the person hides it.
  String? appleName;

  /// The Apple account each account signs in with, by the account's own email:
  /// that same email, or a linked one.
  final appleIds = <String, String>{};

  /// The account [apple] signs in to, if any.
  String? _appleOwner(String apple) => appleIds.entries.where((e) => e.value == apple).firstOrNull?.key;

  /// Emails whose Apple tokens [prepareToDelete] revoked.
  final appleRevoked = <String>[];

  /// An Apple sign-in waiting to be linked to whichever account signs in
  /// next, as Firebase keeps the pending credential.
  bool _applePending = false;

  @override
  Future<void> signInWithApple() async {
    final email = appleAccount;
    if (email == null) throw const AuthException(AuthErrorCode.cancelled);
    // Linked to an account under another email: that account.
    final linked = _appleOwner(email);
    if (linked != null) return _signedIn(linked);
    if (_accounts.containsKey(email)) {
      // One account per email, and Apple is not a trusted provider for
      // other addresses: Firebase refuses until the account links Apple.
      _applePending = true;
      throw AuthException(AuthErrorCode.needsLink, email);
    }
    _accounts[email] = (uid: 'u${_next++}', password: '', verified: true, name: appleName ?? email.split('@').first);
    appleIds[email] = email;
    _signedIn(email);
  }

  /// Signs [email] in, linking a pending Apple sign-in to it.
  void _signedIn(String email) {
    if (_applePending) {
      _applePending = false;
      // As Firebase: one Apple account per account; one already linked stays.
      appleIds.putIfAbsent(email, () => appleAccount!);
    }
    _set(_user(email));
  }

  /// Gives [email]'s account a password, as if set on another device.
  void setPassword(String email, String password) {
    final a = _accounts[email]!;
    _accounts[email] = (uid: a.uid, password: password, verified: a.verified, name: a.name);
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    final a = _accounts[email.trim()];
    if (a == null || a.password.isEmpty || a.password != password) {
      throw const AuthException(AuthErrorCode.invalidCredential);
    }
    _signedIn(email.trim());
  }

  @override
  Future<void> registerWithEmail(
    String name,
    String email,
    String password,
    AppLanguage language,
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
    _accounts[email] = (uid: 'u${_next++}', password: password, verified: false, name: name);
    _set(_user(email));
    emailLanguages.add(language);
  }

  int verificationEmailsSent = 0;
  final resetEmails = <String>[];

  /// The language of every email sent: verifications, the one on
  /// registering included, and password resets.
  final emailLanguages = <AppLanguage>[];

  @override
  Future<void> sendEmailVerification(AppLanguage language) async {
    verificationEmailsSent++;
    emailLanguages.add(language);
  }

  @override
  Future<void> sendPasswordReset(String email, AppLanguage language) async {
    resetEmails.add(email);
    emailLanguages.add(language);
  }

  /// Marks [email] verified, as if its owner clicked the link.
  void verify(String email) {
    final a = _accounts[email]!;
    _accounts[email] = (uid: a.uid, password: a.password, verified: true, name: a.name);
  }

  @override
  Future<void> reload() async {
    final email = _current?.email;
    if (email != null && _accounts.containsKey(email)) _set(_user(email));
  }

  @override
  Future<void> signOut() async => _set(null);

  @override
  Future<void> prepareToDelete() async {
    final email = _current?.email;
    final apple = appleIds[email];
    if (email == null || apple == null) return;
    if (appleAccount != apple) throw const AuthException(AuthErrorCode.cancelled);
    appleRevoked.add(email);
  }

  /// uids that hold the platform operator claim.
  final operators = <String>{};

  @override
  Future<bool> isOperator() async => operators.contains(_current?.uid);

  void deleteCurrent() {
    final email = _current?.email;
    if (email != null) {
      _accounts.remove(email);
      _google.remove(email);
      appleIds.remove(email);
    }
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
    final old = _b.users[profile.uid];
    await _b.write(
      () => _b.users[profile.uid] = profile.copyWith(appLocale: old?.appLocale, photoAiConsent: old?.photoAiConsent),
    );
  }

  @override
  Future<void> agreeToPhotoAi(String uid) async {
    final p = _b.users[uid];
    if (_b.auth.currentUser?.uid != uid || p == null) throw const CloudException(CloudErrorCode.permissionDenied);
    await _b.write(() => _b.users[uid] = p.copyWith(photoAiConsent: true));
  }

  @override
  Future<void> setAppLocale(String uid, String tag) async {
    // As firestore.rules: only on one's own profile, and a short tag.
    final p = _b.users[uid];
    if (_b.auth.currentUser?.uid != uid || p == null || tag.length > Limits.appLocale) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    await _b.write(() => _b.users[uid] = p.copyWith(appLocale: tag));
  }

  @override
  Future<void> ensure(UserProfile profile) async {
    if (!_b.connectivity.online && _b.auth.currentUser?.uid == profile.uid && _b.users.containsKey(profile.uid)) return;
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
  Stream<List<Membership>> watchMine(String uid) {
    final mine = _b.watch(
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
    final held = _b.membershipsHeld;
    if (held == null) return mine;
    return Stream.fromFuture(held.future).asyncExpand((_) => mine);
  }
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
    if (!_b.services[churchId]!.ids.contains(type) || !me.canEditRosters(type)) {
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
  /// and its group's 負責人 (the saved group; a new one's as given). One
  /// never turns into the other, and a cancelled event's is the backend's.
  void _requireRosterWrite(Roster r) {
    final saved = _b.rosters[churchId]![r.id];
    if (saved != null && saved.isEvent != r.isEvent) throw const CloudException(CloudErrorCode.permissionDenied);
    if (!r.isEvent) return _requireRosterEditor(r.type);
    _requireEventRosterEditor((saved ?? r).forEvent!.group);
    if (saved != null && saved.forEvent!.group != r.forEvent!.group) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
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
    await _b.write(() {
      _b.pendingMembers[churchId]?.remove(id);
      _b.pendingRosterIds[churchId]?.remove(id);
    });
  }

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

  @override
  Stream<List<SmallGroupDetails>> smallGroups() => _b.watch(() {
    _requireMember();
    return (_b.smallGroups[churchId] ?? const {}).values.toList();
  }, equals: _sameList);

  /// As functions/src/smallGroups.ts.
  @override
  Future<String> saveSmallGroup(SmallGroupDetails group, {List<String>? leads}) async {
    final me = _b.functionAccess(churchId)!;
    final groups = _b.smallGroups.putIfAbsent(churchId, () => {});
    final was = group.id.isEmpty ? null : groups[group.id];
    if (group.id.isNotEmpty && was == null) throw const CloudException(CloudErrorCode.notFound);
    // Its 小組長 set when it meets, and nothing else.
    final scheduling =
        was != null &&
        leads == null &&
        group.name == was.name &&
        group.service == was.service &&
        me.leadSmallGroups.contains(was.id);
    if (!scheduling && !me.mayEditSmallGroup(was?.service, group.service)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    if (_b.services[churchId]!.byId(group.service) == null) throw const CloudException(CloudErrorCode.unknown);
    // A day it meets: on its weekday.
    if (group.startsOn case final start? when group.weekday == null || start.weekday != group.weekday) {
      throw const CloudException(CloudErrorCode.unknown);
    }
    final name = group.name.trim();
    if (name.isEmpty || !withinTextLimit(name, TextLimits.profileName)) {
      throw const CloudException(CloudErrorCode.unknown);
    }
    final members = _b.members[churchId]!;
    if (leads != null && leads.any((u) => members[u] == null)) throw const CloudException(CloudErrorCode.notFound);
    final id = group.id.isEmpty ? 'sg${++_b._smallGroupIds}' : group.id;
    await _b.write(() {
      groups[id] = SmallGroupDetails(
        id: id,
        name: name,
        service: group.service,
        weekday: group.weekday,
        every: group.weekday == null ? 1 : group.every,
        startsOn: group.weekday == null ? null : group.startsOn,
      );
      if (leads == null) return;
      for (final m in [...members.values]) {
        members[m.uid] = m.withSmallGroupLead(id, lead: leads.contains(m.uid));
      }
    });
    return id;
  }

  @override
  Future<void> deleteSmallGroup(String id) async {
    final me = _b.functionAccess(churchId)!;
    final was = _b.smallGroups[churchId]?[id];
    if (was == null) throw const CloudException(CloudErrorCode.notFound);
    if (!me.mayEditSmallGroup(was.service, null)) throw const CloudException(CloudErrorCode.permissionDenied);
    await _b.write(() {
      _b.smallGroups[churchId]!.remove(id);
      final members = _b.members[churchId]!;
      for (final m in [...members.values]) {
        if (!m.leadSmallGroups.contains(id) && !m.smallGroups.contains(id)) continue;
        members[m.uid] = m.withSmallGroupLead(id, lead: false).copyWith(smallGroups: {...m.smallGroups}..remove(id));
      }
    });
  }

  /// The service of the 小組 that group [key] is, for who may see it.
  String? _smallGroupService(String key) => switch (ChurchGroup.parse(key)) {
    SmallGroup(:final id) => _b.smallGroups[churchId]?[id]?.service,
    _ => null,
  };

  @override
  Stream<AttendanceRecord> attendance(String key) => _b.watch(() {
    if (!_b.requireMember(churchId).readsAttendance(key, smallGroupService: _smallGroupService(key))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    return _b.attendance[churchId]?[key] ?? const AttendanceRecord();
  });

  void _requireAttendanceWriter(String key) {
    if (!_b.requireMember(churchId).writesAttendance(key, smallGroupService: _smallGroupService(key))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }

  @override
  Future<void> setAttendance(String key, Day day, AttendanceDay? value) async {
    _requireAttendanceWriter(key);
    if (value != null &&
        !value.none &&
        (value.count! < 0 || value.count! > 100000 || !withinTextLimit(value.note, TextLimits.attendanceNote))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    await _b.write(() {
      final all = _b.attendance.putIfAbsent(churchId, () => {});
      final was = all[key] ?? const AttendanceRecord();
      all[key] = AttendanceRecord(
        pauses: was.pauses,
        days: {...was.days, day: ?value}..removeWhere((d, _) => d == day && value == null),
      );
    });
  }

  @override
  Future<void> setAttendancePauses(String key, List<AttendancePause> pauses) async {
    _requireAttendanceWriter(key);
    if (pauses.length > 50) throw const CloudException(CloudErrorCode.permissionDenied);
    await _b.write(() {
      final all = _b.attendance.putIfAbsent(churchId, () => {});
      all[key] = AttendanceRecord(pauses: pauses, days: (all[key] ?? const AttendanceRecord()).days);
    });
  }

  @override
  Future<void> setAttendanceSince(Day? since) async {
    _requireAdmin();
    await _b.write(() => _b.churches[churchId] = _b.churches[churchId]!.copyWith(attendanceSince: () => since));
  }

  @override
  Future<void> compareAndSetMinistries({required List<Ministry> before, required List<Ministry> after}) async {
    _requireAdmin();
    await _b.write(() {
      final current = _b.ministries[churchId] ?? const MinistrySettings();
      if (!listEquals(current.ministries, before)) throw const CloudException(CloudErrorCode.conflict);
      _b.ministries[churchId] = current.withMinistries(after);
    });
  }

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
  Future<List<Roster>> pastRosters({required Day from, required Day before}) async {
    _requireMember();
    return [
      for (final r in _b.rosters[churchId]!.values)
        if (!r.day.isBefore(from) && r.day.isBefore(before)) r,
    ];
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
  Future<void> compareAndSetRosters(RosterChange change) async {
    final RosterChange(:staffOrder, :serviceChange) = change;
    final uid = _uid;
    await _b.write(() {
      if (_uid != uid) throw const CloudException(CloudErrorCode.permissionDenied);
      _requireMember();
      final saved = _b.rosters[churchId]!;
      for (final id in change.before.keys) {
        if (!change.expects(id, saved[id])) {
          throw const CloudException(CloudErrorCode.conflict);
        }
      }
      if (staffOrder case final order?) {
        _requireRosterEditor(order.serviceType);
        if ((_b.staffOrders[churchId]![order.serviceType] ?? StaffOrder()) != order.before) {
          throw const CloudException(CloudErrorCode.conflict);
        }
      }
      if (serviceChange case final service?) {
        _requireAdmin();
        if (_b.services[churchId]!.byId(service.before.id) != service.before) {
          throw const CloudException(CloudErrorCode.conflict);
        }
      }
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
      if (staffOrder case final order?) _b.staffOrders[churchId]![order.serviceType] = order.after;
      if (serviceChange case final service?) {
        final settings = _b.services[churchId]!;
        _b.services[churchId] = settings.withServices([
          for (final s in settings.services) s.id == service.before.id ? service.after : s,
        ]);
      }
    });
  }

  @override
  Future<void> compareAndSetLedDuties(RosterChange change) async {
    if (change.staffOrder != null || change.serviceChange != null) throw ArgumentError('only rosters');
    final uid = _uid;
    await _b.write(() {
      // As functions/src/ledDuties.ts: compared first, then only the duties
      // the caller's 事工 lead.
      if (_uid != uid) throw const CloudException(CloudErrorCode.permissionDenied);
      final me = _b.requireMember(churchId);
      final ministries = (_b.ministries[churchId] ?? const MinistrySettings()).ministries;
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
        final roles = me.ledDuties(ministries, day.isEvent ? null : day.type);
        if (!mayChangeLedDuties(roles, was, next)) throw const CloudException(CloudErrorCode.permissionDenied);
        if (was == null && !day.isEvent && !_b.services[churchId]!.ids.contains(day.type)) {
          throw const CloudException(CloudErrorCode.unknown);
        }
      }
      for (final entry in change.after.entries) {
        saved[entry.key] = entry.value!.copyWith(saved: true);
      }
    });
  }

  @override
  Future<void> compareAndSetServiceList({required List<Service> before, required List<Service> after}) async {
    _requireAdmin();
    if (after.isEmpty || after.length > Limits.services) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    await _b.write(() {
      final settings = _b.services[churchId]!;
      if (!listEquals(settings.services, before)) throw const CloudException(CloudErrorCode.conflict);
      _b.services[churchId] = settings.withServices(after);
    });
  }

  @override
  Future<void> compareAndSetService({
    required Service before,
    required Service after,
    ({String from, String to})? dutyRename,
  }) async {
    if (before.id != after.id) throw ArgumentError('service id cannot change');
    await _b.write(() {
      _requireAdmin();
      final settings = _b.services[churchId]!;
      if (settings.byId(before.id) != before) throw const CloudException(CloudErrorCode.conflict);
      if (dutyRename case final rename?) {
        if (!validDutyRename(before: before.duties, after: after.duties, from: rename.from, to: rename.to)) {
          throw const CloudException(CloudErrorCode.unknown);
        }
        final orders = _b.staffOrders[churchId]!;
        final order = orders[before.id];
        if (order?.rankingsByRole.containsKey(rename.to) ?? false) throw const CloudException(CloudErrorCode.conflict);
        bool affected(List<Zone> zones) =>
            zones.any((zone) => zone.serviceType == before.id && zone.duties.contains(rename.from));
        final changedMembers = _b.members[churchId]!.values.where((member) => affected(member.zones)).length;
        final changedPending = (_b.pendingMembers[churchId]?.values ?? const <PendingMember>[])
            .where((member) => affected(member.zones))
            .length;
        if (1 + changedMembers + changedPending + ((order?.rankingsByRole.containsKey(rename.from) ?? false) ? 1 : 0) >
            RosterChange.maxWrites) {
          throw const CloudException(CloudErrorCode.quotaExceeded, reason: CloudReason.tooManyChanges);
        }
        List<Zone> renamed(List<Zone> zones) => [
          for (final zone in zones)
            zone.serviceType == before.id
                ? zone.copyWith(
                    duties: {for (final duty in zone.duties) duty == rename.from ? rename.to : duty}.toList(),
                  )
                : zone,
        ];
        final members = _b.members[churchId]!;
        for (final entry in members.entries.toList()) {
          if (affected(entry.value.zones)) members[entry.key] = entry.value.copyWith(zones: renamed(entry.value.zones));
        }
        final pending = _b.pendingMembers[churchId];
        if (pending != null) {
          for (final entry in pending.entries.toList()) {
            final member = entry.value;
            if (!affected(member.zones)) continue;
            pending[entry.key] = PendingMember(
              id: member.id,
              name: member.name,
              email: member.email,
              role: member.role,
              groups: member.groups,
              zones: renamed(member.zones),
              mutedNotifications: member.mutedNotifications,
            );
          }
        }
        if (order?.rankingsByRole.containsKey(rename.from) ?? false) {
          orders[before.id] = order!.withRolesRenamed({rename.from: rename.to});
        }
        // The 事工 that link the duty keep leading it (#82).
        if (_b.ministries[churchId] case final m?) {
          _b.ministries[churchId] = MinistrySettings(
            ids: m.ids,
            ministries: [
              for (final ministry in m.ministries)
                ministry.copyWith(
                  duties: [
                    for (final d in ministry.duties)
                      d.service == before.id && d.duty == rename.from ? MinistryDuty(d.service, rename.to) : d,
                  ],
                ),
            ],
          );
        }
      }
      _b.services[churchId] = settings.withServices([
        for (final service in settings.services) service.id == before.id ? after : service,
      ]);
    });
  }

  @override
  Future<void> compareAndSetMember({required Member before, required Member after}) async {
    if (before.uid != after.uid) throw ArgumentError('member uid cannot change');
    _requireAdmin();
    if (after.uid == _uid && !after.isAdmin) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    _checkName(after.name);
    await _b.write(() {
      final members = _b.members[churchId]!;
      final current = members[after.uid];
      if (current == null) throw const CloudException(CloudErrorCode.notFound);
      if (!current.sameAdminFields(before)) throw const CloudException(CloudErrorCode.conflict);
      // As memberToJson writes it.
      members[after.uid] = current.copyWith(
        name: after.name,
        role: after.role,
        groups: after.groups,
        zones: after.zones,
        identities: after.identities,
        ministries: after.ministries,
        smallGroups: after.smallGroups,
      );
    });
  }

  @override
  Future<void> setGroupMember(
    String uid,
    ChurchGroup group, {
    required bool member,
    List<String> duties = const [],
    List<String> smallGroups = const [],
  }) async {
    await _b.write(() {
      // As functions/src/groupMembers.ts: the group as it is now, then who
      // may move whom.
      final me = _b.requireMember(churchId);
      final members = _b.members[churchId]!;
      final service = switch (group) {
        ServiceGroup(:final id) => _b.services[churchId]!.byId(id),
        MinistryGroup() || SmallGroup() => null,
      };
      final small = switch (group) {
        SmallGroup(:final id) => _b.smallGroups[churchId]?[id],
        _ => null,
      };
      final known = switch (group) {
        ServiceGroup() => service != null,
        MinistryGroup(:final id) => (_b.ministries[churchId] ?? const MinistrySettings()).byId(id) != null,
        SmallGroup() => small != null,
      };
      if (!known) throw const CloudException(CloudErrorCode.permissionDenied);
      final them = members[uid];
      if (them == null) throw const CloudException(CloudErrorCode.notFound);
      if (!me.mayMove(them, group, service: small?.service)) {
        throw const CloudException(CloudErrorCode.permissionDenied);
      }
      if (duties.any((d) => !(service?.duties.contains(d) ?? true))) throw const CloudException(CloudErrorCode.unknown);
      members[uid] = them.inGroupAs(
        group,
        member: member,
        duties: duties.toSet().toList(),
        smallGroups: smallGroups.toSet().toList(),
      );
    });
  }

  @override
  Future<void> grantDuty(String uid, String serviceType, String duty) =>
      _changeZones(uid, (m) => m.withDuty(serviceType, duty));

  @override
  Future<void> revokeDuty(String uid, String serviceType, String duty) =>
      _changeZones(uid, (m) => m.withoutDuty(serviceType, duty));

  /// Admins: [change] applied to member [uid] as they are when written.
  Future<void> _changeZones(String uid, Member Function(Member) change) async {
    _requireAdmin();
    await _b.write(() {
      final now = _b.members[churchId]![uid];
      if (now == null) throw const CloudException(CloudErrorCode.notFound);
      _b.members[churchId]![uid] = change(now);
    });
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
  Future<void> setReminderTiming(String uid, ReminderTiming timing) async {
    if (uid != _uid) throw const CloudException(CloudErrorCode.permissionDenied);
    final m = _b.requireMember(churchId);
    await _b.write(
      () => _b.members[churchId]![uid] = m.copyWith(reminderTiming: timing),
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
    if (link == null || !link.changesSourceOf(saved)) return const LinkSourceResult();
    return _setLinkSource(link.source, link.fetchMinute);
  }

  @override
  Future<LinkSourceResult> refreshChurchLink() async {
    _functionAdmin();
    final link = _b.churchLinks[churchId];
    if (link == null) throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.noLink);
    if (link.source == null) throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.noSource);
    return _setLinkSource(link.source, link.fetchMinute, refresh: true);
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

  /// Its calendar's events are kept on the church's clock: unlike Google's,
  /// they do not move with it.
  @override
  Future<void> setTimeZone(ChurchTimeZone timeZone) async {
    _functionAdmin();
    _b.churches[churchId] = _b.churches[churchId]!.copyWith(timeZone: timeZone);
    _b.notify();
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
    _b.churches[churchId] = _deleted(_b.churches[churchId]!, _b.clock());
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
    _b.churches[churchId] = Church(
      id: c.id,
      name: c.name,
      logoUrl: c.logoUrl,
      homeName: c.homeName,
      timeZone: c.timeZone,
    );
    _b.notify();
  }

  @override
  Future<void> mergePending(String pendingId, String uid) async {
    _functionAdmin();
    final p = _b.pendingMembers[churchId]?[pendingId];
    final m = _b.memberOf(churchId, uid);
    if (p == null || m == null) throw const CloudException(CloudErrorCode.notFound);
    _b.members[churchId]![uid] = _absorb(m, p);
    _settlePending(_b, churchId, pendingId, uid);
    _b.notify();
  }

  /// The setLinkSource function.
  Future<LinkSourceResult> _setLinkSource(String? source, int fetchMinute, {bool refresh = false}) async {
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
    if (!refresh) _b.churchLinks[churchId] = next(source, fetchMinute);
    if (!changed && !refresh) {
      _b.notify();
      return const LinkSourceResult();
    }
    // A new source is fetched at once; what it gives is scripted.
    _b.linkSourceFetches.add(source);
    final scripted = _b.nextLinkResult;
    _b.nextLinkResult = null;
    final answer = scripted?.content ?? _b.linkSourceAnswers[source] ?? LinkFetchError.network;
    final now = _b.clock();
    final today = _b.churches[churchId]!.timeZone.today(now).key;
    var error = scripted?.error;
    if (scripted != null && error == null && scripted.content == null) error = LinkFetchError.badFormat;
    if (answer is LinkContent && error == null && answer.date != null && answer.date != today) {
      error = LinkFetchError.notToday;
    }
    if (answer is LinkContent && scripted != null && answer.date == null && error == null) {
      error = LinkFetchError.badFormat;
    }
    final LinkSourceResult result;
    if (answer is LinkContent && error == null) {
      _b.linkContents[churchId] = LinkContent(
        source: source,
        date: answer.date ?? today,
        title: answer.title,
        body: answer.body,
        link: answer.link,
        fetchedAt: now,
      );
      result = LinkSourceResult(content: _b.linkContents[churchId]);
    } else {
      final failed = error ?? answer as LinkFetchError;
      _b.linkContents[churchId] = LinkContent(
        source: source,
        error: failed,
        errorStatus: scripted?.status,
        errorAt: now,
      );
      result = LinkSourceResult(error: failed, status: scripted?.status);
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

  @override
  Future<Uri> calendarAuthUrl() async {
    _functionAdmin();
    return Uri.parse('https://accounts.google.com/o/oauth2/v2/auth?state=memory');
  }

  @override
  Future<List<CalendarChoice>> calendarList() async {
    _functionAdmin();
    return _b.calendarChoices;
  }

  @override
  Future<void> calendarSelect(String calendarId, String calendarName) async {
    _functionAdmin();
    _b.calendars[churchId] = CalendarSettings(
      connected: true,
      calendarName: calendarName,
      calendarId: calendarId,
      revision: 'memory:${++_b._calendarRevision}',
    );
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
    _b.requireNetwork();
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
    _requireEventWrite(() => _groupNow(event.id), event.group ?? '');
    _requireRestore(restoreRosterOf);
    await _b.calendarSaveHeld?.future;
    final saved = event.id == null
        ? CalendarEvent(
            id: _b.newEventId(),
            title: event.title,
            start: event.start,
            end: event.end,
            allDay: event.allDay,
            location: event.location,
            description: event.description,
            group: event.group,
          )
        : event;
    await _b.write(() {
      _requireEventWrite(() => _groupNow(event.id), event.group ?? '');
      _requireRestore(restoreRosterOf);
      final list = _b.calendarEvents.putIfAbsent(churchId, () => []);
      final was = list.where((e) => e.id == saved.id).firstOrNull?.group;
      list.removeWhere((e) => e.id == saved.id);
      list.add(saved);
      // A day of a recurring event given to another group: the series goes
      // with it (重複活動照系列存).
      final series = saved.recurringEventId;
      if (series != null && was != saved.group) {
        for (final (i, e) in list.indexed.toList()) {
          if (e.recurringEventId == series && e.group != saved.group) list[i] = e.copyWith(group: () => saved.group);
        }
      }
      // The roster and calendar change become visible together.
      final rosters = _b.rosters[churchId]!;
      final from = rosters[Roster.idForEvent(restoreRosterOf ?? saved.id!)];
      if (from != null && (restoreRosterOf == null) != from.forEvent!.cancelled) {
        final moved = eventRoster(
          saved,
          duties: from.duties,
          calendarId: from.forEvent!.calendarId,
        ).copyWith(saved: true);
        if (restoreRosterOf != null) rosters.remove(from.id);
        rosters[moved.id] = moved;
      }
    });
    return saved;
  }

  @override
  Future<void> calendarDelete(CalendarEvent event) async {
    _requireEventWrite(() => _groupNow(event.id), null);
    await _b.write(() {
      _requireEventWrite(() => _groupNow(event.id), null);
      _b.calendarEvents[churchId]?.removeWhere((e) => e.id == event.id);
      final rosters = _b.rosters[churchId]!;
      final r = rosters[Roster.idForEvent(event.id!)];
      if (r != null) rosters[r.id] = r.copyWith(forEvent: r.forEvent!.copyWith(cancelled: true));
    });
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
    _rosterEditorOf(serviceType);
    if (images.any((i) => i.bytes.length > Limits.photoBytes)) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.tooLarge);
    }
    if (!_b.photoPlatformOpen) throw const CloudException(CloudErrorCode.quotaExceeded, reason: CloudReason.platform);
    final used = _b.photosUsed[churchId] ?? 0;
    if (used >= _b.photoLimit) throw const CloudException(CloudErrorCode.quotaExceeded, reason: CloudReason.church);
    _b.photosUsed[churchId] = used + 1;
    await _b.recognizing;
    return _b.recognized;
  }

  /// A short stand-in for the backend's prompt, with what it is built from.
  @override
  Future<String> photoPrompt(String serviceType) async {
    _rosterEditorOf(serviceType);
    final service = _b.services[churchId]!.byId(serviceType)!;
    final names = [for (final m in _b.members[churchId]!.values) m.name];
    return '把「${service.name}」的服事表照片轉成 JSON。\n${service.duties.join('、')}\n${names.join('、')}';
  }

  /// As the backend's photo calls (access.ts `arranges`): someone who
  /// arranges any of a service the church has.
  void _rosterEditorOf(String serviceType) => _b.functionAccess(
    churchId,
    allowed: (me) =>
        _b.services[churchId]!.ids.contains(serviceType) &&
        (me.arranges((_b.ministries[churchId] ?? const MinistrySettings()).ministries, serviceType)?.isNotEmpty ??
            true),
  );
}

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

  @override
  Stream<MinimumBuilds> minimumBuilds() => _b.watch(() => _b.minimumBuilds);
}

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
    final key = nameKey(name);
    if (_b.churches.values.any((c) => nameKey(c.name) == key)) {
      throw const CloudException(CloudErrorCode.duplicateName);
    }
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
    _b.users.remove(uid);
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
    final emails = _b.auth.currentUser?.claimEmails ?? const [];
    return [
      for (final MapEntry(key: cid, value: pending) in _b.pendingMembers.entries)
        if (_b.churches[cid]?.isActive ?? false)
          for (final p in pending.values)
            if (emails.contains(p.email.trim().toLowerCase()))
              PendingClaim(churchId: cid, churchName: _b.churches[cid]!.name, pendingId: p.id, name: p.name),
    ];
  }

  @override
  Future<String> claimPending(String churchId, String pendingId) async {
    final user = _b.auth.currentUser;
    final emails = user?.claimEmails ?? const [];
    if (user == null || emails.isEmpty) throw const CloudException(CloudErrorCode.unverifiedEmail);
    final existing = _b.functionAccess(churchId, anyone: true);
    final p = _b.pendingMembers[churchId]?[pendingId];
    if (p == null) {
      // Claimed already (a double tap, a retry): fine if it was by them.
      if (existing != null) return churchId;
      throw const CloudException(CloudErrorCode.notFound);
    }
    if (!emails.contains(p.email.trim().toLowerCase())) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    _b.members[churchId]![user.uid] = existing != null
        ? _absorb(existing, p)
        : Member(
            uid: user.uid,
            name: p.name,
            email: user.email,
            role: p.role,
            groups: _claimedGroups(p),
            zones: p.zones,
            identities: _claimedLeads(p),
            mutedNotifications: p.mutedNotifications,
            joinedAt: _b.clock(),
          );
    _settlePending(_b, churchId, pendingId, user.uid);
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
    _b.requireNetwork();
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
    await _b.backOfficeReadsHeld?.future;
    return stats.take(days).toList();
  }

  @override
  Future<FundingOverview> adminFunding() async {
    _requireOperator();
    await _b.backOfficeReadsHeld?.future;
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
  }) async => loggedErrors.add(message);
}

/// Points the rosters the move recorded for pending member [pid] at [uid]
/// instead, and drops [pid]; as functions/src/claim.ts does.
void _settlePending(MemoryBackend b, String cid, String pid, String uid) {
  b.pendingMembers[cid]!.remove(pid);
  final rosters = b.rosters[cid]!;
  for (final key in b.pendingRosterIds[cid]?.remove(pid) ?? const <String>[]) {
    final value = rosters[key];
    if (value == null) continue;
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

/// A pending member's old permission groups as 身分 (#82), as
/// claimedGroups in functions/src/claim.ts: calendar-editors folds into
/// 行政; roster-editors alone, their 牧區's rosters in self-host, makes them
/// 負責人 of the services they are in.
Set<Group> _claimedGroups(PendingMember p) =>
    p.groups.contains(Group.calendarEditors) ? const {Group.rosterEditors, Group.calendarEditors} : const {};

List<Identity> _claimedLeads(PendingMember p) {
  if (p.groups.contains(Group.calendarEditors)) return const [OfficeIdentity()];
  if (!p.groups.contains(Group.rosterEditors)) return const [];
  return [
    for (final type in {for (final z in p.zones) z.serviceType}) ServiceLead(type),
  ];
}

/// [m] with the groups, zones and leads of pending member [p] added.
Member _absorb(Member m, PendingMember p) => m.copyWith(
  groups: {...m.groups, ..._claimedGroups(p)},
  identities: [
    ...m.identities,
    for (final i in _claimedLeads(p))
      if (!m.identities.contains(i)) i,
  ],
  mutedNotifications: {...m.mutedNotifications, ...p.mutedNotifications},
  zones: [
    for (final type in {...m.zoneTypes, for (final z in p.zones) z.serviceType})
      Zone(
        serviceType: type,
        duties: {
          for (final z in [...m.zones, ...p.zones])
            if (z.serviceType == type) ...z.duties,
        }.toList(),
        smallGroups: {
          for (final z in [...m.zones, ...p.zones])
            if (z.serviceType == type) ...z.smallGroups,
        }.toList(),
      ),
  ],
);

/// Someone in a self-host export, [source] their user document (null when
/// it has none), as the move makes them a pending member: what
/// mapMember in functions/src/importer.ts does
/// (testdata/church_rules.json, movedMembers).
PendingMember movedMember({
  required String id,
  required String name,
  required String email,
  Map<dynamic, dynamic>? source,
}) {
  List<String> strings(Object? values) => [
    if (values is List)
      for (final value in values)
        if (value is String) value,
  ];
  final prefs = source?['notificationPrefs'];
  final muted = prefs is Map ? strings(prefs['muted']) : const <String>[];
  return PendingMember(
    id: id,
    name: name,
    email: email,
    role: source == null
        ? Role.staff
        : Role.values.where((role) => role.name == source['role']).firstOrNull ?? Role.member,
    groups: {for (final id in strings(source?['groups'])) ?Group.byId(id)},
    zones: [
      if (source?['zones'] is List)
        for (final zone in source!['zones'] as List)
          if (zone is Map && zone['serviceType'] is String)
            Zone(
              serviceType: zone['serviceType'] as String,
              duties: strings(zone['ministries']),
              smallGroups: strings(zone['smallGroups']),
            ),
    ],
    mutedNotifications: {
      for (final kind in NotificationKind.values)
        if (muted.contains(kind.name)) kind,
      if (prefs is Map && prefs['weeklyRosterReminder'] == false) NotificationKind.reminder,
    },
  );
}

/// The services a new church starts with, in its maker's language. The
/// Cloud Function seeds the same lists (functions/src/languages.ts;
/// testdata/church_rules.json).
const defaultServices = {
  AppLanguage.zhHant: [
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
  ],
  AppLanguage.zhHans: [
    Service(
      id: 'sunday',
      name: '主日崇拜',
      weekday: DateTime.sunday,
      duties: ['领会', '敬拜主领', '司琴', '音控', '投影', '招待'],
      events: [
        EventTag(name: '圣餐', color: 0),
        EventTag(name: '浸礼', color: 4),
      ],
    ),
  ],
  AppLanguage.en: [
    Service(
      id: 'sunday',
      name: 'Sunday Service',
      weekday: DateTime.sunday,
      duties: ['Host', 'Worship Leader', 'Piano', 'Sound', 'Slides', 'Usher'],
      events: [
        EventTag(name: 'Communion', color: 0),
        EventTag(name: 'Baptism', color: 4),
      ],
    ),
  ],
  AppLanguage.ja: [
    Service(
      id: 'sunday',
      name: '主日礼拝',
      weekday: DateTime.sunday,
      duties: ['司会', '賛美リード', '奏楽', '音響', 'スライド', '受付'],
      events: [
        EventTag(name: '聖餐式', color: 0),
        EventTag(name: '洗礼式', color: 4),
      ],
    ),
  ],
  AppLanguage.ko: [
    Service(
      id: 'sunday',
      name: '주일예배',
      weekday: DateTime.sunday,
      duties: ['사회', '찬양 인도', '반주', '음향', '자막', '안내'],
      events: [
        EventTag(name: '성찬', color: 0),
        EventTag(name: '세례', color: 4),
      ],
    ),
  ],
};

/// Church [c] as deleting it leaves it, at [at].
Church _deleted(Church c, DateTime at) => Church(
  id: c.id,
  name: c.name,
  status: ChurchStatus.deleted,
  logoUrl: c.logoUrl,
  homeName: c.homeName,
  deletedAt: at,
  timeZone: c.timeZone,
  attendanceSince: c.attendanceSince,
);
