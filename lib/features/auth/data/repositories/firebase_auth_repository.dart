import 'dart:async';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../cached_user_storage.dart';

class FirebaseAuthRepository implements AuthRepository {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CachedUserStorage _cachedUserStorage;

  FirebaseAuthRepository({CachedUserStorage? cachedUserStorage})
      : _cachedUserStorage = cachedUserStorage ?? CachedUserStorage();

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
      onTimeout: () => throw TimeoutException(
        'Auth state restore timed out after 10s',
      ),
    );
    if (current == null) return null;
    return await _fetchUserFromFirestore(current.uid);
  }

  @override
  Future<User?> getCachedUser() => _cachedUserStorage.read();

  Future<User?> _fetchUserFromFirestore(String uid) async {
    final doc = await _usersCollection.doc(uid).get();
    if (!doc.exists) return null;
    final user = User.fromJson(doc.data() as Map<String, dynamic>);
    // Keep the local cache fresh every time we successfully fetch from Firestore.
    await _cachedUserStorage.write(user);
    return user;
  }

  @override
  Future<void> logout() async {
    await _cachedUserStorage.clear();
    await _auth.signOut();
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
    if (user.email.trim().isEmpty) {
      await _usersCollection.doc(user.id).set(user.toJson());
      return;
    }
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp',
        options: Firebase.app().options,
      );

      final secondaryAuth = firebase_auth.FirebaseAuth.instanceFor(
        app: secondaryApp,
      );

      // 使用 User 物件中攜帶的完整 Email
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: user.email.trim(),
        password: password,
      );

      final uid = credential.user!.uid;

      final newUser = user.copyWith(id: uid);
      await _usersCollection.doc(uid).set(newUser.toJson());
    } catch (e) {
      log('Add User Error: $e');
      throw Exception('無法新增使用者: $e');
    } finally {
      await secondaryApp?.delete();
    }
  }

  @override
  Future<void> updateUser(User user, {String? password}) async {
    final email = user.email.trim();
    if (email.isNotEmpty && password != null) {
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

        final uid = credential.user!.uid;
        final newUser = user.copyWith(id: uid);
        await _usersCollection.doc(uid).set(newUser.toJson());
        if (uid != user.id) {
          await _usersCollection.doc(user.id).delete();
        }
        return;
      } catch (e) {
        log('Update User Error: $e');
        throw Exception('無法建立登入帳號: $e');
      } finally {
        await secondaryApp?.delete();
      }
    }

    await _usersCollection.doc(user.id).update(user.toJson());
  }

  @override
  Future<void> deleteUser(String id) async {
    await _usersCollection.doc(id).delete();
  }
}
