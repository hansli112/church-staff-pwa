import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/providers.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  Future<ProviderContainer> open(MemoryBackend backend) async {
    final container = ProviderContainer(overrides: await testOverrides(backend));
    addTearDown(container.dispose);
    container.listen(churchProvider, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  test('reads from the church wait until it is open', () async {
    final backend = seededChurch();
    backend.churches['grace'] = backend.churches['grace']!.copyWith(status: ChurchStatus.suspended);
    final container = await open(backend);
    expect(container.read(churchOpenProvider), isFalse);
    expect(() => container.read(servicesProvider.future), throwsA(isA<StateError>()));
  });

  test('sign-out forgets the picked church but keeps it on screen until the account changes', () async {
    final backend = seededChurch();
    final container = await open(backend);
    container.read(selectedChurchProvider.notifier).select('grace');
    await container.read(selectedChurchProvider.notifier).forget();
    expect(container.read(prefsProvider).getString('selected_church'), isNull);
    expect(container.read(currentChurchIdProvider), 'grace');
  });
}
