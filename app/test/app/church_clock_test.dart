import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:martha/core/builtin_localizations.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/common/time_zones.dart';
import 'package:martha/l10n/app_localizations.dart';

/// [language]'s words, its dates set up as the app sets them.
Future<L10n> _in(AppLanguage language) async {
  await builtinLocalizationsDelegates.first.load(language.locale);
  addTearDown(() => Intl.defaultLocale = null);
  return lookupL10n(language.locale);
}

void main() {
  // 07:30 on Oct 19 in Taipei; still Oct 18 in Los Angeles, in summer time.
  final instant = DateTime.utc(2026, 10, 18, 23, 30);

  test("every time shown is on the church's clock, not the phone's", () async {
    final clock = ChurchClock(await _in(AppLanguage.zhHant), ChurchTimeZone.losAngeles);
    expect(clock.moment(instant), '10/18 16:30');
    expect(clock.day(instant), '10月18日');
    expect(clock.dayWithYear(instant), '2026年10月18日');
    expect(ChurchClock(await _in(AppLanguage.zhHant), ChurchTimeZone.taipei).moment(instant), '10/19 07:30');
  });

  test('in English the month goes by name', () async {
    final clock = ChurchClock(await _in(AppLanguage.en), ChurchTimeZone.losAngeles);
    expect(clock.moment(instant), 'Oct 18 16:30');
    expect(clock.day(instant), 'Oct 18');
    expect(clock.dayWithYear(instant), 'Oct 18, 2026');
  });

  test('every language the app speaks shows a time, Simplified Chinese too', () async {
    for (final language in AppLanguage.values) {
      expect(
        ChurchClock(await _in(language), ChurchTimeZone.taipei).moment(instant),
        contains('7:30'),
        reason: '$language',
      );
    }
  });
}
