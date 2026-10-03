import 'dart:async';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/sign_in_account_exception.dart';
import '../cached_user_storage.dart';
import '../sign_in_admin_service.dart';

class FirebaseAuthRepository implements AuthRepository {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CachedUserStorage _cachedUserStorage;
  final SignInAdminService _signIns;

  FirebaseAuthRepository({
    CachedUserStorage? cachedUserStorage,
    SignInAdminService? signIns,
  }) : _cachedUserStorage = cachedUserStorage ?? CachedUserStorage(),
       _signIns = signIns ?? SignInAdminService();

  CollectionReference get _usersCollection => _firestore.collection('users');

  @override
  Future<User?> login(String email, String password) async {
    // Don't catch — let FirebaseAuthException propagate so SessionProvider can
    // map it to a user-friendly message. Returning null here would erase the
    // distinction between "wrong password" and "network unreachable" and
    // make every failure look like '帳號或密碼錯誤'.
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (credential.user == null) return null;
    final user = await _fetchUserFromFirestore(credential.user!.uid);
    if (user != null) await _cachedUserStorage.write(user);
    return user;
  }

  @override
  Future<User?> getCurrentUser() async {
    // Level 1 optimization: Firebase.initializeApp() has already been awaited
    // in main(), which means the SDK has read IndexedDB and populated
    // _auth.currentUser synchronously. Prefer the synchronous getter to skip
    // the IndexedDB stream round-trip (~50-200 ms).
    //
    // Fallback: if currentUser is null we still await authStateChanges().first
    // to handle Safari Private Mode (no IndexedDB) or other edge cases where
    // the synchronous cache hasn't been populated yet, which would cause the
    // SDK to emit the real state on the stream shortly after init.
    var current = _auth.currentUser;
    current ??= await _auth.authStateChanges().first.timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw TimeoutException('Auth state restore timed out after 10s'),
    );
    if (current == null) return null;
    return await _fetchUserFromFirestore(current.uid);
  }

  @override
  Future<User?> getCachedUser() => _cachedUserStorage.read();

  @override
  Future<void> writeCachedUser(User user) => _cachedUserStorage.write(user);

  Future<User?> _fetchUserFromFirestore(String uid) async {
    final doc = await _usersCollection.doc(uid).get();
    if (!doc.exists) return null;
    final user = User.fromJson(doc.data() as Map<String, dynamic>);
    // Cache write is intentionally NOT done here to avoid the user-switch
    // race: if a logout + login-B happens while this await is in flight, the
    // stale A data must not overwrite the B session in local storage.
    // The caller (login or SessionProvider._refreshUserInBackground) is
    // responsible for writing the cache only after verifying the session is
    // still valid.
    return user;
  }

  @override
  Future<void> logout() async {
    // signOut 先做：它才是真正終結 session 的那一步。反過來的話，本地快取
    // 清除一失敗（例如儲存被瀏覽器封鎖）就會讓 signOut 根本不會執行，
    // 而使用者已經看到自己回到登入畫面 —— 共用裝置上等於把帳號留給下一個人。
    await _auth.signOut();

    // 本地快取清除屬於盡力而為：Auth session 已經沒了，就算這裡失敗，
    // 下次啟動時的背景 profile 更新也會發現 session 失效並登出。
    try {
      await _cachedUserStorage.clear();
    } catch (e, st) {
      log('清除本地使用者快取失敗（session 已登出）', error: e, stackTrace: st);
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    // 信件用 Firebase 內建範本；不設語言的話是英文，同工看到會以為是垃圾信。
    await _auth.setLanguageCode('zh-TW');
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  @override
  Future<List<User>> getUsers() async {
    final snapshot = await _usersCollection.get();
    return snapshot.docs
        .map((doc) => User.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> addUser(User user, String password) async {
    final email = user.email.trim();
    if (email.isEmpty) {
      await _usersCollection.doc(user.id).set(user.toJson());
      return;
    }
    final uid = await _createSignIn(email, password, user.name);
    await _usersCollection.doc(uid).set(user.copyWith(id: uid).toJson());
  }

  @override
  Future<void> updateUser(User user, {String? password}) async {
    final email = user.email.trim();
    if (email.isNotEmpty && password != null) {
      // A staff member without an email gets one: their profile moves to the
      // new sign-in's uid.
      final uid = await _createSignIn(email, password, user.name);
      await _usersCollection.doc(uid).set(user.copyWith(id: uid).toJson());
      if (uid != user.id) {
        await _usersCollection.doc(user.id).delete();
      }
      return;
    }

    await _usersCollection.doc(user.id).update(user.toJson());
  }

  /// The sign-in goes first: once the profile is gone the admin can no longer
  /// see the person, and a failed sign-in removal would leave the email
  /// unusable. Removing a sign-in that is already gone succeeds, so a retry
  /// after a failed profile delete works.
  @override
  Future<void> deleteUser(String id) async {
    // On a site without account management only the profile goes, as before.
    await _signIns.delete(id);
    await _usersCollection.doc(id).delete();
  }

  /// Creates [email]'s sign-in and returns its uid: through the site's own
  /// account management when it has one, else in the browser like before.
  Future<String> _createSignIn(
    String email,
    String password,
    String name,
  ) async {
    final uid = await _signIns.create(
      email: email,
      password: password,
      name: name,
    );
    return uid ?? await _createSignInInBrowser(email, password);
  }

  /// A second Firebase app, so creating the sign-in does not sign the admin
  /// out of the first one.
  Future<String> _createSignInInBrowser(String email, String password) async {
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp',
        options: Firebase.app().options,
      );
      final secondaryAuth = firebase_auth.FirebaseAuth.instanceFor(
        app: secondaryApp,
      );
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user!.uid;
    } on firebase_auth.FirebaseAuthException catch (e) {
      log('Create sign-in error: ${e.code}');
      if (e.code != 'email-already-in-use') rethrow;
      throw await _emailTakenInBrowser(email);
    } finally {
      await secondaryApp?.delete();
    }
  }

  /// Why [email] cannot get a sign-in here: another staff member uses it, or a
  /// delete left the sign-in behind. Only the second needs the Firebase console,
  /// since the browser cannot remove someone else's sign-in.
  Future<SignInAccountException> _emailTakenInBrowser(String email) async {
    final owners = await _usersCollection
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (owners.docs.isNotEmpty) {
      final name = (owners.docs.first.data() as Map<String, dynamic>)['name'];
      return SignInAccountException(
        name is String && name.trim().isNotEmpty
            ? '這個 Email 已經是「${name.trim()}」的帳號'
            : '這個 Email 已經有同工在用了',
      );
    }
    final projectId = Firebase.app().options.projectId;
    return SignInAccountException(
      '這個 Email 之前建立過登入帳號（刪除同工時登入帳號還留著）。'
      '請按「開啟 Firebase」，在 Users 清單找到這個 Email 刪除後，再回來新增。',
      helpUrl:
          'https://console.firebase.google.com/project/$projectId/authentication/users',
    );
  }
}
