import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';

import 'world.dart';

class MemoryWorld implements ContractWorld {
  @override
  final MemoryBackend backend = MemoryBackend();

  @override
  Future<String> signUp(String email, {String name = '', bool verified = true}) async {
    await backend.auth.registerWithEmail(name, email, contractPassword);
    if (verified) {
      backend.auth.verify(email);
      await backend.auth.reload();
    }
    return backend.auth.currentUser!.uid;
  }

  @override
  Future<void> signIn(String email) => backend.auth.signInWithEmail(email, contractPassword);

  @override
  Future<void> signOut() => backend.auth.signOut();

  @override
  Future<void> verify(String email) async => backend.auth.verify(email);

  @override
  Future<void> makeOperator(String email) async {
    await signIn(email);
    backend.auth.operators.add(backend.auth.currentUser!.uid);
  }

  @override
  Future<void> addPending(String churchId, PendingMember pending, {List<String> rosterIds = const []}) async {
    (backend.pendingMembers[churchId] ??= {})[pending.id] = pending;
    backend.notify();
  }

  @override
  Future<void> backdateDeletion(String churchId, Duration ago) async {
    final c = backend.churches[churchId]!;
    backend.churches[churchId] = Church(
      id: c.id,
      name: c.name,
      status: c.status,
      logoUrl: c.logoUrl,
      homeName: c.homeName,
      deletedAt: backend.clock().subtract(ago),
    );
    backend.notify();
  }

  @override
  bool isDenied(Object error) => error is CloudException && error.code == CloudErrorCode.permissionDenied;
}
