import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/roster_news.dart';

// testdata/roster_changes.json, which functions/src/rosterNews.ts runs too.
void main() {
  final data = jsonDecode(File('../testdata/roster_changes.json').readAsStringSync()) as Map<String, dynamic>;
  List<String>? roles(Object? v) => v == null ? null : [...(v as List).cast<String>()];

  group('where a roster change came from', () {
    final rows = (data['via'] as List).cast<Map<String, dynamic>>();

    test('the app writes what the table says it does, and nothing else', () {
      expect(RosterVia.values.map((v) => v.name), [
        for (final r in rows)
          if (r['by'] == 'app') r['via'],
      ]);
    });

    for (final r in rows.where((r) => r['by'] == 'app')) {
      test('${r['via']} waits for 通知同工 only when the table says so', () {
        expect(RosterVia.values.byName(r['via'] as String).waitsForNotice, r['tells'] == 'planned');
      });
    }
  });

  group('what waits for 通知同工', () {
    for (final c in (data['planned'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final next = plannedAfter(
          roles(c['waiting']),
          before: roles(c['before'])!,
          after: roles(c['after'])!,
          told: c['told'] as bool,
        );
        expect(next?.toSet(), roles(c['next'])?.toSet());
      });
    }
  });
}
