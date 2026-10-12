import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/languages.dart';

/// The rows functions/test/languages.test.ts runs too: both sides must agree.
final _languages = jsonDecode(File('../testdata/languages.json').readAsStringSync()) as Map<String, dynamic>;

/// A device's locale for a BCP 47 tag: language, then a script (4 letters) or a region.
Locale _locale(String tag) {
  final [language, ...rest] = tag.split('-');
  final script = rest.where((s) => s.length == 4).firstOrNull;
  final region = rest.where((s) => s.length != 4).firstOrNull;
  return Locale.fromSubtags(languageCode: language, scriptCode: script, countryCode: region);
}

void main() {
  group('the first language on the device’s list the app speaks', () {
    for (final r in (_languages['preferred'] as List).cast<Map<String, dynamic>>()) {
      test(r['why'] as String, () {
        expect(
          AppLanguage.resolve([for (final tag in (r['preferred'] as List).cast<String>()) _locale(tag)]).tag,
          r['language'],
        );
      });
    }
  });

  test('a chosen language is kept by its tag', () {
    for (final language in AppLanguage.values) {
      expect(AppLanguage.fromTag(language.tag), language);
    }
    expect(AppLanguage.fromTag(null), isNull);
    expect(AppLanguage.fromTag('xx'), isNull);
  });
}
