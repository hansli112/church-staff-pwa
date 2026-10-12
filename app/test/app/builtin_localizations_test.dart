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

void _expectSame(DateSymbols symbols, DateSymbols flutter) {
  expect(symbols.NAME, flutter.NAME);
  for (final (a, b) in [
    (symbols.ERAS, flutter.ERAS),
    (symbols.ERANAMES, flutter.ERANAMES),
    (symbols.NARROWMONTHS, flutter.NARROWMONTHS),
    (symbols.STANDALONENARROWMONTHS, flutter.STANDALONENARROWMONTHS),
    (symbols.MONTHS, flutter.MONTHS),
    (symbols.STANDALONEMONTHS, flutter.STANDALONEMONTHS),
    (symbols.SHORTMONTHS, flutter.SHORTMONTHS),
    (symbols.STANDALONESHORTMONTHS, flutter.STANDALONESHORTMONTHS),
    (symbols.WEEKDAYS, flutter.WEEKDAYS),
    (symbols.STANDALONEWEEKDAYS, flutter.STANDALONEWEEKDAYS),
    (symbols.SHORTWEEKDAYS, flutter.SHORTWEEKDAYS),
    (symbols.STANDALONESHORTWEEKDAYS, flutter.STANDALONESHORTWEEKDAYS),
    (symbols.NARROWWEEKDAYS, flutter.NARROWWEEKDAYS),
    (symbols.STANDALONENARROWWEEKDAYS, flutter.STANDALONENARROWWEEKDAYS),
    (symbols.SHORTQUARTERS, flutter.SHORTQUARTERS),
    (symbols.QUARTERS, flutter.QUARTERS),
    (symbols.AMPMS, flutter.AMPMS),
    (symbols.DATEFORMATS, flutter.DATEFORMATS),
    (symbols.TIMEFORMATS, flutter.TIMEFORMATS),
    (symbols.DATETIMEFORMATS, flutter.DATETIMEFORMATS),
    (symbols.WEEKENDRANGE, flutter.WEEKENDRANGE),
  ]) {
    expect(a, b);
  }
  expect(symbols.FIRSTDAYOFWEEK, flutter.FIRSTDAYOFWEEK);
  expect(symbols.FIRSTWEEKCUTOFFDAY, flutter.FIRSTWEEKCUTOFFDAY);
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
    _expectSame(zhTwDateSymbols, flutter_dates.dateSymbols['zh_TW']!);
    expect(zhTwDatePatterns, flutter_dates.datePatterns['zh_TW']);
    _expectSame(enDateSymbols, flutter_dates.dateSymbols['en']!);
    expect(enDatePatterns, flutter_dates.datePatterns['en']);
  });

  test('every language the app speaks has Flutter’s text', () {
    for (final language in AppLanguage.values) {
      for (final delegate in builtinLocalizationsDelegates) {
        expect(delegate.isSupported(language.locale), isTrue, reason: '$language ${delegate.type}');
      }
    }
  });
}
