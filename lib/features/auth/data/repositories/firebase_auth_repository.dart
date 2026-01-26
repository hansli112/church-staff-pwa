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
    try {
      // 直接使用傳入的完整 Email 登入
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (credential.user == null) return null;

      return await _fetchUserFromFirestore(credential.user!.uid);
    } catch (e) {
      print('Firebase Login Error: $e');
      return null;
    }
  }

  @override
  Future<User?> getCurrentUser() async {
    final current = await _auth.authStateChanges().first;
    if (current == null) return null;
    return await _fetchUserFromFirestore(current.uid);
  }

  Future<User?> _fetchUserFromFirestore(String uid) async {
    try {
      final doc = await _usersCollection.doc(uid).get();
      if (!doc.exists) return null;
      return User.fromJson(doc.data() as Map<String, dynamic>);
    } catch (e) {
      print('Fetch User Error: $e');
      return null;
    }
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
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp',
        options: Firebase.app().options,
      );

      final secondaryAuth = firebase_auth.FirebaseAuth.instanceFor(app: secondaryApp);
      
      // 使用 User 物件中攜帶的完整 Email
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: user.email.trim(),
        password: password,
      );

      final uid = credential.user!.uid;

      final newUser = user.copyWith(id: uid);
      await _usersCollection.doc(uid).set(newUser.toJson());

    } catch (e) {
      print('Add User Error: $e');
      throw Exception('無法新增使用者: $e');
    } finally {
      await secondaryApp?.delete();
    }
  }

  @override
  Future<void> updateUser(User user) async {
    await _usersCollection.doc(user.id).update(user.toJson());
  }

  @override
  Future<void> deleteUser(String id) async {
    await _usersCollection.doc(id).delete();
  }
}
