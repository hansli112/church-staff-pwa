import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/saved_read.dart';

import '../support/harness.dart';

/// What the server answers [_count]: [answer], once [held] lets it.
class _Server {
  int answer = 1;
  Completer<void>? held;
  Object? error;
  int reads = 0;

  Future<int> read() async {
    reads++;
    final gate = held;
    final failure = error;
    await gate?.future;
    if (failure != null) throw failure;
    return answer;
  }
}

late _Server _server;

final _count = AsyncNotifierProvider.autoDispose<SavedRead<int>, Saved<int>>(
  () => SavedRead(
    'count',
    read: (_) => _server.read(),
    encode: (n) => {'n': n},
    decode: (json) => json['n']! as int,
  ),
);

void main() {
  late MemoryBackend backend;
  late List<Override> overrides;

  setUp(() async {
    _server = _Server();
    backend = MemoryBackend(clock: testClock)..auth.signInAs('pastor@example.com', uid: 'pastor');
    overrides = await testOverrides(backend);
  });

  /// The app opened anew on this device: what it kept is all it has.
  Future<ProviderContainer> launch() async {
    final container = ProviderContainer(overrides: overrides, retry: (_, _) => null);
    addTearDown(container.dispose);
    container.listen(_count, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  /// Opened once, read to the end, and closed: this device kept [answer].
  Future<void> keep(int answer) async {
    _server.answer = answer;
    final container = await launch();
    expect(container.read(_count).value?.value, answer);
    await pumpEventQueue();
    container.dispose();
  }

  test('with nothing kept, it waits for the server', () async {
    _server.held = Completer();
    final container = await launch();
    expect(container.read(_count).isLoading, isTrue);
    expect(container.read(_count).hasValue, isFalse);
    _server.held!.complete();
    await pumpEventQueue();
    expect(container.read(_count).value?.value, 1);
    expect(container.read(_count).value?.fresh, isTrue);
  });

  test('opened again, the kept answer shows at once, then the new one', () async {
    await keep(1);
    _server
      ..answer = 2
      ..held = Completer();
    final container = await launch();
    final shown = container.read(_count).value!;
    expect((shown.value, shown.fresh), (1, false));
    expect(shown.status.cached, isFalse, reason: 'reading again is not yet worth a label');
    _server.held!.complete();
    await pumpEventQueue();
    final answered = container.read(_count).value!;
    expect((answered.value, answered.fresh), (2, true));
  });

  test('a failed read keeps the kept answer, labelled', () async {
    await keep(1);
    _server.error = const CloudException(CloudErrorCode.unavailable);
    final container = await launch();
    final shown = container.read(_count).value!;
    expect((shown.value, shown.fresh), (1, false));
    expect(shown.status.cached, isTrue);
    expect(container.read(_count).hasError, isFalse);
  });

  test('a refusal drops the kept answer, here and next time', () async {
    await keep(1);
    _server.error = const CloudException(CloudErrorCode.permissionDenied);
    final refused = await launch();
    expect(refused.read(_count).hasError, isTrue);
    refused.dispose();
    _server
      ..error = null
      ..held = Completer();
    final next = await launch();
    expect(next.read(_count).hasValue, isFalse);
  });

  test('another account finds nothing of the last one', () async {
    await keep(1);
    await backend.auth.signOut();
    backend.auth.signInAs('mary@example.com', uid: 'mary');
    _server.held = Completer();
    final container = await launch();
    expect(container.read(_count).hasValue, isFalse);
  });

  test('signing out drops what was kept', () async {
    await keep(1);
    await backend.auth.signOut();
    final signedOut = await launch();
    signedOut.read(savedReadsProvider);
    signedOut.dispose();
    backend.auth.signInAs('pastor@example.com', uid: 'pastor');
    _server.held = Completer();
    final container = await launch();
    expect(container.read(_count).hasValue, isFalse);
  });

  test('reload keeps what shows until the answer, and an earlier read cannot replace it', () async {
    await keep(1);
    final firstRead = _server.held = Completer();
    _server.answer = 2;
    final container = await launch();
    _server
      ..held = null
      ..answer = 3;
    await container.read(_count.notifier).reload();
    expect(container.read(_count).value?.value, 3);
    firstRead.complete();
    await pumpEventQueue();
    expect(container.read(_count).value?.value, 3);
    expect(container.read(uidProvider), 'pastor');
  });
}
