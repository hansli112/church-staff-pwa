import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/state/providers.dart';

void main() {
  test('today turns over at midnight while the app stays open', () {
    fakeAsync((async) {
      final start = DateTime(2026, 10, 1, 23, 30);
      DateTime now() => start.add(async.elapsed);
      final container = ProviderContainer(
        overrides: [backendProvider.overrideWithValue(MemoryBackend(clock: now))],
      );
      addTearDown(container.dispose);
      final seen = <Day>[];
      container.listen(todayProvider, (_, day) => seen.add(day), fireImmediately: true);

      async.elapse(const Duration(minutes: 29));
      expect(seen, [Day(2026, 10, 1)]);

      async.elapse(const Duration(minutes: 2));
      expect(seen, [Day(2026, 10, 1), Day(2026, 10, 2)]);
    });
  });
}
