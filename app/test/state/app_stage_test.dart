import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/providers.dart';

import '../support/harness.dart';

void main() {
  test('restoring a saved session waits for the memberships instead of showing welcome', () async {
    final backend = MemoryBackend(clock: testClock);
    final cid = backend.addChurch('恩典堂', id: 'grace');
    backend.addMember(cid, const Member(uid: 'u1', name: '王牧師', role: Role.admin));
    final auth = StreamController<AuthUser?>();
    final container = ProviderContainer(
      overrides: [
        ...await testOverrides(backend),
        authUserProvider.overrideWith((ref) => auth.stream),
      ],
    );
    addTearDown(container.dispose);
    final stages = <AppStage>[];
    container.listen(appStageProvider, (_, s) => stages.add(s), fireImmediately: true);

    // Something reads the memberships while the session is being restored.
    container.listen(membershipsProvider, (_, _) {});
    await pumpEventQueue();
    auth.add(const AuthUser(uid: 'u1', email: 'a@example.com', emailVerified: true));
    await pumpEventQueue();

    expect(stages, isNot(contains(AppStage.noChurch)));
    expect(container.read(membershipsProvider).value, hasLength(1));
  });

  test('a failed session restore signs out instead of waiting forever', () async {
    final backend = MemoryBackend(clock: testClock);
    final auth = StreamController<AuthUser?>();
    // As after Riverpod's retries have given up.
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...await testOverrides(backend),
        authUserProvider.overrideWith((ref) => auth.stream),
      ],
    );
    addTearDown(container.dispose);
    container.listen(membershipsProvider, (_, _) {});
    container.listen(appStageProvider, (_, _) {});
    auth.addError(Exception('restore failed'));
    await pumpEventQueue();
    expect(container.read(appStageProvider), AppStage.signedOut);
    expect(container.read(membershipsProvider).hasValue, isTrue);
  });
}
