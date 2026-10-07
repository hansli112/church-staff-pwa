import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/limits.dart';
import 'package:martha/domain/text.dart';

/// The rows functions/test/text.test.ts runs too: both sides must agree.
final _rules = jsonDecode(File('../testdata/text_rules.json').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _rows(String name) => (_rules[name] as List).cast<Map<String, dynamic>>();

void main() {
  group('foldWidthAndCase', () {
    for (final r in _rows('foldWidthAndCase')) {
      test(r['why'] as String, () => expect(foldWidthAndCase(r['in'] as String), r['out']));
    }
  });

  group('nameKey', () {
    for (final r in _rows('nameKey')) {
      test(r['why'] as String, () => expect(nameKey(r['in'] as String), r['out']));
    }
  });

  group('matchesSearch', () {
    for (final r in _rows('matchesSearch')) {
      test(r['why'] as String, () => expect(matchesSearch(r['name'] as String, r['query'] as String), r['matches']));
    }
  });

  group('characterCount', () {
    for (final r in _rows('characterCount')) {
      test(r['why'] as String, () => expect(characterCount(r['in'] as String), r['count']));
    }
  });

  group('withinTextLimit', () {
    for (final r in _rows('withinTextLimit')) {
      test(r['why'] as String, () => expect(withinTextLimit(r['in'] as String, r['max'] as int), r['within']));
    }
  });
}
