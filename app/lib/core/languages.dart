import 'package:flutter/widgets.dart';

/// The languages the app is written in. Each has its ARB file in lib/l10n,
/// and Flutter's own text and date data in builtin_localizations.dart.
enum AppLanguage {
  zhHant(
    tag: 'zh-Hant',
    locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
    intlLocale: 'zh_TW',
    label: '繁體中文',
    monthByName: false,
    emailLanguage: 'zh-TW',
  ),
  en(tag: 'en', locale: Locale('en'), intlLocale: 'en', label: 'English', monthByName: true, emailLanguage: 'en')
  ;

  const AppLanguage({
    required this.tag,
    required this.locale,
    required this.intlLocale,
    required this.label,
    required this.monthByName,
    required this.emailLanguage,
  });

  /// Kept on the profile when chosen (`users/{uid}.locale`), and as the one
  /// shown (`users/{uid}.appLocale`) for the server's pushes.
  final String tag;

  final Locale locale;

  /// intl's name for its dates.
  final String intlLocale;

  /// Its name in itself, the same whatever language is shown.
  final String label;

  /// Short dates name the month (Oct 18): 10/18 reads one way in America
  /// and the other in Malaysia.
  final bool monthByName;

  /// Firebase Auth's code for the verification and password reset emails
  /// it sends in this language.
  final String emailLanguage;

  /// The language [context] is shown in.
  static AppLanguage shownIn(BuildContext context) => of(Localizations.localeOf(context))!;

  static AppLanguage? fromTag(String? tag) => values.where((l) => l.tag == tag).firstOrNull;

  /// The language for a device or browser asking for [locale], if the app
  /// speaks it. Every Chinese is Traditional until Simplified is added.
  static AppLanguage? of(Locale locale) => switch (locale.languageCode) {
    'zh' => zhHant,
    'en' => en,
    _ => null,
  };

  /// Following the device: the first language on its list the app speaks,
  /// else English, which more people read than Chinese.
  static AppLanguage resolve(Iterable<Locale> preferred) => preferred.map(of).nonNulls.firstOrNull ?? en;
}
