import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/fonts.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/data/memory/demo_data.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

/// The app's own strings, read from this checkout.
class _Arb extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());

  // Read at once: the bundle's own decodes a large file on another isolate,
  // which a widget test's clock never waits for.
  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}

/// The text [warmUpFonts] lays out for a page opened at [location] in [language].
Future<String> _warmed(WidgetTester tester, String location, AppLanguage language) async {
  final laidOut = <String>[];
  final fonts = ChangeNotifier();
  addTearDown(fonts.dispose);
  unawaited(
    warmUpFonts(
      bundle: _Arb(),
      systemFonts: fonts,
      languages: [language],
      initialLocation: Uri.parse(location),
      layOut: laidOut.add,
    ),
  );
  await tester.pump();
  fonts.notifyListeners();
  await tester.pump();
  return laidOut.join();
}

/// Chinese characters, kana, Hangul, and the full-width punctuation they
/// use: the ones the engine fetches fonts for.
final _fetched = RegExp(
  r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}　-〿＀-￯]',
  unicode: true,
);

/// Characters drawn on the page at [location] in [language], other than the
/// church's own text, that [warmUpFonts] does not lay out for it.
Future<Set<String>> _unwarmed(WidgetTester tester, MemoryBackend b, String location, AppLanguage language) async {
  await pumpApp(tester, b, deviceLocales: [language.locale]);
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
  final drawn = [for (final t in tester.widgetList<RichText>(find.byType(RichText))) t.text.toPlainText()].join();
  final known = '${await _warmed(tester, location, language)}${churchText(b).join()}';
  return {
    for (final m in _fetched.allMatches(drawn))
      if (!known.contains(m[0]!)) m[0]!,
  };
}

void main() {
  // Each page the warmup picks text for, drawn in each language: whatever
  // of the app's own text it shows, the warmup laid out first.
  for (final language in AppLanguage.values) {
    group(language.tag, () => _pages(language));
  }
}

void _pages(AppLanguage language) {
  testWidgets('the home page', (tester) async {
    expect(await _unwarmed(tester, seededChurch(as: staffMei), '/home', language), isEmpty);
  });

  testWidgets('the sign-in page', (tester) async {
    expect(await _unwarmed(tester, MemoryBackend(clock: testClock), '/login', language), isEmpty);
  });

  testWidgets('the welcome page of an account in no church yet', (tester) async {
    final b = MemoryBackend(clock: testClock);
    b.auth.signInAs('amy@example.com', uid: 'amy', name: 'Amy');
    expect(await _unwarmed(tester, b, '/home', language), isEmpty);
  });

  testWidgets("a service's roster", (tester) async {
    expect(await _unwarmed(tester, seededChurch(), '/rosters/sunday/2026-10-11', language), isEmpty);
  });

  testWidgets('安排服事, opened by its address', (tester) async {
    expect(await _unwarmed(tester, seededChurch(), '/rosters/plan/sunday', language), isEmpty);
  });

  testWidgets("an event's roster", (tester) async {
    final b = seededChurch();
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'xmas', title: '聖誕晚會', start: DateTime(2026, 10, 9, 19), end: DateTime(2026, 10, 9, 21)),
    ];
    final roster = Roster(
      type: '',
      day: Day(2026, 10, 9),
      duties: const [
        Duty(role: '主持', people: ['李美玉'], uids: {'李美玉': 'mei'}),
      ],
      forEvent: RosterEvent(eventId: 'xmas', title: '聖誕晚會', lastDay: Day(2026, 10, 9)),
    );
    b.rosters['grace']![roster.id] = roster;
    expect(await _unwarmed(tester, b, '/rosters/event/xmas', language), isEmpty);
  });

  testWidgets('the language page, each language by its own name', (tester) async {
    expect(await _unwarmed(tester, seededChurch(), '/me/language', language), isEmpty);
  });

  testWidgets('church information', (tester) async {
    expect(await _unwarmed(tester, seededChurch(), '/me/church', language), isEmpty);
  });
}
