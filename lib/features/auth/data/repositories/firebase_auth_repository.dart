import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _usersCollection => _firestore.collection('users');

  @override
  Future<User?> login(String email, String password) async {
    // Don't catch — let FirebaseAuthException propagate so AuthProvider can
    // map it to a user-friendly message. Returning null here would erase the
    // distinction between "wrong password" and "network unreachable" and
    // make every failure look like '帳號或密碼錯誤'.
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (credential.user == null) return null;
    return await _fetchUserFromFirestore(credential.user!.uid);
  }

  @override
  Future<User?> getCurrentUser() async {
    // Time-bound the auth-state lookup. authStateChanges().first can hang on
    // Safari Private Mode (no IndexedDB) or when Firebase init fails — without
    // this, AuthProvider stays stuck in the restoring shell forever.
    final current = await _auth.authStateChanges().first.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
    if (current == null) return null;
    return await _fetchUserFromFirestore(current.uid);
  }

  Future<User?> _fetchUserFromFirestore(String uid) async {
    final doc = await _usersCollection.doc(uid).get();
    if (!doc.exists) return null;
    return User.fromJson(doc.data() as Map<String, dynamic>);
  }

  @override
  Future<void> logout() async {
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
