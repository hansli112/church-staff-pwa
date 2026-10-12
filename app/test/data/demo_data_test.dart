import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/languages.dart';
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

  group('the demo church writes in the language the demo opens in', () {
    for (final language in AppLanguage.values) {
      test(language.tag, () {
        final b = demoBackend(language: language);
        final services = demoServicesIn(language);
        expect(b.services['demo']!.services.map((s) => s.name), services.map((s) => s.name));
        for (final (i, s) in services.indexed) {
          expect(
            [s.id, s.weekday, s.duties.length, s.events.length],
            [
              demoServices[i].id,
              demoServices[i].weekday,
              demoServices[i].duties.length,
              demoServices[i].events.length,
            ],
          );
          expect(s.duties.toSet(), hasLength(s.duties.length), reason: 'no duty twice in ${s.name}');
        }
        final names = demoMembers(150, language).map((m) => m.name);
        expect(names.toSet(), hasLength(150), reason: 'no two people with one name');
        if (language == AppLanguage.en) {
          final typed = [
            b.churches['demo']!.name,
            ...services.expand((s) => [s.name, ...s.duties]),
            ...names,
          ];
          expect(typed.where((t) => RegExp(r'[^\x00-\x7F]').hasMatch(t)), isEmpty);
        }
      });
    }
  });
}
