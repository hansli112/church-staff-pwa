@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Every language's strings, against the Traditional Chinese ones gen-l10n
// builds the rest from: a string missing in one shows Chinese in the middle
// of it. New strings are translated when they are added (#71).

const _template = 'lib/l10n/app_zh.arb';

Map<String, dynamic> _read(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Set<String> _keys(Map<String, dynamic> arb) => {
  for (final key in arb.keys)
    if (!key.startsWith('@')) key,
};

/// The placeholders [message] uses: `{name}`, or `{count, plural, …}`.
Set<String> _placeholders(String message) => {
  for (final m in RegExp(r'\{(\w+)[},]').allMatches(message)) m.group(1)!,
};

void main() {
  final template = _read(_template);
  final translations = [
    for (final f in Directory('lib/l10n').listSync().whereType<File>())
      if (f.path.endsWith('.arb') && f.path != _template) f.path,
  ];

  test('there are translations', () => expect(translations, isNotEmpty));

  for (final path in translations) {
    test('$path has every string, and only those', () {
      final arb = _read(path);
      expect(_keys(arb).difference(_keys(template)), isEmpty, reason: 'not in $_template');
      expect(_keys(template).difference(_keys(arb)), isEmpty, reason: 'not translated');
    });

    test('$path keeps every string’s placeholders', () {
      final arb = _read(path);
      for (final key in _keys(template)) {
        final declared = <String>{
          ...?((template['@$key'] as Map<String, dynamic>?)?['placeholders'] as Map<String, dynamic>?)?.keys,
        };
        expect(_placeholders(arb[key] as String), declared, reason: key);
      }
    });
  }

  test('Simplified Chinese has none of the commonest Traditional-only characters', () {
    final hans = _read('lib/l10n/app_zh_Hans.arb');
    for (final key in _keys(hans)) {
      expect(hans[key], isNot(matches(RegExp('[們這個說會時來對為國與將從還後過開關點區員號發樂體經應書讓請設資訊權單]'))), reason: key);
    }
  });

  test('English is all English', () {
    final en = _read('lib/l10n/app_en.arb');
    for (final key in _keys(en)) {
      expect(en[key], isNot(matches(RegExp(r'[　-〿一-鿿＀-￯]'))), reason: key);
    }
  });
}
