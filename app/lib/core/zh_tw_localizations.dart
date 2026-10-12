import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/date_symbols.dart' as intl;
import 'package:intl/intl.dart' as intl;

/// Flutter's own text (buttons, the date picker, accessibility labels) in
/// Traditional Chinese (Taiwan) only. [GlobalMaterialLocalizations.delegate]
/// and its kin pick from every language Flutter has, so all of them ship:
/// about 65 KB gzipped in the web app, which only speaks zh-TW.
///
/// Their dates are in zh_TW too, where Flutter's own fell back to `zh`
/// (周日 rather than 週日). Loading them also sets up `DateFormat('zh_TW')`
/// for the app's own dates, and makes zh_TW the default locale.
const zhTwLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  _MaterialDelegate(),
  _CupertinoDelegate(),
  _WidgetsDelegate(),
];

/// intl's name for it.
const _intlLocale = 'zh_TW';

bool _supported(Locale locale) => locale.languageCode == 'zh';

bool _dateDataLoaded = false;

void _loadDateData() {
  if (_dateDataLoaded) return;
  initializeDateFormattingCustom(locale: _intlLocale, symbols: zhTwDateSymbols, patterns: zhTwDatePatterns);
  // A DateFormat without a locale takes the default, else the device's,
  // which has no data here.
  intl.Intl.defaultLocale = _intlLocale;
  _dateDataLoaded = true;
}

class _MaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _MaterialDelegate();

  @override
  bool isSupported(Locale locale) => _supported(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    _loadDateData();
    // The same formats as GlobalMaterialLocalizations.delegate.
    return SynchronousFuture(
      MaterialLocalizationZhHantTw(
        fullYearFormat: intl.DateFormat.y(_intlLocale),
        compactDateFormat: intl.DateFormat.yMd(_intlLocale),
        shortDateFormat: intl.DateFormat.yMMMd(_intlLocale),
        mediumDateFormat: intl.DateFormat.MMMEd(_intlLocale),
        longDateFormat: intl.DateFormat.yMMMMEEEEd(_intlLocale),
        yearMonthFormat: intl.DateFormat.yMMMM(_intlLocale),
        shortMonthDayFormat: intl.DateFormat.MMMd(_intlLocale),
        decimalFormat: intl.NumberFormat.decimalPattern(_intlLocale),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', _intlLocale),
      ),
    );
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
    _loadDateData();
    // The same formats as GlobalCupertinoLocalizations.delegate.
    return SynchronousFuture(
      CupertinoLocalizationZhHantTw(
        fullYearFormat: intl.DateFormat.y(_intlLocale),
        dayFormat: intl.DateFormat.d(_intlLocale),
        weekdayFormat: intl.DateFormat.E(_intlLocale),
        mediumDateFormat: intl.DateFormat.MMMEd(_intlLocale),
        singleDigitHourFormat: intl.DateFormat('HH', _intlLocale),
        singleDigitMinuteFormat: intl.DateFormat.m(_intlLocale),
        doubleDigitMinuteFormat: intl.DateFormat('mm', _intlLocale),
        singleDigitSecondFormat: intl.DateFormat.s(_intlLocale),
        decimalFormat: intl.NumberFormat.decimalPattern(_intlLocale),
      ),
    );
  }

  @override
  bool shouldReload(_CupertinoDelegate old) => false;
}

class _WidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _WidgetsDelegate();

  @override
  bool isSupported(Locale locale) => _supported(locale);

  @override
  Future<WidgetsLocalizations> load(Locale locale) => SynchronousFuture(const WidgetsLocalizationZhHantTw());

  @override
  bool shouldReload(_WidgetsDelegate old) => false;
}

// Copied from flutter_localizations' generated_date_localizations.dart
// (Flutter 3.41.0), which holds every locale's. A test checks it still matches.

final zhTwDateSymbols = intl.DateSymbols(
  NAME: 'zh_TW',
  ERAS: const <String>['西元前', '西元'],
  ERANAMES: const <String>['西元前', '西元'],
  NARROWMONTHS: const <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'],
  STANDALONENARROWMONTHS: const <String>[
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
  ],
  MONTHS: const <String>[
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月',
  ],
  STANDALONEMONTHS: const <String>[
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月',
  ],
  SHORTMONTHS: const <String>[
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月',
  ],
  STANDALONESHORTMONTHS: const <String>[
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月',
  ],
  WEEKDAYS: const <String>['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'],
  STANDALONEWEEKDAYS: const <String>['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'],
  SHORTWEEKDAYS: const <String>['週日', '週一', '週二', '週三', '週四', '週五', '週六'],
  STANDALONESHORTWEEKDAYS: const <String>['週日', '週一', '週二', '週三', '週四', '週五', '週六'],
  NARROWWEEKDAYS: const <String>['日', '一', '二', '三', '四', '五', '六'],
  STANDALONENARROWWEEKDAYS: const <String>['日', '一', '二', '三', '四', '五', '六'],
  SHORTQUARTERS: const <String>['第1季', '第2季', '第3季', '第4季'],
  QUARTERS: const <String>['第1季', '第2季', '第3季', '第4季'],
  AMPMS: const <String>['上午', '下午'],
  DATEFORMATS: const <String>['y年M月d日 EEEE', 'y年M月d日', 'y年M月d日', 'y/M/d'],
  TIMEFORMATS: const <String>['Bh:mm:ss [zzzz]', 'Bh:mm:ss [z]', 'Bh:mm:ss', 'Bh:mm'],
  FIRSTDAYOFWEEK: 6,
  WEEKENDRANGE: const <int>[5, 6],
  FIRSTWEEKCUTOFFDAY: 5,
  DATETIMEFORMATS: const <String>['{1} {0}', '{1} {0}', '{1} {0}', '{1} {0}'],
);

const zhTwDatePatterns = <String, String>{
  'd': 'd日',
  'E': 'ccc',
  'EEEE': 'cccc',
  'LLL': 'LLL',
  'LLLL': 'LLLL',
  'M': 'M月',
  'Md': 'M/d',
  'MEd': 'M/d（EEE）',
  'MMM': 'LLL',
  'MMMd': 'M月d日',
  'MMMEd': 'M月d日 EEE',
  'MMMM': 'LLLL',
  'MMMMd': 'M月d日',
  'MMMMEEEEd': 'M月d日 EEEE',
  'QQQ': 'QQQ',
  'QQQQ': 'QQQQ',
  'y': 'y年',
  'yM': 'y/M',
  'yMd': 'y/M/d',
  'yMEd': 'y/M/d（EEE）',
  'yMMM': 'y年M月',
  'yMMMd': 'y年M月d日',
  'yMMMEd': 'y年M月d日 EEE',
  'yMMMM': 'y年M月',
  'yMMMMd': 'y年M月d日',
  'yMMMMEEEEd': 'y年M月d日 EEEE',
  'yQQQ': 'y年QQQ',
  'yQQQQ': 'y年QQQQ',
  'H': 'H時',
  'Hm': 'HH:mm',
  'Hms': 'HH:mm:ss',
  'j': 'ah時',
  'jm': 'ah:mm',
  'jms': 'ah:mm:ss',
  'jmv': 'ah:mm [v]',
  'jmz': 'ah:mm [z]',
  'jz': 'ah時 z',
  'm': 'm',
  'ms': 'mm:ss',
  's': 's',
  'v': 'v',
  'z': 'z',
  'zzzz': 'zzzz',
  'ZZZZ': 'ZZZZ',
};
