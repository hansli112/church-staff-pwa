import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:martha/core/app_update_gateway.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/app_update.dart';

import '../support/harness.dart';
import 'calendar_test.dart' show CalendarBackend;

class Updates implements AppUpdateGateway {
  @override
  String runningVersion = 'running-release';
  @override
  final supported = true;
  Completer<void>? activating;
  int reloads = 0;
  @override
  Future<AppUpdateCheck> check() async => const AppUpdateCheck(available: true, version: 'new-release');
  @override
  Future<void> activate() async {
    await activating?.future;
  }

  @override
  void setEditing(bool editing) {}
  @override
  void reload() {
    reloads++;
  }
}

void main() {
  test('update activation cannot reload if a draft starts while waiting for the worker', () async {
    final backend = CalendarBackend();
    final updates = Updates();
    final container = ProviderContainer(
      overrides: [
        ...await testOverrides(backend),
        appUpdateGatewayProvider.overrideWithValue(updates),
        appUpdateLocationProvider.overrideWithValue(() => '/me'),
      ],
    );
    addTearDown(container.dispose);
    container.listen(appStageProvider, (_, _) {});
    container.listen(meProvider, (_, _) {});
    await pumpEventQueue();
    final action = container.read(appUpdateProvider.notifier);
    await action.check();
    expect(container.read(appUpdateProvider).runningVersion, 'running-release');
    updates.activating = Completer<void>();
    final applying = action.apply();
    await pumpEventQueue();
    final release = container.read(updateEditLockProvider).begin();
    updates.activating!.complete();
    await expectLater(applying, throwsA(isA<UpdateRejected>()));
    expect(updates.reloads, 0);
    release();
  });

  for (final (location, reloads) in [('/me/about', true), ('/me/profile', false)]) {
    test('updating reloads from 設定 or 關於, nowhere else: $location', () async {
      final updates = Updates();
      final container = ProviderContainer(
        overrides: [
          ...await testOverrides(CalendarBackend()),
          appUpdateGatewayProvider.overrideWithValue(updates),
          appUpdateLocationProvider.overrideWithValue(() => location),
        ],
      );
      addTearDown(container.dispose);
      container.listen(appStageProvider, (_, _) {});
      container.listen(meProvider, (_, _) {});
      await pumpEventQueue();
      final action = container.read(appUpdateProvider.notifier);
      await action.check();
      final applying = action.apply();
      await (reloads ? expectLater(applying, completes) : expectLater(applying, throwsA(isA<UpdateRejected>())));
      expect(updates.reloads, reloads ? 1 : 0);
    });
  }

  test('edit leases remain locked through pending work and release exactly once', () async {
    final locks = UpdateEditLock();
    final release = locks.begin();
    expect(locks.locked, isTrue);
    final pending = Completer<void>();
    final write = locks.during(() => pending.future);
    release();
    release();
    expect(locks.locked, isTrue);
    pending.complete();
    await write;
    expect(locks.locked, isFalse);
  });
}
