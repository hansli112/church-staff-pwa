import 'dart:ui';

import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'languages.dart';

/// Month and day in short, in the language shown: 10/18, or Oct 18 where
/// the month goes by name ([AppLanguage.monthByName]).
DateFormat shortMonthDay(L10n l10n) {
  // localeName is `zh_Hans` for Simplified Chinese: a script, not a language.
  final [language, ...rest] = l10n.localeName.split('_');
  final script = rest.where((s) => s.length == 4).firstOrNull;
  final shown = AppLanguage.of(Locale.fromSubtags(languageCode: language, scriptCode: script))!;
  return shown.monthByName ? DateFormat.MMMd() : DateFormat.Md();
}
