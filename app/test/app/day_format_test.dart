import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:martha/core/builtin_localizations.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/features/rosters/format.dart';
import 'package:martha/l10n/app_localizations.dart';

/// [language]'s words, its dates set up as the app sets them.
Future<L10n> _in(AppLanguage language) async {
  await builtinLocalizationsDelegates.first.load(language.locale);
  addTearDown(() => Intl.defaultLocale = null);
  return lookupL10n(language.locale);
}

void main() {
  final today = Day(2026, 10, 18);

  test('beside a date block: the weekday, with 今天, 明天 or the year when it applies', () async {
    final l10n = await _in(AppLanguage.zhHant);
    expect(dayBesideBlock(l10n, today, today), '今天 · 週日');
    expect(dayBesideBlock(l10n, Day(2026, 10, 19), today), '明天 · 週一');
    expect(dayBesideBlock(l10n, Day(2026, 10, 24), today), '週六');
    expect(dayBesideBlock(l10n, Day(2027, 4, 11), today), '2027年 · 週日');
  });

  test('the block shows the month as the language shortens it, and reads out the whole day', () async {
    final zh = dayBlock(await _in(AppLanguage.zhHant), Day(2026, 10, 25), today);
    expect((zh.month, zh.day, zh.today, zh.semanticLabel), ('10月', 25, false, '10月25日 週日'));
    final en = dayBlock(await _in(AppLanguage.en), today, today);
    expect((en.month, en.day, en.today), ('Oct', 18, true));
  });
}
