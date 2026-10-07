import 'dart:convert';
import 'dart:js_interop';

import 'package:martha/data/firebase/codec.dart';
import 'package:martha/data/firebase/firebase_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/env.dart';
import 'package:web/web.dart' as web;

import 'world.dart';

/// The contract world on the local emulators (project demo-martha). What
/// the app cannot do itself goes through the emulators' admin REST APIs,
/// which take `Bearer owner` and skip the security rules.
class FirebaseWorld implements ContractWorld {
  FirebaseWorld(this.backend);

  @override
  final FirebaseBackend backend;

  final _uids = <String, String>{};

  static const _project = 'demo-martha';
  static final _auth = 'http://localhost:${EmulatorPorts.auth}';
  static final _firestore = 'http://localhost:${EmulatorPorts.firestore}';
  static final _documents = '$_firestore/v1/projects/$_project/databases/(default)/documents';

  /// Signs out and empties Auth and Firestore.
  Future<void> reset() async {
    await backend.auth.signOut();
    _uids.clear();
    await _send('DELETE', '$_firestore/emulator/v1/projects/$_project/databases/(default)/documents');
    await _send('DELETE', '$_auth/emulator/v1/projects/$_project/accounts');
  }

  @override
  Future<String> signUp(String email, {String name = '', bool verified = true}) async {
    await backend.auth.registerWithEmail(name, email, contractPassword);
    final uid = backend.auth.currentUser!.uid;
    _uids[email] = uid;
    if (verified) {
      await verify(email);
      await backend.auth.reload();
    }
    return uid;
  }

  @override
  Future<void> signIn(String email) => backend.auth.signInWithEmail(email, contractPassword);

  @override
  Future<void> signOut() => backend.auth.signOut();

  @override
  Future<void> verify(String email) => _updateAccount(email, {'emailVerified': true});

  @override
  Future<void> makeOperator(String email) async {
    await _updateAccount(email, {
      'customAttributes': jsonEncode({'operator': true}),
    });
    await signIn(email);
    // A new ID token, with the claim.
    await backend.auth.reload();
  }

  @override
  Future<void> addPending(String churchId, PendingMember pending, {List<String> rosterIds = const []}) async {
    final hash = pending.email.isEmpty ? null : await _sha256(pending.email.trim().toLowerCase());
    final member = memberToJson(
      Member(uid: pending.id, name: pending.name, role: pending.role, groups: pending.groups, zones: pending.zones),
    )..remove('uid');
    await _write('churches/$churchId/pendingMembers/${pending.id}', {
      ...member,
      'email': pending.email,
      'emailHash': hash,
      'rosterIds': rosterIds,
    });
    if (hash != null) {
      await _write(
        'pendingIndex/$hash',
        {
          'churches': {churchId: pending.id},
        },
        mask: ['churches.`$churchId`'],
      );
    }
  }

  @override
  Future<void> backdateDeletion(String churchId, Duration ago) =>
      _write('churches/$churchId', {'deletedAt': DateTime.now().subtract(ago)}, mask: ['deletedAt']);

  Future<void> _updateAccount(String email, Map<String, Object?> fields) => _send(
    'POST',
    '$_auth/identitytoolkit.googleapis.com/v1/projects/$_project/accounts:update',
    {'localId': _uids[email], ...fields},
  );

  /// Writes the fields of [path] (all of them, or only [mask]).
  Future<void> _write(String path, Map<String, Object?> fields, {List<String>? mask}) {
    final query = mask == null
        ? ''
        : '?${[for (final f in mask) 'updateMask.fieldPaths=${Uri.encodeQueryComponent(f)}'].join('&')}';
    return _send('PATCH', '$_documents/$path$query', {'fields': _fields(fields)});
  }

  static Map<String, Object?> _fields(Map<String, Object?> map) => {
    for (final e in map.entries) e.key: _value(e.value),
  };

  static Map<String, Object?> _value(Object? v) => switch (v) {
    null => {'nullValue': null},
    final bool b => {'booleanValue': b},
    final int i => {'integerValue': '$i'},
    final double d => {'doubleValue': d},
    final String s => {'stringValue': s},
    final DateTime t => {'timestampValue': t.toUtc().toIso8601String()},
    final List<Object?> l => {
      'arrayValue': {'values': l.map(_value).toList()},
    },
    final Map<String, Object?> m => {
      'mapValue': {'fields': _fields(m)},
    },
    _ => throw ArgumentError.value(v, 'value', 'not writable to Firestore'),
  };

  static Future<void> _send(String method, String url, [Object? body]) async {
    final res = await web.window
        .fetch(
          url.toJS,
          web.RequestInit(
            method: method,
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer owner'}.jsify()! as web.HeadersInit,
            body: body == null ? null : jsonEncode(body).toJS,
          ),
        )
        .toDart;
    if (!res.ok) throw StateError('$method $url: ${res.status} ${(await res.text().toDart).toDart}');
  }

  static Future<String> _sha256(String text) async {
    final digest = await web.window.crypto.subtle.digest('SHA-256'.toJS, utf8.encode(text).toJS).toDart;
    return [for (final b in (digest as JSArrayBuffer).toDart.asUint8List()) b.toRadixString(16).padLeft(2, '0')].join();
  }
}
