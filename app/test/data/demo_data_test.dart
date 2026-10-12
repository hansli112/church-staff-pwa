import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/memory/demo_data.dart';
import 'package:martha/domain/day.dart';

void main() {
  test("the demo's rosters start four weeks before the church's today, wherever the phone is", () {
    // Saturday evening in UTC is already Sunday in Taipei, where the demo
    // church is.
    final b = demoBackend(clock: () => DateTime.utc(2026, 10, 10, 20));
    final from = Day(2026, 10, 11).addDays(-28);
    for (final s in demoServices) {
      final first = b.rosters['demo']!.values
          .where((r) => r.type == s.id)
          .map((r) => r.day)
          .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      expect(first, from.nextOnOrAfter(s.weekday), reason: s.name);
    }
  });
}
