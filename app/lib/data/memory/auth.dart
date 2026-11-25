part of 'memory_backend.dart';

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
      () => _b.users[profile.uid] = profile.copyWith(
        appLocale: old?.appLocale,
        photoAiConsent: old?.photoAiConsent,
        notificationsSeen: old?.notificationsSeen,
        seenOn: old?.seenOn,
      ),
    );
  }

  @override
  Future<void> agreeToPhotoAi(String uid) async {
    final p = _b.users[uid];
    if (_b.auth.currentUser?.uid != uid || p == null) throw const CloudException(CloudErrorCode.permissionDenied);
    // As Firestore's cache: kept here at once, not waiting for the server.
    _b.users[uid] = p.copyWith(photoAiConsent: true);
    _b.notify();
  }

  @override
  Future<void> setAppLocale(String uid, String tag) async {
    // As firestore.rules: only on one's own profile, and a short tag.
    final p = _b.users[uid];
    if (_b.auth.currentUser?.uid != uid || p == null || tag.length > Limits.appLocale) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    // Read again when written: another field may be written meanwhile.
    await _b.write(() => _b.users[uid] = _b.users[uid]!.copyWith(appLocale: tag));
  }

  @override
  Future<void> markSeen(String uid, String day) async {
    // As firestore.rules: only on one's own profile, and a day.
    final p = _b.users[uid];
    if (_b.auth.currentUser?.uid != uid || p == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    await _b.write(() => _b.users[uid] = _b.users[uid]!.copyWith(seenOn: day));
  }

  @override
  Future<void> ensure(UserProfile profile) async {
    if (!_b.connectivity.online && _b.auth.currentUser?.uid == profile.uid && _b.users.containsKey(profile.uid)) return;
    _checkName(profile.name);
    await _b.write(() => _b.users.putIfAbsent(profile.uid, () => profile));
  }

  @override
  Stream<List<NotificationItem>> notifications(String uid) => _b.watch(() {
    // As firestore.rules: only their own.
    if (_b.auth.currentUser?.uid != uid) throw const CloudException(CloudErrorCode.permissionDenied);
    return [...?_b.notifications[uid]]..sort((a, b) => b.at.compareTo(a.at));
  }, equals: listEquals);

  @override
  Future<void> markNotificationsSeen(String uid, String churchId, DateTime upTo, {bool onlyForward = false}) async {
    if (onlyForward) _b.requireNetwork();
    final p = _b.users[uid];
    if (_b.auth.currentUser?.uid != uid || p == null) throw const CloudException(CloudErrorCode.permissionDenied);
    final at = DateTime.fromMillisecondsSinceEpoch(upTo.millisecondsSinceEpoch, isUtc: true);
    if (onlyForward && !(p.notificationsSeen[churchId]?.isBefore(at) ?? true)) return;
    await _b.write(() => _b.users[uid] = p.copyWith(notificationsSeen: {...p.notificationsSeen, churchId: at}));
  }
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
