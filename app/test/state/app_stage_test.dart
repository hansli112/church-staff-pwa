import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/echoing_church_data.dart';
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

  test('signing in waits for the memberships instead of showing welcome', () async {
    // Signed out, the memberships are none; that empty list was still held
    // while the new account's came in, and welcome flashed on every sign-in.
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
    // As the app does: something reads the memberships while signed out.
    container.listen(membershipsProvider, (_, _) {});
    auth.add(null);
    await pumpEventQueue();
    expect(container.read(appStageProvider), AppStage.signedOut);

    // As on a phone: the memberships take a moment to come in.
    backend.membershipsHeld = Completer();
    backend.auth.signInAs('a@example.com', uid: 'u1');
    auth.add(const AuthUser(uid: 'u1', email: 'a@example.com', emailVerified: true));
    await pumpEventQueue();
    expect(container.read(appStageProvider), AppStage.loading);
    backend.membershipsHeld!.complete();
    await pumpEventQueue();

    expect(stages, isNot(contains(AppStage.noChurch)));
    expect(container.read(appStageProvider), AppStage.ready);
  });

  test('a church still coming in is loading, not closed', () async {
    // A deep link opened cold went to /closed and lost its page: the church
    // read before there was a church (null) was still held while loading.
    final backend = MemoryBackend(clock: testClock);
    final cid = backend.addChurch('恩典堂', id: 'grace');
    backend.addMember(cid, const Member(uid: 'u1', name: '王牧師', role: Role.admin));
    backend.auth.signInAs('a@example.com', uid: 'u1');
    var chosen = false;
    final container = ProviderContainer(
      overrides: [
        ...await testOverrides(backend),
        churchDataProvider.overrideWith((ref) => chosen ? EchoingChurchData(backend.church(cid)) : null),
      ],
    );
    addTearDown(container.dispose);
    container.listen(appStageProvider, (_, _) {});
    container.listen(churchProvider, (_, _) {});
    await pumpEventQueue();

    chosen = true;
    container.invalidate(churchDataProvider);
    expect(container.read(appStageProvider), AppStage.loading);
    await pumpEventQueue();
    expect(container.read(appStageProvider), AppStage.ready);
  });

  test('a church that is gone is closed', () async {
    final backend = MemoryBackend(clock: testClock);
    final cid = backend.addChurch('恩典堂', id: 'grace');
    backend.addMember(cid, const Member(uid: 'u1', name: '王牧師', role: Role.admin));
    backend.auth.signInAs('a@example.com', uid: 'u1');
    final container = ProviderContainer(overrides: await testOverrides(backend));
    addTearDown(container.dispose);
    container.listen(appStageProvider, (_, _) {});
    await pumpEventQueue();
    expect(container.read(appStageProvider), AppStage.ready);

    backend.churches.remove(cid);
    backend.notify();
    await pumpEventQueue();
    expect(container.read(appStageProvider), AppStage.churchClosed);
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
