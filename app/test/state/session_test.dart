import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/session.dart';

import '../support/harness.dart';

void main() {
  test('a profile that failed to save (offline) is saved on the next account change', () async {
    final backend = MemoryBackend(clock: testClock)..failNextWrite = Exception('offline');
    final auth = StreamController<AuthUser?>();
    final container = ProviderContainer(
      overrides: [
        ...await testOverrides(backend),
        authUserProvider.overrideWith((ref) => auth.stream),
      ],
    );
    addTearDown(container.dispose);
    container.listen(sessionEffectsProvider, (_, _) {});
    // A new instance each time, as a reload gives: an equal const would not
    // notify listeners.
    // ignore: prefer_const_constructors
    AuthUser user() => AuthUser(uid: 'u1', email: 'a@example.com', emailVerified: true, displayName: '王小明');

    auth.add(user());
    await pumpEventQueue();
    expect(backend.users, isEmpty);

    auth.add(user()); // a token refresh
    await pumpEventQueue();
    expect(backend.users['u1']?.name, '王小明');
  });
}
