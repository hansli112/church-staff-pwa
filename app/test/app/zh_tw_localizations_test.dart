import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// The full table Flutter ships, to check the copy of its zh_TW entry.
// ignore: implementation_imports
import 'package:flutter_localizations/src/l10n/generated_date_localizations.dart' as flutter_dates;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:martha/core/zh_tw_localizations.dart';

const _zhTw = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW');

/// Ours for [T], loaded for zh-TW.
Future<T> _load<T>() async {
  final delegate = zhTwLocalizationsDelegates.whereType<LocalizationsDelegate<T>>().single;
  expect(delegate.isSupported(_zhTw), isTrue);
  return delegate.load(_zhTw);
}

void main() {
  final day = DateTime(2026, 10, 18, 9, 5);

  // Flutter's own delegates would set up the date data for every locale and
  // hide a missing zh_TW, so comparing with them is in another file (each
  // test file runs on its own).
  test('dates are written as in Taiwan, in the date picker too', () async {
    final material = await _load<MaterialLocalizations>();
    expect(material.formatMediumDate(day), '10月18日 週日');
    expect(material.formatFullDate(day), '2026年10月18日 星期日');
    expect(material.formatMonthYear(day), '2026年10月');
    expect(material.formatYear(day), '2026年');
    final cupertino = await _load<CupertinoLocalizations>();
    expect(cupertino.datePickerMediumDate(day), '10月18日 週日');
  });

  test('the app’s own DateFormat(zh_TW) works once they are loaded', () async {
    await _load<MaterialLocalizations>();
    expect(DateFormat.MMMEd('zh_TW').format(day), '10月18日 週日');
    expect(DateFormat.yMMMM('zh_TW').format(day), '2026年10月');
    expect(DateFormat.Hm('zh_TW').format(day), '09:05');
    // Without a locale too: the device's (en_US in tests) has no data here.
    expect(DateFormat('M/d HH:mm').format(day), '10/18 09:05');
  });

  test('the zh_TW date data is Flutter’s, as is', () {
    final symbols = zhTwDateSymbols;
    final flutter = flutter_dates.dateSymbols['zh_TW']!;
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
    expect(zhTwDatePatterns, flutter_dates.datePatterns['zh_TW']);
  });
}
