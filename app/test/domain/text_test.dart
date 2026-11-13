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

  // Only the app ranks people by it, so its rows live here.
  group('nameMatch', () {
    test('the same name, spaces, width and case aside, is exact', () {
      expect(nameMatch('王小明', '王 小明'), NameMatch.exact);
      expect(nameMatch('Hans Lee', 'hans lee'), NameMatch.exact);
    });
    test('one name inside the other is partial: a given name, a first name', () {
      expect(nameMatch('小明', '王小明'), NameMatch.partial);
      expect(nameMatch('王小明', '小明'), NameMatch.partial);
      expect(nameMatch('Hans', 'Hans Lee'), NameMatch.partial);
    });
    test('one character is too little to go by', () {
      expect(nameMatch('明', '王小明'), NameMatch.none);
      expect(nameMatch('', '王小明'), NameMatch.none);
    });
    test('different names are none', () {
      expect(nameMatch('陳志明', '林志明'), NameMatch.none);
    });
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
