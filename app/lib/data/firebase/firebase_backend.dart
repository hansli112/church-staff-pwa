import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/staff_order.dart';
import '../../env.dart';
import '../backend.dart';
import 'codec.dart';

/// All Cloud Functions run in the same region as Firestore.
const functionsRegion = 'asia-east1';

class FirebaseBackend implements Backend {
  FirebaseBackend({
    fa.FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  }) : _auth = auth ?? fa.FirebaseAuth.instance,
       _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instanceFor(region: functionsRegion),
       _storage = storage ?? FirebaseStorage.instance;

  final fa.FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  @override
  late final AuthGateway auth = FirebaseAuthGateway(_auth);

  @override
  late final ProfileRepository profiles = _Profiles(_db);

  @override
  late final MembershipRepository memberships = _Memberships(_db);

  @override
  late final CloudApi cloud = FirebaseCloudApi(_functions, storage: _storage, auth: _auth);

  final _churches = <String, ChurchData>{};

  @override
  ChurchData church(String churchId) => _churches.putIfAbsent(
    churchId,
    () => FirestoreChurchData(_db, _storage, churchId),
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
    // Native: the system account picker (no browser), when the OAuth web
    // client ID is configured for this build. Otherwise fall back to the
    // browser flow, which needs no native setup.
    if (_googleServerClientId.isEmpty) return _auth.signInWithProvider(provider);
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(serverClientId: _googleServerClientId);
      _googleReady = true;
    }
    try {
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      return _auth.signInWithCredential(fa.GoogleAuthProvider.credential(idToken: idToken));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const AuthException(AuthErrorCode.cancelled);
      rethrow;
    }
  });

  /// The project's OAuth web client ID, from --dart-define.
  static const _googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
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
      _db.doc('users/$uid').snapshots().map((s) => s.exists ? profileFromJson(uid, s.data()!) : null);

  @override
  Future<void> save(UserProfile profile) => _db.runTransaction((tx) async {
    final ref = _db.doc('users/${profile.uid}');
    final current = await tx.get(ref);
    tx.set(ref, {
      'name': profile.name,
      'email': profile.email,
      'locale': profile.locale ?? FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!current.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });

  @override
  Future<void> ensure(UserProfile profile) => _db.runTransaction((tx) async {
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
  });
}

class _Memberships implements MembershipRepository {
  _Memberships(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<List<Membership>> watchMine(String uid) => _db
      .collectionGroup('members')
      .where('uid', isEqualTo: uid)
      .snapshots()
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

class FirestoreChurchData implements ChurchData {
  FirestoreChurchData(this._db, this._storage, this.churchId);

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  @override
  final String churchId;

  DocumentReference<Json> get _church => _db.doc('churches/$churchId');
  CollectionReference<Json> _col(String name) => _church.collection(name);

  String? _logoUrl;
  Object? _logoVersion;

  @override
  Stream<Church?> church() => _church.snapshots().asyncMap((snap) async {
    final data = snap.data();
    if (data == null) return null;
    final version = data['logoVersion'];
    if (version == null) {
      _logoUrl = null;
    } else if (version != _logoVersion) {
      try {
        _logoUrl = await _storage.ref(_logoPath).getDownloadURL();
      } on FirebaseException {
        _logoUrl = null;
      }
    }
    _logoVersion = version;
    return churchFromJson(snap.id, data, logoUrl: _logoUrl);
  });

  String get _logoPath => 'churches/$churchId/logo.png';

  @override
  Stream<Member?> member(String uid) =>
      _col('members').doc(uid).snapshots().map((s) => s.exists ? memberFromJson(uid, s.data()!) : null);

  @override
  Stream<List<Member>> members() => _col('members').snapshots().map(
    (snap) => [for (final d in snap.docs) memberFromJson(d.id, d.data())],
  );

  @override
  Stream<List<PendingMember>> pendingMembers() => _col('pendingMembers').snapshots().map(
    (snap) => [for (final d in snap.docs) pendingMemberFromJson(d.id, d.data())],
  );

  @override
  Future<void> deletePendingMember(String id) => _col('pendingMembers').doc(id).delete();

  @override
  Stream<ServiceSettings> services() => _col(
    'settings',
  ).doc('services').snapshots().map((s) => serviceSettingsFromJson(s.data()));

  @override
  Stream<List<Roster>> rosters({required Day from}) => _col('rosters')
      .where('dateKey', isGreaterThanOrEqualTo: from.key)
      .orderBy('dateKey')
      .snapshots()
      .map((snap) => [for (final d in snap.docs) ?rosterFromJson(d.data())]);

  @override
  Stream<StaffOrder> staffOrder(String serviceType) =>
      _col('staff_orders').doc(serviceType).snapshots().map((s) => StaffOrder.fromJson(s.data() ?? const {}));

  // One-off reads go to the server when online: a listener's first
  // snapshot may come from the offline cache and miss documents.
  @override
  Future<List<Member>> allMembers() async {
    final snap = await _col('members').get();
    return [for (final d in snap.docs) memberFromJson(d.id, d.data())];
  }

  @override
  Future<List<PendingMember>> allPendingMembers() async {
    final snap = await _col('pendingMembers').get();
    return [for (final d in snap.docs) pendingMemberFromJson(d.id, d.data())];
  }

  @override
  Future<List<Roster>> allRosters() async {
    final snap = await _col('rosters').get();
    return [for (final d in snap.docs) ?rosterFromJson(d.data())];
  }

  @override
  Future<Map<String, StaffOrder>> allStaffOrders() async {
    final snap = await _col('staff_orders').get();
    return {for (final d in snap.docs) d.id: StaffOrder.fromJson(d.data())};
  }

  Json _rosterDoc(Roster r) => {
    ...rosterToJson(r),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  @override
  Future<void> saveRoster(Roster roster) => _col('rosters').doc(roster.id).set(_rosterDoc(roster));

  @override
  Future<void> saveRosters(List<Roster> rosters, {String via = 'app'}) {
    final batch = _db.batch();
    for (final r in rosters) {
      batch.set(_col('rosters').doc(r.id), {..._rosterDoc(r), 'via': via});
    }
    return batch.commit();
  }

  @override
  Future<void> deleteRoster(Roster roster) => _col('rosters').doc(roster.id).delete();

  @override
  Future<void> updateStaffOrder(
    String serviceType,
    Map<String, List<String>?> changes,
  ) async {
    if (changes.isEmpty) return;
    final ref = _col('staff_orders').doc(serviceType);
    // Read-modify-write in a transaction so two editors ordering different
    // duties do not overwrite each other.
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final next = StaffOrder.fromJson(
        snap.data() ?? const {},
      ).withChanges(changes);
      tx.set(ref, next.toJson());
    });
  }

  @override
  Future<void> saveServices(List<Service> services) async {
    final ref = _col('settings').doc('services');
    // Merge ids inside a transaction: two admins saving at once must not
    // drop each other's new IDs (the rules also reject shrinking ids).
    await _db.runTransaction((tx) async {
      final current = serviceSettingsFromJson((await tx.get(ref)).data());
      final next = current.withServices(services);
      tx.set(ref, {
        'services': [for (final s in next.services) serviceToJson(s)],
        'ids': next.ids,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> saveMember(Member member) => _col('members').doc(member.uid).update(memberToJson(member));

  @override
  Future<void> removeMember(String uid) => _col('members').doc(uid).delete();

  @override
  Future<void> setNotificationPrefs(String uid, Set<NotificationKind> muted) => _col(
    'members',
  ).doc(uid).update({'notificationPrefs': notificationPrefsToJson(muted)});

  @override
  Stream<List<Invite>> invites() => _db
      .collection('invites')
      .where('cid', isEqualTo: churchId)
      .orderBy('expiresAt', descending: true)
      .snapshots()
      .map(
        (snap) => [for (final d in snap.docs) inviteFromJson(d.id, d.data())],
      );

  @override
  Future<Invite> createInvite({required Duration validFor}) async {
    final church = await _church.get();
    final code = randomInviteCode();
    final expiresAt = DateTime.now().add(validFor);
    final uid = fa.FirebaseAuth.instance.currentUser?.uid;
    await _db.collection('invites').doc(code).set({
      'cid': churchId,
      'churchName': church.data()?['name'] ?? '',
      'expiresAt': Timestamp.fromDate(expiresAt),
      'revoked': false,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return Invite(
      code: code,
      churchId: churchId,
      churchName: church.data()?['name'] as String? ?? '',
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> revokeInvite(String code) => _db.collection('invites').doc(code).update({'revoked': true});

  @override
  Stream<CalendarSettings> calendarSettings() =>
      _col('settings').doc('calendar').snapshots().map((s) => calendarSettingsFromJson(s.data()));

  @override
  Stream<ChurchLink?> churchLink() => _col('settings').doc('link').snapshots().map((s) => churchLinkFromJson(s.data()));

  @override
  Future<void> saveChurchLink(ChurchLink? link) {
    final ref = _col('settings').doc('link');
    if (link == null) return ref.delete();
    // Merge: the content source on the same doc is the backend's.
    return ref.set({...churchLinkToJson(link), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  @override
  Stream<LinkContent?> linkContent() =>
      _col('settings').doc('linkContent').snapshots().map((s) => linkContentFromJson(s.data()));

  @override
  Stream<WebhookSettings?> webhook() =>
      _col('settings').doc('webhook').snapshots().map((s) => webhookFromJson(s.data()));

  @override
  Future<void> setHomeName(String? name) => _church.update({'homeName': name ?? FieldValue.delete()});

  @override
  Future<void> uploadLogo(List<int> bytes) async {
    await _storage
        .ref(_logoPath)
        .putData(
          Uint8List.fromList(bytes),
          SettableMetadata(
            contentType: 'image/png',
            cacheControl: 'public, max-age=86400',
          ),
        );
  }
}

const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

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

class FirebaseCloudApi implements CloudApi {
  FirebaseCloudApi(this._functions, {FirebaseStorage? storage, fa.FirebaseAuth? auth})
    : _storage = storage ?? FirebaseStorage.instance,
      _auth = auth ?? fa.FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;
  final fa.FirebaseAuth _auth;

  Future<Object?> _call(String name, [Map<String, Object?>? data]) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(data);
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      throw _translate(e);
    }
  }

  static CloudException _translate(FirebaseFunctionsException e) {
    final details = e.details;
    final reason = details is Map ? details['reason'] : null;
    for (final code in CloudErrorCode.values) {
      if (code.name == reason) {
        return CloudException(code, details is Map ? details['detail'] : null);
      }
    }
    return CloudException(switch (e.code) {
      'permission-denied' || 'unauthenticated' => CloudErrorCode.permissionDenied,
      'unavailable' || 'deadline-exceeded' => CloudErrorCode.unavailable,
      'resource-exhausted' => CloudErrorCode.quotaExceeded,
      _ => CloudErrorCode.unknown,
    });
  }

  Map<String, Object?> _map(Object? data) => data is Map ? Map<String, Object?>.from(data) : const {};

  @override
  Future<String> createChurch(String name) async =>
      _map(await _call('createChurch', {'name': name}))['churchId'] as String;

  @override
  Future<Invite> previewInvite(String code) async {
    final data = _map(await _call('previewInvite', {'code': code}));
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
  Future<String> redeemInvite(String code) async =>
      _map(await _call('redeemInvite', {'code': code}))['churchId'] as String;

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
    final d = _map(await _call('movePreview', {'path': path}));
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
      _map(await _call('moveCommit', {'path': path, 'churchName': churchName, 'me': me}))['churchId'] as String;

  @override
  Future<List<PendingClaim>> pendingClaims() async {
    final d = _map(await _call('pendingClaims'));
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
      _map(await _call('claimPending', {'churchId': churchId, 'pendingId': pendingId}))['churchId'] as String;

  @override
  Future<void> mergePending(String churchId, String pendingId, String uid) =>
      _call('mergePending', {'churchId': churchId, 'pendingId': pendingId, 'uid': uid});

  @override
  Future<ChurchPreview> churchPreview(String churchId) async {
    final d = _map(await _call('churchPreview', {'churchId': churchId}));
    final logo = d['logoPath'];
    return ChurchPreview(
      id: churchId,
      name: d['name'] as String? ?? '',
      // Served by the church page on the hosting origin.
      logoUrl: logo is String ? '${Env.current.webOrigin}$logo' : null,
    );
  }

  @override
  Future<void> deleteChurch(String churchId) => _call('deleteChurch', {'churchId': churchId});

  @override
  Future<void> restoreChurch(String churchId) => _call('restoreChurch', {'churchId': churchId});

  @override
  Future<LinkSourceResult> setLinkSource(String churchId, String? source, int fetchMinute) async {
    final d = _map(
      await _call('setLinkSource', {'churchId': churchId, 'source': source, 'fetchMinute': fetchMinute}),
    );
    final content = d['content'];
    return LinkSourceResult(
      content: content is Map && source != null
          ? linkContentFromJson({...Map<String, dynamic>.from(content), 'source': source})
          : null,
      error: d['ok'] == true ? null : linkFetchErrorFromName(d['error']),
      status: (d['status'] as num?)?.toInt(),
    );
  }

  @override
  Future<String?> webhookSave(
    String churchId, {
    required String? url,
    bool calendar = false,
    bool roster = false,
    String? secret,
  }) async {
    final d = _map(
      await _call('webhookSave', {
        'churchId': churchId,
        'url': url,
        'events': {'calendar': calendar, 'roster': roster},
        'secret': ?secret,
      }),
    );
    return d['secret'] as String?;
  }

  @override
  Future<String?> webhookRotateSecret(String churchId, {String? secret}) async =>
      _map(await _call('webhookRotateSecret', {'churchId': churchId, 'secret': ?secret}))['secret'] as String?;

  @override
  Future<WebhookDelivery> webhookTest(String churchId) async =>
      webhookDeliveryFromJson(await _call('webhookTest', {'churchId': churchId})) ?? const WebhookDelivery(ok: false);

  @override
  Future<List<ChurchSummary>> adminSearchChurches(String query) async {
    final data = _map(await _call('adminSearchChurches', {'query': query}));
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
    final data = _map(
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
    final data = _map(await _call('adminStats', {'days': days}));
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
  Future<Uri> calendarAuthUrl(String churchId) async =>
      Uri.parse(_map(await _call('calendarAuthUrl', {'churchId': churchId}))['url'] as String);

  @override
  Future<List<({String id, String name})>> calendarList(String churchId) async {
    final d = _map(await _call('calendarList', {'churchId': churchId}));
    return [
      for (final c in d['calendars'] as List<dynamic>? ?? const [])
        if (c is Map) (id: c['id'] as String, name: c['name'] as String? ?? ''),
    ];
  }

  @override
  Future<void> calendarSelect(String churchId, String calendarId, String calendarName) =>
      _call('calendarSelect', {'churchId': churchId, 'calendarId': calendarId, 'calendarName': calendarName});

  @override
  Future<void> calendarDisconnect(String churchId) => _call('calendarDisconnect', {'churchId': churchId});

  @override
  Future<List<CalendarEvent>> calendarEvents(String churchId, String month) async {
    final d = _map(await _call('calendarEvents', {'churchId': churchId, 'month': month}));
    return [
      for (final e in d['events'] as List<dynamic>? ?? const []) ?calendarEventFromJson(e),
    ];
  }

  @override
  Future<CalendarEvent> calendarSave(String churchId, CalendarEvent event, {CalendarEvent? previous}) async {
    final d = _map(
      await _call('calendarWrite', {
        'churchId': churchId,
        'op': 'upsert',
        'event': calendarEventToJson(event),
        if (previous != null) 'previousStart': calendarEventToJson(previous)['start'],
      }),
    );
    return calendarEventFromJson(d['event']) ?? event;
  }

  @override
  Future<void> calendarDelete(String churchId, CalendarEvent event) => _call('calendarWrite', {
    'churchId': churchId,
    'op': 'delete',
    'eventId': event.id,
    'event': calendarEventToJson(event),
  });

  @override
  Future<PhotoQuota> photoQuota(String churchId) async {
    final d = _map(await _call('photoQuota', {'churchId': churchId}));
    return PhotoQuota(
      remaining: (d['remaining'] as num).toInt(),
      limit: (d['limit'] as num).toInt(),
      platformOpen: d['platformOpen'] == true,
    );
  }

  @override
  Future<List<dynamic>> recognizeRoster(String churchId, String serviceType, List<PhotoInput> images) async {
    final d = _map(
      await _call('recognizeRoster', {
        'churchId': churchId,
        'serviceType': serviceType,
        'images': [
          for (final i in images) {'mimeType': i.mimeType, 'data': base64Encode(i.bytes)},
        ],
      }),
    );
    return d['rows'] as List<dynamic>? ?? const [];
  }

  @override
  Future<void> logError({
    required String message,
    required String stack,
    String? churchId,
  }) async {
    try {
      await _functions.httpsCallable('logClientError').call<Object?>({
        'message': message,
        'stack': stack,
        'churchId': ?churchId,
      });
    } catch (_) {
      // Error reporting must never cause another error.
    }
  }
}
