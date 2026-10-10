import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/staff_order.dart';
import '../../env.dart';
import '../backend.dart';
import 'codec.dart';
import '../native_or_browser.dart';
import '../retry_refused.dart';

bool _refused(Object e) => e is FirebaseException && e.code == 'permission-denied';

/// Firestore instances whose listeners skip what the local cache answers
/// first ([FirebaseBackend.serverReads]).
final _serverReads = Expando<bool>();

/// Firestore listeners that survive being refused right after sign-in (see
/// [retryRefused]).
extension on DocumentReference<Json> {
  Stream<DocumentSnapshot<Json>> live() => _serverReads[firestore] == true
      ? retryRefused(() => snapshots(includeMetadataChanges: true), isRefused: _refused).where(_fromServer)
      : retryRefused(snapshots, isRefused: _refused);
}

extension on Query<Json> {
  Stream<QuerySnapshot<Json>> live() => _serverReads[firestore] == true
      ? retryRefused(() => snapshots(includeMetadataChanges: true), isRefused: _refused).where(_fromServer)
      : retryRefused(snapshots, isRefused: _refused);
}

bool _fromServer(Object snapshot) => switch (snapshot) {
  DocumentSnapshot(:final metadata) || QuerySnapshot(:final metadata) => !metadata.isFromCache,
  _ => true,
};

/// All Cloud Functions run in the same region as Firestore.
const functionsRegion = 'asia-east1';

class FirebaseBackend implements Backend {
  /// With [serverReads], every listener's first value is the server's
  /// answer, never the local cache's (which may be stale or another
  /// user's). For the contract tests; the app shows the cache at once.
  FirebaseBackend({
    fa.FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    bool serverReads = false,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now,
       _auth = auth ?? fa.FirebaseAuth.instance,
       _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instanceFor(region: functionsRegion),
       _storage = storage ?? FirebaseStorage.instance {
    if (serverReads) _serverReads[_db] = true;
  }

  final fa.FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  @override
  final DateTime Function() clock;

  @override
  late final AuthGateway auth = FirebaseAuthGateway(_auth);

  @override
  late final ProfileRepository profiles = _Profiles(_db);

  @override
  late final MembershipRepository memberships = _Memberships(_db);

  late final _calls = _Callables(_functions, _auth);

  @override
  late final CloudApi cloud = FirebaseCloudApi._(_calls, _storage, _auth);

  @override
  late final PlatformData platform = _Platform(_db);

  final _churches = <String, ChurchData>{};

  @override
  ChurchData church(String churchId) => _churches.putIfAbsent(
    churchId,
    () => FirestoreChurchData._(_db, _storage, _calls, clock, churchId),
  );
}

// ---------------------------------------------------------------- auth

class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway(this._auth);

  final fa.FirebaseAuth _auth;

  /// A sign-in method waiting to be linked once the user signs in the way
  /// their account already uses (account-exists-with-different-credential).
  fa.AuthCredential? _pending;

  final _reloaded = StreamController<AuthUser?>.broadcast();

  static AuthUser? _map(fa.User? u) {
    if (u == null) return null;
    final providers = u.providerData.map((p) => p.providerId).toSet();
    return AuthUser(
      uid: u.uid,
      email: u.email ?? '',
      emailVerified: u.emailVerified,
      displayName: u.displayName,
      usesPassword:
          providers.contains('password') && !providers.contains('google.com') && !providers.contains('apple.com'),
    );
  }

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> authState() {
    final controller = StreamController<AuthUser?>();
    final subs = <StreamSubscription<Object?>>[];
    controller.onListen = () {
      subs
        ..add(
          _auth.userChanges().map(_map).listen(controller.add, onError: controller.addError),
        )
        ..add(_reloaded.stream.listen(controller.add));
    };
    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  Future<void> _run(Future<fa.UserCredential> Function() signIn) async {
    try {
      final result = await signIn();
      final pending = _pending;
      if (pending != null && result.user != null) {
        _pending = null;
        try {
          await result.user!.linkWithCredential(pending);
        } on fa.FirebaseAuthException catch (e) {
          debugPrint('Linking pending credential failed: ${e.code}');
        }
      }
    } on fa.FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  AuthException _translate(fa.FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        _pending = e.credential;
        return AuthException(AuthErrorCode.needsLink, e.email);
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'web-context-canceled':
      case 'canceled':
        return const AuthException(AuthErrorCode.cancelled);
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return const AuthException(AuthErrorCode.invalidCredential);
      case 'email-already-in-use':
        return AuthException(AuthErrorCode.emailInUse, e.email);
      case 'weak-password':
        return const AuthException(AuthErrorCode.weakPassword);
      case 'invalid-email':
        return const AuthException(AuthErrorCode.invalidEmail);
      case 'too-many-requests':
        return const AuthException(AuthErrorCode.tooManyRequests);
      case 'network-request-failed':
        return const AuthException(AuthErrorCode.network);
      default:
        debugPrint('Unhandled auth error: ${e.code}');
        return const AuthException(AuthErrorCode.unknown);
    }
  }

  @override
  Future<void> signInWithGoogle() => _run(() async {
    final provider = fa.GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
    if (kIsWeb) return _auth.signInWithPopup(provider);
    Future<fa.UserCredential> browser() => _auth.signInWithProvider(provider);
    // Native: the system account picker (no browser), when the OAuth web
    // client ID is configured for this build. Otherwise the browser flow,
    // which needs no native setup.
    if (_googleServerClientId.isEmpty) return browser();
    final google = GoogleSignIn.instance;
    try {
      if (!_googleReady) {
        // iOS also needs its own client ID; Android finds its client from
        // the package name and signing certificate.
        final ios = defaultTargetPlatform == TargetPlatform.iOS;
        await google.initialize(
          clientId: ios && _googleIosClientId.isNotEmpty ? _googleIosClientId : null,
          serverClientId: _googleServerClientId,
        );
        _googleReady = true;
      }
      return await nativeOrBrowser(
        native: () async {
          final account = await google.authenticate();
          final idToken = account.authentication.idToken;
          return _auth.signInWithCredential(fa.GoogleAuthProvider.credential(idToken: idToken));
        },
        browser: browser,
        useBrowser: nativeGoogleUnavailable,
        // A signing certificate missing from the Firebase Android app looks
        // the same as a phone without a Google account, so every fallback
        // is reported.
        onFallback: (e, stack) => FirebaseCrashlytics.instance.recordError(
          e,
          stack,
          reason: 'native Google sign-in unavailable; signed in with the browser',
        ),
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const AuthException(AuthErrorCode.cancelled);
      rethrow;
    }
  });

  /// The project's OAuth web client ID, from --dart-define.
  static const _googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// The project's iOS OAuth client ID, from --dart-define.
  static const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  bool _googleReady = false;

  @override
  Future<void> signInWithEmail(String email, String password) => _run(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<void> registerWithEmail(String name, String email, String password) => _run(() async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await result.user?.updateDisplayName(name.trim());
    // Push the account with its name, so users/{uid} is created with it.
    await _auth.currentUser?.reload();
    _reloaded.add(_map(_auth.currentUser));
    await result.user?.sendEmailVerification();
    return result;
  });

  @override
  Future<void> sendEmailVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } on fa.FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fa.FirebaseAuthException catch (e) {
      // Do not reveal whether the email has an account.
      if (e.code != 'user-not-found') throw _translate(e);
    }
  }

  @override
  Future<void> reload() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    // emailVerified changes on the token; refresh it so the Cloud
    // Functions see the verified email too.
    await _auth.currentUser?.getIdToken(true);
    _reloaded.add(_map(_auth.currentUser));
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<bool> isOperator() async {
    final token = await _auth.currentUser?.getIdTokenResult();
    return token?.claims?['operator'] == true;
  }
}

// ---------------------------------------------------------------- users

class _Profiles implements ProfileRepository {
  _Profiles(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<UserProfile?> watch(String uid) =>
      _db.doc('users/$uid').live().map((s) => s.exists ? profileFromJson(uid, s.data()!) : null);

  @override
  Future<void> save(UserProfile profile) => _guard(
    () => _db.runTransaction((tx) async {
      final ref = _db.doc('users/${profile.uid}');
      final current = await tx.get(ref);
      tx.set(ref, {
        'name': profile.name,
        'email': profile.email,
        'locale': profile.locale ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (!current.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }),
  );

  @override
  Future<void> ensure(UserProfile profile) => _guard(
    () => _db.runTransaction((tx) async {
      // A transaction reads the server, not the offline cache, so a profile
      // created on another device is seen and kept.
      final ref = _db.doc('users/${profile.uid}');
      if ((await tx.get(ref)).exists) return;
      tx.set(ref, {
        'name': profile.name,
        'email': profile.email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }),
  );
}

class _Platform implements PlatformData {
  _Platform(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<Funding?> funding() =>
      _db.doc('platform/funding').live().map((s) => s.exists ? fundingFromJson(s.data()!) : null);
}

Funding fundingFromJson(Map<String, Object?> d) {
  int n(String key) => (d[key] as num?)?.round() ?? 0;
  return Funding(
    month: d['month'] as String? ?? '',
    target: n('target'),
    received: n('received'),
    carried: n('carried'),
    monthsLeft: n('monthsLeft'),
  );
}

class _Memberships implements MembershipRepository {
  _Memberships(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<List<Membership>> watchMine(String uid) => _db
      .collectionGroup('members')
      .where('uid', isEqualTo: uid)
      .live()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            if (doc.reference.parent.parent case final church?)
              Membership(
                churchId: church.id,
                member: memberFromJson(doc.id, doc.data()),
              ),
        ],
      );
}

// ---------------------------------------------------------------- church

/// Firestore and Storage for the church's data, Cloud Functions for what
/// the backend does for it. Every error leaves as a [CloudException]
/// ([_guard], [_Translated.translated]).
class FirestoreChurchData implements ChurchData {
  FirestoreChurchData._(this._db, this._storage, this._calls, this._clock, this.churchId);

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final _Callables _calls;
  final DateTime Function() _clock;

  @override
  final String churchId;

  DocumentReference<Json> get _church => _db.doc('churches/$churchId');
  CollectionReference<Json> _col(String name) => _church.collection(name);

  /// Calls function [name] for this church.
  Future<Map<String, Object?>> _call(String name, [Map<String, Object?> data = const {}]) async =>
      _asMap(await _calls.call(name, {'churchId': churchId, ...data}));

  String? _logoVersion;
  String? _logoUrl;
  Future<String>? _logoLookup;

  @override
  Stream<Church?> church() {
    late final StreamController<Church?> out;
    StreamSubscription<Church?>? sub;
    Church? latest;
    Future<String>? pending;
    var readEpoch = 0;
    var open = true;

    out = StreamController<Church?>(
      onListen: () {
        sub = _church
            .live()
            .map((snap) {
              final data = snap.data();
              latest = data == null ? null : churchFromJson(snap.id, data);
              final church = latest;
              final version = data?['logoVersion'];
              if (church == null || !church.isActive || version is! String || version.isEmpty) {
                _logoVersion = null;
                _logoUrl = null;
                _logoLookup = null;
                pending = null;
                return church;
              }
              if (version != _logoVersion) {
                _logoVersion = version;
                _logoUrl = null;
                _logoLookup = null;
              }
              if (_logoUrl == null) {
                final lookup = _logoLookup ??= Future<String>.sync(() => _storage.ref(_logoPath).getDownloadURL());
                if (pending != lookup) {
                  pending = lookup;
                  final epoch = readEpoch;
                  unawaited(
                    lookup.then(
                      (url) {
                        if (epoch != readEpoch || !open || out.isClosed || pending != lookup || _logoLookup != lookup) {
                          return;
                        }
                        _logoUrl = url;
                        if (latest case final church?) out.add(church.copyWith(logoUrl: url));
                      },
                      onError: (Object error, StackTrace stack) {
                        if (epoch != readEpoch || !open || out.isClosed || pending != lookup || _logoLookup != lookup) {
                          return;
                        }
                        // The logo is optional; metadata is already available.
                        if (error is! FirebaseException) out.addError(error, stack);
                      },
                    ),
                  );
                }
              }
              return church.copyWith(logoUrl: _logoUrl);
            })
            .listen(
              out.add,
              onError: (Object error, StackTrace stack) {
                readEpoch++;
                latest = null;
                pending = null;
                out.addError(error, stack);
              },
              onDone: out.close,
            );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () {
        open = false;
        // Match live()'s nonwaiting cancellation, including on source completion.
        unawaited(sub?.cancel());
      },
    );
    return out.stream.translated();
  }

  String get _logoPath => 'churches/$churchId/logo.png';

  @override
  Stream<Member?> member(String uid) =>
      _col('members').doc(uid).live().map((s) => s.exists ? memberFromJson(uid, s.data()!) : null).translated();

  @override
  Stream<List<Member>> members() =>
      _col('members').live().map((snap) => [for (final d in snap.docs) memberFromJson(d.id, d.data())]).translated();

  @override
  Stream<List<PendingMember>> pendingMembers() => _col(
    'pendingMembers',
  ).live().map((snap) => [for (final d in snap.docs) pendingMemberFromJson(d.id, d.data())]).translated();

  @override
  Future<void> deletePendingMember(String id) => _guard(() => _col('pendingMembers').doc(id).delete());

  @override
  Stream<ServiceSettings> services() =>
      _col('settings').doc('services').live().map((s) => serviceSettingsFromJson(s.data())).translated();

  @override
  Stream<List<Roster>> rosters({required Day from}) {
    final merged = _MergedRosters();
    return _latestOfBoth(
      _decodedRosters(_col('rosters').where('dateKey', isGreaterThanOrEqualTo: from.key).orderBy('dateKey')),
      // Events begun before [from] and still on: only events' rosters have
      // an endDateKey, so its single-field index is enough.
      _decodedRosters(_col('rosters').where('endDateKey', isGreaterThanOrEqualTo: from.key)),
      merged.combine,
      onCancel: merged.clear,
    ).translated();
  }

  @override
  Future<List<Roster>> eventRosters() => _guard(() async {
    final snap = await _col('rosters').where('kind', isEqualTo: 'event').get();
    final all = [for (final d in snap.docs) ?rosterFromJson(d.data())];
    return [
      for (final r in all)
        if (!(r.forEvent?.cancelled ?? true)) r,
    ]..sort((a, b) => b.day.compareTo(a.day));
  });

  @override
  Stream<StaffOrder> staffOrder(String serviceType) => _col(
    'staff_orders',
  ).doc(serviceType).live().map((s) => StaffOrder.fromJson(s.data() ?? const {})).translated();

  // One-off reads go to the server when online: a listener's first
  // snapshot may come from the offline cache and miss documents.
  @override
  Future<List<Member>> allMembers() => _guard(() async {
    final snap = await _col('members').get();
    return [for (final d in snap.docs) memberFromJson(d.id, d.data())];
  });

  @override
  Future<List<PendingMember>> allPendingMembers() => _guard(() async {
    final snap = await _col('pendingMembers').get();
    return [for (final d in snap.docs) pendingMemberFromJson(d.id, d.data())];
  });

  @override
  Future<List<Roster>> allRosters() => _guard(() async {
    final snap = await _col('rosters').get();
    return [for (final d in snap.docs) ?rosterFromJson(d.data())];
  });

  @override
  Future<Map<String, StaffOrder>> allStaffOrders() => _guard(() async {
    final snap = await _col('staff_orders').get();
    return {for (final d in snap.docs) d.id: StaffOrder.fromJson(d.data())};
  });

  Json _rosterDoc(Roster r) => {
    ...rosterToJson(r),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  @override
  Future<void> saveRoster(Roster roster) => _guard(() => _col('rosters').doc(roster.id).set(_rosterDoc(roster)));

  @override
  Future<void> saveRosters(List<Roster> rosters, {String via = 'app'}) => _guard(() {
    final batch = _db.batch();
    for (final r in rosters) {
      batch.set(_col('rosters').doc(r.id), {..._rosterDoc(r), 'via': via});
    }
    return batch.commit();
  });

  @override
  Future<void> deleteRoster(Roster roster) => _guard(() => _col('rosters').doc(roster.id).delete());

  @override
  Future<void> updateStaffOrder(
    String serviceType,
    Map<String, List<String>?> changes,
  ) async {
    if (changes.isEmpty) return;
    final ref = _col('staff_orders').doc(serviceType);
    // Read-modify-write in a transaction so two editors ordering different
    // duties do not overwrite each other.
    await _guard(
      () => _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final next = StaffOrder.fromJson(
          snap.data() ?? const {},
        ).withChanges(changes);
        tx.set(ref, next.toJson());
      }),
    );
  }

  @override
  Future<void> saveServices(List<Service> services) {
    final ref = _col('settings').doc('services');
    // Merge ids inside a transaction: two admins saving at once must not
    // drop each other's new IDs (the rules also reject shrinking ids).
    return _guard(
      () => _db.runTransaction((tx) async {
        final current = serviceSettingsFromJson((await tx.get(ref)).data());
        final next = current.withServices(services);
        tx.set(ref, {
          'services': [for (final s in next.services) serviceToJson(s)],
          'ids': next.ids,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }),
    );
  }

  @override
  Future<void> saveMember(Member member) => _guard(() => _col('members').doc(member.uid).update(memberToJson(member)));

  @override
  Future<void> removeMember(String uid) => _guard(() => _col('members').doc(uid).delete());

  @override
  Future<void> setNotificationPrefs(String uid, Set<NotificationKind> muted) => _guard(
    () => _col('members').doc(uid).update({'notificationPrefs': notificationPrefsToJson(muted)}),
  );

  @override
  Stream<List<Invite>> invites() => _db
      .collection('invites')
      .where('cid', isEqualTo: churchId)
      .orderBy('expiresAt', descending: true)
      .live()
      .map(
        (snap) => [for (final d in snap.docs) inviteFromJson(d.id, d.data())],
      )
      .translated();

  @override
  Future<Invite> createInvite({required Duration validFor, List<String> zoneTypes = const []}) => _guard(() async {
    final church = await _church.get();
    final code = randomInviteCode();
    final expiresAt = _clock().add(validFor);
    final uid = fa.FirebaseAuth.instance.currentUser?.uid;
    await _db.collection('invites').doc(code).set({
      'cid': churchId,
      'churchName': church.data()?['name'] ?? '',
      'expiresAt': Timestamp.fromDate(expiresAt),
      'revoked': false,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      if (zoneTypes.isNotEmpty) 'zoneTypes': zoneTypes,
    });
    return Invite(
      code: code,
      churchId: churchId,
      churchName: church.data()?['name'] as String? ?? '',
      expiresAt: expiresAt,
      zoneTypes: zoneTypes,
    );
  });

  @override
  Future<void> revokeInvite(String code) => _guard(() => _db.collection('invites').doc(code).update({'revoked': true}));

  @override
  Stream<CalendarSettings> calendarSettings() =>
      _col('settings').doc('calendar').live().map((s) => calendarSettingsFromJson(s.data())).translated();

  @override
  Stream<ChurchLink?> churchLink() =>
      _col('settings').doc('link').live().map((s) => churchLinkFromJson(s.data())).translated();

  @override
  Future<LinkSourceResult> setChurchLink(ChurchLink? link) async {
    final ref = _col('settings').doc('link');
    if (link == null) {
      await _guard(ref.delete);
      return const LinkSourceResult();
    }
    final saved = churchLinkFromJson((await _guard(ref.get)).data());
    // Merge: the source and fetch time on the same doc are set by the
    // setLinkSource function, which also fetches a new source.
    await _guard(
      () => ref.set({...churchLinkToJson(link), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)),
    );
    if (link.source == saved?.source && (link.source == null || link.fetchMinute == saved?.fetchMinute)) {
      return const LinkSourceResult();
    }
    final d = await _call('setLinkSource', {'source': link.source, 'fetchMinute': link.fetchMinute});
    final content = d['content'];
    return LinkSourceResult(
      content: content is Map && link.source != null
          ? linkContentFromJson({...Map<String, dynamic>.from(content), 'source': link.source})
          : null,
      error: d['ok'] == true ? null : linkFetchErrorFromName(d['error']),
      status: (d['status'] as num?)?.toInt(),
    );
  }

  @override
  Stream<LinkContent?> linkContent() =>
      _col('settings').doc('linkContent').live().map((s) => linkContentFromJson(s.data())).translated();

  @override
  Stream<WebhookSettings?> webhook() =>
      _col('settings').doc('webhook').live().map((s) => webhookFromJson(s.data())).translated();

  @override
  Future<void> setHomeName(String? name) => _guard(() => _church.update({'homeName': name ?? FieldValue.delete()}));

  @override
  Future<void> uploadLogo(List<int> bytes) => _guard(
    () => _storage
        .ref(_logoPath)
        .putData(
          Uint8List.fromList(bytes),
          SettableMetadata(
            contentType: 'image/png',
            cacheControl: 'public, max-age=86400',
          ),
        ),
  );

  @override
  Future<void> deleteChurch() => _call('deleteChurch');

  @override
  Future<void> restoreChurch() => _call('restoreChurch');

  @override
  Future<void> mergePending(String pendingId, String uid) =>
      _call('mergePending', {'pendingId': pendingId, 'uid': uid});

  @override
  Future<String?> webhookSave({
    required String? url,
    bool calendar = false,
    bool roster = false,
    String? secret,
  }) async {
    final d = await _call('webhookSave', {
      'url': url,
      'events': {'calendar': calendar, 'roster': roster},
      'secret': ?secret,
    });
    return d['secret'] as String?;
  }

  @override
  Future<String?> webhookRotateSecret({String? secret}) async =>
      (await _call('webhookRotateSecret', {'secret': ?secret}))['secret'] as String?;

  @override
  Future<WebhookDelivery> webhookTest() async =>
      webhookDeliveryFromJson(await _call('webhookTest')) ?? const WebhookDelivery(ok: false);

  @override
  Future<Uri> calendarAuthUrl() async => Uri.parse((await _call('calendarAuthUrl'))['url'] as String);

  @override
  Future<List<({String id, String name})>> calendarList() async {
    final d = await _call('calendarList');
    return [
      for (final c in d['calendars'] as List<dynamic>? ?? const [])
        if (c is Map) (id: c['id'] as String, name: c['name'] as String? ?? ''),
    ];
  }

  @override
  Future<void> calendarSelect(String calendarId, String calendarName) =>
      _call('calendarSelect', {'calendarId': calendarId, 'calendarName': calendarName});

  @override
  Future<void> calendarDisconnect() => _call('calendarDisconnect');

  @override
  Future<List<CalendarEvent>> calendarEvents(String month) async {
    final d = await _call('calendarEvents', {'month': month});
    return [
      for (final e in d['events'] as List<dynamic>? ?? const []) ?calendarEventFromJson(e),
    ];
  }

  @override
  Future<CalendarEvent> calendarSave(CalendarEvent event, {CalendarEvent? previous, String? restoreRosterOf}) async {
    final d = await _call('calendarWrite', {
      'op': 'upsert',
      'event': calendarEventToJson(event),
      'restoreRosterOf': ?restoreRosterOf,
      // The months the event was in, for the function to drop from its
      // cache. previousStart is what functions before `previous` read.
      if (previous != null) ...{
        'previous': {'start': calendarEventToJson(previous)['start'], 'end': calendarEventToJson(previous)['end']},
        'previousStart': calendarEventToJson(previous)['start'],
      },
    });
    return calendarEventFromJson(d['event']) ?? event;
  }

  @override
  Future<void> calendarDelete(CalendarEvent event) => _call('calendarWrite', {
    'op': 'delete',
    'eventId': event.id,
    'event': calendarEventToJson(event),
  });

  @override
  Future<PhotoQuota> photoQuota() async {
    final d = await _call('photoQuota');
    return PhotoQuota(
      remaining: (d['remaining'] as num).toInt(),
      limit: (d['limit'] as num).toInt(),
      platformOpen: d['platformOpen'] == true,
    );
  }

  @override
  Future<List<dynamic>> recognizeRoster(String serviceType, List<PhotoInput> images) async {
    final d = await _call('recognizeRoster', {
      'serviceType': serviceType,
      'images': [
        for (final i in images) {'mimeType': i.mimeType, 'data': base64Encode(i.bytes)},
      ],
    });
    return d['rows'] as List<dynamic>? ?? const [];
  }
}

const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

typedef _DecodedRosterSnapshot = ({Map<String, Roster?> rosters, ({Object error, StackTrace stack})? failure});

/// Keeps only decoded rosters, per query subscription, not a second JSON copy.
/// Queries still read every matching document; only unchanged conversion work
/// is avoided. The complete snapshot supplies membership and source order.
Stream<_DecodedRosterSnapshot> _decodedRosters(Query<Json> query) {
  var previous = <String, Roster?>{};
  final serverReads = _serverReads[query.firestore] == true;
  late final StreamController<_DecodedRosterSnapshot> out;
  StreamSubscription<_DecodedRosterSnapshot>? sub;
  out = StreamController<_DecodedRosterSnapshot>(
    onListen: () {
      sub = retryRefused(
        () {
          // A retried listener starts its own docChanges baseline.
          previous = {};
          return query
              .snapshots(includeMetadataChanges: serverReads)
              .map<_DecodedRosterSnapshot?>((snapshot) {
                try {
                  final docs = snapshot.docs;
                  final changes = snapshot.docChanges;
                  // A full replacement already has to convert everything. Do
                  // not deep-compare all duties merely to reuse its objects.
                  final replaceAll = docs.length > 1 && changes.length >= docs.length;
                  final changed = replaceAll ? const <String>{} : {for (final change in changes) change.doc.id};
                  final next = <String, Roster?>{};
                  for (final doc in docs) {
                    if (replaceAll) {
                      next[doc.id] = rosterFromJson(doc.data());
                      continue;
                    }
                    final before = previous[doc.id];
                    final value = previous.containsKey(doc.id) && !changed.contains(doc.id)
                        ? before
                        : rosterFromJson(doc.data());
                    // Check identity first for untouched documents, and cheap
                    // event tags before deep duty equality on bulk tag edits.
                    final same =
                        identical(value, before) ||
                        (value != null && before != null && listEquals(value.events, before.events) && value == before);
                    next[doc.id] = same ? before : value;
                  }
                  previous = next;
                  // Reconcile cache snapshots too: the server acknowledgement
                  // may contain no changes relative to the suppressed cache.
                  return serverReads && snapshot.metadata.isFromCache ? null : (rosters: next, failure: null);
                } catch (error, stack) {
                  // SDK changes advanced even when this snapshot failed to
                  // decode. The next snapshot must rebuild its whole baseline.
                  previous = {};
                  // Server-only reads never exposed cache decoding failures.
                  if (serverReads && snapshot.metadata.isFromCache) return null;
                  // Keep the failed source, not its last successful data: an
                  // update of the other query cannot make this decode succeed.
                  return (rosters: const <String, Roster?>{}, failure: (error: error, stack: stack));
                }
              })
              .where((value) => value != null)
              .cast<_DecodedRosterSnapshot>();
        },
        isRefused: _refused,
      ).listen(out.add, onError: out.addError, onDone: out.close);
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () async {
      previous = {};
      final stopping = sub;
      sub = null;
      await stopping?.cancel();
    },
  );
  return out.stream;
}

/// Reuses an unchanged sorted result without changing the two queries' merge
/// order: a valid day-query entry wins; a null one leaves the event fallback.
class _MergedRosters {
  Map<String, Roster> _previous = {};
  List<Roster> _sorted = [];

  List<Roster> combine(_DecodedRosterSnapshot days, _DecodedRosterSnapshot events) {
    // Events were decoded first in the original raw-snapshot merge.
    final failure = events.failure ?? days.failure;
    if (failure != null) Error.throwWithStackTrace(failure.error, failure.stack);
    final next = {
      for (final source in [events.rosters, days.rosters])
        for (final entry in source.entries) entry.key: ?entry.value,
    };
    var unchanged = next.length == _previous.length;
    final oldKeys = _previous.keys.iterator;
    if (unchanged) {
      for (final entry in next.entries) {
        if (!oldKeys.moveNext() || oldKeys.current != entry.key || !identical(_previous[entry.key], entry.value)) {
          unchanged = false;
          break;
        }
      }
    }
    if (unchanged) return _sorted;
    _previous = next;
    return _sorted = next.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  }

  void clear() {
    _previous = {};
    _sorted = [];
  }
}

/// The latest of [a] and [b] together, once each has given one.
Stream<R> _latestOfBoth<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine, {
  void Function()? onCancel,
}) {
  late final StreamController<R> out;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  (A,)? lastA;
  (B,)? lastB;
  void emit() {
    if (lastA case (final x,)) {
      if (lastB case (final y,)) {
        try {
          out.add(combine(x, y));
        } catch (error, stack) {
          out.addError(error, stack);
        }
      }
    }
  }

  out = StreamController<R>(
    onListen: () {
      var open = 2;
      void done() {
        if (--open == 0) out.close();
      }

      subA = a.listen(
        (v) {
          lastA = (v,);
          emit();
        },
        onError: out.addError,
        onDone: done,
      );
      subB = b.listen(
        (v) {
          lastB = (v,);
          emit();
        },
        onError: out.addError,
        onDone: done,
      );
    },
    onPause: () {
      subA?.pause();
      subB?.pause();
    },
    onResume: () {
      subA?.resume();
      subB?.resume();
    },
    onCancel: () async {
      lastA = null;
      lastB = null;
      onCancel?.call();
      final stoppingA = subA;
      final stoppingB = subB;
      subA = null;
      subB = null;
      await Future.wait<void>([?stoppingA?.cancel(), ?stoppingB?.cancel()]);
    },
  );
  return out.stream;
}

/// 10 characters from a 32-letter alphabet without look-alikes (0/O, 1/I):
/// 50 bits, enough that guessing a live invite is not practical.
String randomInviteCode() {
  final rng = Random.secure();
  return List.generate(
    10,
    (_) => _alphabet[rng.nextInt(_alphabet.length)],
  ).join();
}

// ---------------------------------------------------------------- functions

/// Errors from Firestore, Storage and Cloud Functions as [CloudException]s:
/// a direct write the rules refuse gives the code a function refusing it
/// would give.
CloudException _cloudError(FirebaseException e) => switch (e) {
  FirebaseFunctionsException() => _Callables.translate(e),
  // Storage says unauthorized where Firestore says permission-denied.
  FirebaseException(code: 'unauthorized') => const CloudException(CloudErrorCode.permissionDenied),
  _ => CloudException(_codeFor(e.code)),
};

/// What a Firebase error code means, when no reason of ours came with it.
CloudErrorCode _codeFor(String code) => switch (code) {
  'permission-denied' || 'unauthenticated' => CloudErrorCode.permissionDenied,
  'unavailable' || 'deadline-exceeded' => CloudErrorCode.unavailable,
  'resource-exhausted' => CloudErrorCode.quotaExceeded,
  _ => CloudErrorCode.unknown,
};

/// Runs a Firestore or Storage operation, its errors as [CloudException]s.
Future<T> _guard<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on FirebaseException catch (e, stack) {
    Error.throwWithStackTrace(_cloudError(e), stack);
  }
}

extension _Translated<T> on Stream<T> {
  /// This stream, its Firestore errors as [CloudException]s.
  Stream<T> translated() => handleError(
    (Object e, StackTrace stack) => Error.throwWithStackTrace(_cloudError(e as FirebaseException), stack),
    test: (e) => e is FirebaseException,
  );
}

Map<String, Object?> _asMap(Object? data) => data is Map ? Map<String, Object?>.from(data) : const {};

/// Calls Cloud Functions, their errors as [CloudException]s.
class _Callables {
  _Callables(this._functions, this._auth);

  final FirebaseFunctions _functions;
  final fa.FirebaseAuth _auth;

  Future<Object?> call(String name, [Map<String, Object?>? data]) async {
    try {
      return await _callOnce(name, data);
    } on CloudException catch (e) {
      // Verified in another tab, or before the app was reopened: the ID
      // token still says unverified until it is refreshed.
      if (e.code != CloudErrorCode.unverifiedEmail || !await _verifiedNow()) rethrow;
      return _callOnce(name, data);
    }
  }

  Future<Object?> _callOnce(String name, Map<String, Object?>? data) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(data);
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      throw translate(e);
    }
  }

  /// Reloads the account and, when its email is verified, refreshes the ID
  /// token so the next call carries it.
  Future<bool> _verifiedNow() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
    } on fa.FirebaseAuthException {
      return false; // Offline: the unverified answer stands.
    }
    if (_auth.currentUser?.emailVerified != true) return false;
    await _auth.currentUser?.getIdToken(true);
    return true;
  }

  /// The reason the function gave, else what its error code means.
  static CloudException translate(FirebaseFunctionsException e) {
    final details = e.details;
    final reason = details is Map ? details['reason'] : null;
    final detail = details is Map ? details['detail'] : null;
    for (final code in CloudErrorCode.values) {
      if (code.name == reason) {
        return CloudException(
          code,
          reason: CloudReason.values.where((r) => r.name == detail).firstOrNull,
          churches: detail is List ? [for (final c in detail) '$c'] : const [],
        );
      }
    }
    return CloudException(_codeFor(e.code));
  }

  /// Sends an error report once, never failing.
  Future<void> report(Map<String, Object?> data) async {
    try {
      await _functions.httpsCallable('logClientError').call<Object?>(data);
    } catch (_) {
      // Error reporting must never cause another error.
    }
  }
}

class FirebaseCloudApi implements CloudApi {
  FirebaseCloudApi._(this._calls, this._storage, this._auth);

  final _Callables _calls;
  final FirebaseStorage _storage;
  final fa.FirebaseAuth _auth;

  Future<Object?> _call(String name, [Map<String, Object?>? data]) => _calls.call(name, data);

  @override
  Future<String> createChurch(String name) async =>
      _asMap(await _call('createChurch', {'name': name}))['churchId'] as String;

  @override
  Future<Invite> previewInvite(String code) async {
    final data = _asMap(await _call('previewInvite', {'code': code}));
    return Invite(
      code: code,
      churchId: data['churchId'] as String,
      churchName: data['churchName'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (data['expiresAt'] as num).toInt(),
      ),
    );
  }

  @override
  Future<String> invitedChurchName(String code) async =>
      _asMap(await _call('previewInvite', {'code': code}))['churchName'] as String? ?? '';

  @override
  Future<String> redeemInvite(String code) async =>
      _asMap(await _call('redeemInvite', {'code': code}))['churchId'] as String;

  @override
  Future<void> deleteAccount() => _call('deleteAccount');

  @override
  Future<String> uploadMoveFile(List<int> bytes) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const CloudException(CloudErrorCode.permissionDenied);
    final path = 'moves/$uid/${DateTime.now().millisecondsSinceEpoch}.json';
    await _storage.ref(path).putData(Uint8List.fromList(bytes), SettableMetadata(contentType: 'application/json'));
    return path;
  }

  @override
  Future<MovePreview> movePreview(String path) async {
    final d = _asMap(await _call('movePreview', {'path': path}));
    return MovePreview(
      members: (d['members'] as num?)?.toInt() ?? 0,
      rosters: (d['rosters'] as num?)?.toInt() ?? 0,
      skippedRosters: (d['skippedRosters'] as num?)?.toInt() ?? 0,
      services: [
        for (final s in d['services'] as List<dynamic>? ?? const [])
          if (s is Map) s['name'] as String? ?? '',
      ],
      people: [
        for (final p in d['people'] as List<dynamic>? ?? const [])
          if (p is Map)
            MovePerson(id: p['id'] as String, name: p['name'] as String? ?? '', email: p['email'] as String? ?? ''),
      ],
    );
  }

  @override
  Future<String> moveCommit(String path, {required String churchName, String? me}) async =>
      _asMap(await _call('moveCommit', {'path': path, 'churchName': churchName, 'me': me}))['churchId'] as String;

  @override
  Future<List<PendingClaim>> pendingClaims() async {
    final d = _asMap(await _call('pendingClaims'));
    return [
      for (final c in d['claims'] as List<dynamic>? ?? const [])
        if (c is Map)
          PendingClaim(
            churchId: c['churchId'] as String,
            churchName: c['churchName'] as String? ?? '',
            pendingId: c['pendingId'] as String,
            name: c['name'] as String? ?? '',
          ),
    ];
  }

  @override
  Future<String> claimPending(String churchId, String pendingId) async =>
      _asMap(await _call('claimPending', {'churchId': churchId, 'pendingId': pendingId}))['churchId'] as String;

  @override
  Future<ChurchPreview> churchPreview(String churchId) async {
    final d = _asMap(await _call('churchPreview', {'churchId': churchId}));
    final logo = d['logoPath'];
    return ChurchPreview(
      id: churchId,
      name: d['name'] as String? ?? '',
      // Served by the church page on the hosting origin.
      logoUrl: logo is String ? '${Env.current.webOrigin}$logo' : null,
    );
  }

  @override
  Future<List<ChurchSummary>> adminSearchChurches(String query) async {
    final data = _asMap(await _call('adminSearchChurches', {'query': query}));
    return [
      for (final raw in data['churches'] as List<dynamic>? ?? const [])
        if (raw is Map)
          ChurchSummary(
            id: raw['id'] as String,
            name: raw['name'] as String,
            status: ChurchStatus.values.firstWhere(
              (s) => s.name == raw['status'],
              orElse: () => ChurchStatus.suspended,
            ),
            memberCount: (raw['memberCount'] as num?)?.toInt() ?? 0,
            admins: [
              for (final a in raw['admins'] as List<dynamic>? ?? const [])
                if (a is Map)
                  Member(
                    uid: a['uid'] as String,
                    name: a['name'] as String? ?? '',
                    email: a['email'] as String? ?? '',
                    role: Role.admin,
                  ),
            ],
          ),
    ];
  }

  @override
  Future<void> adminRenameChurch(String churchId, String name) =>
      _call('adminRenameChurch', {'churchId': churchId, 'name': name});

  @override
  Future<List<Member>> adminChurchMembers(String churchId) async {
    final data = _asMap(
      await _call('adminChurchMembers', {'churchId': churchId}),
    );
    return [
      for (final raw in data['members'] as List<dynamic>? ?? const [])
        if (raw is Map)
          Member(
            uid: raw['uid'] as String,
            name: raw['name'] as String? ?? '',
            email: raw['email'] as String? ?? '',
            role: Role.values.firstWhere(
              (r) => r.name == raw['role'],
              orElse: () => Role.staff,
            ),
          ),
    ];
  }

  @override
  Future<void> adminTransferAdmin(String churchId, String uid) =>
      _call('adminTransferAdmin', {'churchId': churchId, 'uid': uid});

  @override
  Future<void> adminSetStatus(String churchId, ChurchStatus status) =>
      _call('adminSetStatus', {'churchId': churchId, 'status': status.name});

  @override
  Future<List<DailyStats>> adminStats({int days = 30}) async {
    final data = _asMap(await _call('adminStats', {'days': days}));
    return [
      for (final raw in data['days'] as List<dynamic>? ?? const [])
        if (raw case {
          'date': final String date,
        } when Day.tryParse(date) != null)
          DailyStats(
            day: Day.parse(date),
            values: {
              for (final e in (raw).entries)
                if (e.key is String && e.value is num) e.key as String: e.value as num,
            },
          ),
    ];
  }

  @override
  Future<FundingOverview> adminFunding() async {
    final d = _asMap(await _call('adminFunding'));
    final summary = d['funding'];
    return FundingOverview(
      costs: [
        for (final raw in d['costs'] as List<dynamic>? ?? const [])
          if (raw case {
            'name': final String name,
            'amount': final num amount,
            'currency': final String code,
            'per': final String per,
          } when Currency.fromCode(code) != null)
            CostItem(
              name: name,
              amount: amount,
              currency: Currency.fromCode(code)!,
              per: per == 'year' ? CostPeriod.year : CostPeriod.month,
            ),
      ],
      months: [
        for (final raw in d['months'] as List<dynamic>? ?? const [])
          if (raw case {'month': final String month, 'received': final num received, 'target': final num target})
            FundingMonth(month: month, received: received.round(), target: target.round()),
      ],
      funding: summary is Map ? fundingFromJson(Map<String, Object?>.from(summary)) : null,
    );
  }

  @override
  Future<void> adminSetFundingCosts(List<CostItem> items) => _call('adminSetFundingCosts', {
    'items': [
      for (final i in items) {'name': i.name, 'amount': i.amount, 'currency': i.currency.code, 'per': i.per.name},
    ],
  });

  @override
  Future<void> logError({
    required String message,
    required String stack,
    String? churchId,
  }) => _calls.report({'message': message, 'stack': stack, 'churchId': ?churchId});
}
