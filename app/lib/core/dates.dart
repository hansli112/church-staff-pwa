import 'dart:ui';

import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'languages.dart';

/// Month and day in short, in the language shown: 10/18, or Oct 18 where
/// the month goes by name ([AppLanguage.monthByName]).
DateFormat shortMonthDay(L10n l10n) =>
    AppLanguage.of(Locale(l10n.localeName))!.monthByName ? DateFormat.MMMd() : DateFormat.Md();
