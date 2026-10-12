import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/languages.dart';

void main() {
  test('the first language on the device’s list the app speaks', () {
    expect(AppLanguage.resolve(const [Locale('zh', 'TW')]), AppLanguage.zhHant);
    expect(AppLanguage.resolve(const [Locale('en', 'US'), Locale('zh', 'TW')]), AppLanguage.en);
    expect(AppLanguage.resolve(const [Locale('de', 'DE'), Locale('zh', 'TW')]), AppLanguage.zhHant);
    expect(AppLanguage.resolve(const [Locale('en', 'MY')]), AppLanguage.en);
  });

  test('English when the app speaks none of them', () {
    expect(AppLanguage.resolve(const [Locale('de', 'DE'), Locale('fr')]), AppLanguage.en);
    expect(AppLanguage.resolve(const []), AppLanguage.en);
  });

  test('every Chinese is Traditional until Simplified is added', () {
    expect(AppLanguage.resolve(const [Locale('zh', 'CN')]), AppLanguage.zhHant);
    expect(AppLanguage.resolve(const [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')]), AppLanguage.zhHant);
  });

  test('a chosen language is kept by its tag', () {
    for (final language in AppLanguage.values) {
      expect(AppLanguage.fromTag(language.tag), language);
    }
    expect(AppLanguage.fromTag(null), isNull);
    expect(AppLanguage.fromTag('xx'), isNull);
  });
}
