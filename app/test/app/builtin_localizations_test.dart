import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// The full table Flutter ships, to check the copies of the app's languages.
// ignore: implementation_imports
import 'package:flutter_localizations/src/l10n/generated_date_localizations.dart' as flutter_dates;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbols.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:martha/core/builtin_localizations.dart';
import 'package:martha/core/date_data.dart';
import 'package:martha/core/languages.dart';

/// Ours for [T], loaded for [language].
Future<T> _load<T>(AppLanguage language) async {
  final delegate = builtinLocalizationsDelegates.whereType<LocalizationsDelegate<T>>().single;
  expect(delegate.isSupported(language.locale), isTrue);
  return delegate.load(language.locale);
}

/// What the app keeps from Flutter 3.41 where 3.50 changed it, by
/// language tag: date symbols by name, patterns by skeleton. The phones'
/// builds are still on 3.41 (Shorebird keeps a release's Flutter), and the
/// web's should not differ from them; Simplified Chinese weeks starting on
/// Monday and 2026/11 for 2026年11月 are a change to decide on, not to take
/// with an upgrade.
const _keptFrom341 = <String, Set<String>>{
  'zh-Hans': {'FIRSTDAYOFWEEK', 'FIRSTWEEKCUTOFFDAY', 'yM'},
  'en': {'TIMEFORMATS', 'DATETIMEFORMATS', 'j', 'jm', 'jms', 'jmv', 'jmz', 'jz'},
  'ko': {'DATEFORMATS'},
};

void _expectSame(DateSymbols symbols, DateSymbols flutter, Set<String> kept) {
  expect(symbols.NAME, flutter.NAME);
  for (final (name, a, b) in <(String, Object?, Object?)>[
    ('NAME', symbols.NAME, flutter.NAME),
    ('ERAS', symbols.ERAS, flutter.ERAS),
    ('ERANAMES', symbols.ERANAMES, flutter.ERANAMES),
    ('NARROWMONTHS', symbols.NARROWMONTHS, flutter.NARROWMONTHS),
    ('STANDALONENARROWMONTHS', symbols.STANDALONENARROWMONTHS, flutter.STANDALONENARROWMONTHS),
    ('MONTHS', symbols.MONTHS, flutter.MONTHS),
    ('STANDALONEMONTHS', symbols.STANDALONEMONTHS, flutter.STANDALONEMONTHS),
    ('SHORTMONTHS', symbols.SHORTMONTHS, flutter.SHORTMONTHS),
    ('STANDALONESHORTMONTHS', symbols.STANDALONESHORTMONTHS, flutter.STANDALONESHORTMONTHS),
    ('WEEKDAYS', symbols.WEEKDAYS, flutter.WEEKDAYS),
    ('STANDALONEWEEKDAYS', symbols.STANDALONEWEEKDAYS, flutter.STANDALONEWEEKDAYS),
    ('SHORTWEEKDAYS', symbols.SHORTWEEKDAYS, flutter.SHORTWEEKDAYS),
    ('STANDALONESHORTWEEKDAYS', symbols.STANDALONESHORTWEEKDAYS, flutter.STANDALONESHORTWEEKDAYS),
    ('NARROWWEEKDAYS', symbols.NARROWWEEKDAYS, flutter.NARROWWEEKDAYS),
    ('STANDALONENARROWWEEKDAYS', symbols.STANDALONENARROWWEEKDAYS, flutter.STANDALONENARROWWEEKDAYS),
    ('SHORTQUARTERS', symbols.SHORTQUARTERS, flutter.SHORTQUARTERS),
    ('QUARTERS', symbols.QUARTERS, flutter.QUARTERS),
    ('AMPMS', symbols.AMPMS, flutter.AMPMS),
    ('DATEFORMATS', symbols.DATEFORMATS, flutter.DATEFORMATS),
    ('TIMEFORMATS', symbols.TIMEFORMATS, flutter.TIMEFORMATS),
    ('DATETIMEFORMATS', symbols.DATETIMEFORMATS, flutter.DATETIMEFORMATS),
    ('WEEKENDRANGE', symbols.WEEKENDRANGE, flutter.WEEKENDRANGE),
    ('FIRSTDAYOFWEEK', symbols.FIRSTDAYOFWEEK, flutter.FIRSTDAYOFWEEK),
    ('FIRSTWEEKCUTOFFDAY', symbols.FIRSTWEEKCUTOFFDAY, flutter.FIRSTWEEKCUTOFFDAY),
    ('FIRSTDAYOFWEEK', symbols.FIRSTDAYOFWEEK, flutter.FIRSTDAYOFWEEK),
    ('FIRSTWEEKCUTOFFDAY', symbols.FIRSTWEEKCUTOFFDAY, flutter.FIRSTWEEKCUTOFFDAY),
  ]) {
    if (!kept.contains(name)) expect(a, b, reason: name);
  }
}

void main() {
  final day = DateTime(2026, 10, 18, 9, 5);

  // Flutter's own delegates would set up the date data for every locale and
  // hide a missing one, so comparing with them is in another file (each
  // test file runs on its own).
  test('dates are written as in Taiwan, in the date picker too', () async {
    final material = await _load<MaterialLocalizations>(AppLanguage.zhHant);
    expect(material.formatMediumDate(day), '10月18日 週日');
    expect(material.formatFullDate(day), '2026年10月18日 星期日');
    expect(material.formatMonthYear(day), '2026年10月');
    expect(material.formatYear(day), '2026年');
    final cupertino = await _load<CupertinoLocalizations>(AppLanguage.zhHant);
    expect(cupertino.datePickerMediumDate(day), '10月18日 週日');
  });

  test('in Simplified Chinese, with 周', () async {
    final material = await _load<MaterialLocalizations>(AppLanguage.zhHans);
    expect(material.formatMediumDate(day), '10月18日周日');
    expect(material.okButtonLabel, '确定');
    expect(DateFormat.MMMEd().format(day), '10月18日周日');
  });

  test('in Japanese and Korean', () async {
    expect((await _load<MaterialLocalizations>(AppLanguage.ja)).formatMediumDate(day), '10月18日(日)');
    expect(DateFormat.MMMEd().format(day), '10月18日(日)');
    expect((await _load<MaterialLocalizations>(AppLanguage.ko)).formatMediumDate(day), '10월 18일 (일)');
    expect(DateFormat.MMMEd().format(day), '10월 18일 (일)');
  });

  test('in English, with the month by name', () async {
    final material = await _load<MaterialLocalizations>(AppLanguage.en);
    expect(material.formatMediumDate(day), 'Sun, Oct 18');
    expect(material.formatMonthYear(day), 'October 2026');
    expect(material.okButtonLabel, 'OK');
    final cupertino = await _load<CupertinoLocalizations>(AppLanguage.en);
    expect(cupertino.datePickerMediumDate(day), 'Sun, Oct 18');
  });

  test('the app’s own dates follow the language last loaded', () async {
    await _load<MaterialLocalizations>(AppLanguage.zhHant);
    expect(DateFormat.MMMEd().format(day), '10月18日 週日');
    expect(DateFormat.yMMMM().format(day), '2026年10月');
    expect(DateFormat.Hm().format(day), '09:05');
    await _load<MaterialLocalizations>(AppLanguage.en);
    expect(DateFormat.MMMEd().format(day), 'Sun, Oct 18');
    expect(DateFormat.MMMd().add_Hm().format(day), 'Oct 18 09:05');
    await _load<CupertinoLocalizations>(AppLanguage.zhHant);
    expect(DateFormat.MMMEd().format(day), '10月18日 週日');
  });

  test('each language’s date data is Flutter’s, as is', () {
    for (final language in AppLanguage.values) {
      final (symbols, patterns) = dateData(language);
      final kept = _keptFrom341[language.tag] ?? const <String>{};
      _expectSame(symbols, flutter_dates.dateSymbols[language.intlLocale]!, kept);
      final flutter = flutter_dates.datePatterns[language.intlLocale]!;
      expect(patterns.keys.toSet(), flutter.keys.toSet(), reason: language.tag);
      for (final MapEntry(:key, :value) in patterns.entries) {
        if (!kept.contains(key)) expect(value, flutter[key], reason: '${language.tag} $key');
      }
    }
  });

  test('every language the app speaks has Flutter’s text', () {
    for (final language in AppLanguage.values) {
      for (final delegate in builtinLocalizationsDelegates) {
        expect(delegate.isSupported(language.locale), isTrue, reason: '$language ${delegate.type}');
      }
    }
  });
}
