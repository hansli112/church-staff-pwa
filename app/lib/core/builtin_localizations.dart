import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/intl.dart' as intl;

import 'date_data.dart';
import 'languages.dart';

/// Flutter's own text (buttons, the date picker, accessibility labels) in
/// the app's languages only. [GlobalMaterialLocalizations.delegate] and its
/// kin pick from every language Flutter has, so all of them ship: about
/// 65 KB gzipped in the web app.
///
/// Traditional Chinese dates are zh_TW's, where Flutter's own fell back to
/// `zh` (周日 rather than 週日). Loading a language also sets up its
/// `DateFormat`s for the app's own dates, and makes it the default locale,
/// so a `DateFormat` given none follows the language shown.
const builtinLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  _MaterialDelegate(),
  _CupertinoDelegate(),
  _WidgetsDelegate(),
];

final _dateDataLoaded = <AppLanguage>{};

/// [locale]'s language, its date data set up and made the default.
AppLanguage _load(Locale locale) {
  final language = AppLanguage.of(locale)!;
  if (_dateDataLoaded.add(language)) {
    final (symbols, patterns) = dateData(language);
    initializeDateFormattingCustom(locale: language.intlLocale, symbols: symbols, patterns: patterns);
  }
  intl.Intl.defaultLocale = language.intlLocale;
  return language;
}

bool _supported(Locale locale) => AppLanguage.of(locale) != null;

class _MaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _MaterialDelegate();

  @override
  bool isSupported(Locale locale) => _supported(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    final language = _load(locale);
    final l = language.intlLocale;
    // The same formats as GlobalMaterialLocalizations.delegate.
    final fullYearFormat = intl.DateFormat.y(l);
    final compactDateFormat = intl.DateFormat.yMd(l);
    final shortDateFormat = intl.DateFormat.yMMMd(l);
    final mediumDateFormat = intl.DateFormat.MMMEd(l);
    final longDateFormat = intl.DateFormat.yMMMMEEEEd(l);
    final yearMonthFormat = intl.DateFormat.yMMMM(l);
    final shortMonthDayFormat = intl.DateFormat.MMMd(l);
    final decimalFormat = intl.NumberFormat.decimalPattern(l);
    final twoDigitZeroPaddedFormat = intl.NumberFormat('00', l);
    return SynchronousFuture(switch (language) {
      AppLanguage.zhHant => MaterialLocalizationZhHantTw(
        fullYearFormat: fullYearFormat,
        compactDateFormat: compactDateFormat,
        shortDateFormat: shortDateFormat,
        mediumDateFormat: mediumDateFormat,
        longDateFormat: longDateFormat,
        yearMonthFormat: yearMonthFormat,
        shortMonthDayFormat: shortMonthDayFormat,
        decimalFormat: decimalFormat,
        twoDigitZeroPaddedFormat: twoDigitZeroPaddedFormat,
      ),
      AppLanguage.en => MaterialLocalizationEn(
        fullYearFormat: fullYearFormat,
        compactDateFormat: compactDateFormat,
        shortDateFormat: shortDateFormat,
        mediumDateFormat: mediumDateFormat,
        longDateFormat: longDateFormat,
        yearMonthFormat: yearMonthFormat,
        shortMonthDayFormat: shortMonthDayFormat,
        decimalFormat: decimalFormat,
        twoDigitZeroPaddedFormat: twoDigitZeroPaddedFormat,
      ),
    });
  }

  @override
  bool shouldReload(_MaterialDelegate old) => false;
}

class _CupertinoDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoDelegate();

  @override
  bool isSupported(Locale locale) => _supported(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    final language = _load(locale);
    final l = language.intlLocale;
    // The same formats as GlobalCupertinoLocalizations.delegate.
    final fullYearFormat = intl.DateFormat.y(l);
    final dayFormat = intl.DateFormat.d(l);
    final weekdayFormat = intl.DateFormat.E(l);
    final mediumDateFormat = intl.DateFormat.MMMEd(l);
    final singleDigitHourFormat = intl.DateFormat('HH', l);
    final singleDigitMinuteFormat = intl.DateFormat.m(l);
    final doubleDigitMinuteFormat = intl.DateFormat('mm', l);
    final singleDigitSecondFormat = intl.DateFormat.s(l);
    final decimalFormat = intl.NumberFormat.decimalPattern(l);
    return SynchronousFuture(switch (language) {
      AppLanguage.zhHant => CupertinoLocalizationZhHantTw(
        fullYearFormat: fullYearFormat,
        dayFormat: dayFormat,
        weekdayFormat: weekdayFormat,
        mediumDateFormat: mediumDateFormat,
        singleDigitHourFormat: singleDigitHourFormat,
        singleDigitMinuteFormat: singleDigitMinuteFormat,
        doubleDigitMinuteFormat: doubleDigitMinuteFormat,
        singleDigitSecondFormat: singleDigitSecondFormat,
        decimalFormat: decimalFormat,
      ),
      AppLanguage.en => CupertinoLocalizationEn(
        fullYearFormat: fullYearFormat,
        dayFormat: dayFormat,
        weekdayFormat: weekdayFormat,
        mediumDateFormat: mediumDateFormat,
        singleDigitHourFormat: singleDigitHourFormat,
        singleDigitMinuteFormat: singleDigitMinuteFormat,
        doubleDigitMinuteFormat: doubleDigitMinuteFormat,
        singleDigitSecondFormat: singleDigitSecondFormat,
        decimalFormat: decimalFormat,
      ),
    });
  }

  @override
  bool shouldReload(_CupertinoDelegate old) => false;
}

class _WidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _WidgetsDelegate();

  @override
  bool isSupported(Locale locale) => _supported(locale);

  @override
  Future<WidgetsLocalizations> load(Locale locale) => SynchronousFuture(switch (AppLanguage.of(locale)!) {
    AppLanguage.zhHant => const WidgetsLocalizationZhHantTw(),
    AppLanguage.en => const WidgetsLocalizationEn(),
  });

  @override
  bool shouldReload(_WidgetsDelegate old) => false;
}
