import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/state/providers.dart';

void main() {
  test('服事清單今天以教會午夜換日，不以海外装置日期判斷', () {
    final backend = MemoryBackend(clock: () => DateTime.utc(2026, 9, 30, 16, 30));
    final container = ProviderContainer(overrides: [backendProvider.overrideWithValue(backend)]);
    addTearDown(container.dispose);
    expect(container.read(todayProvider), Day(2026, 10, 1));
  });
}
