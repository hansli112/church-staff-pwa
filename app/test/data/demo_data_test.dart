import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/data/memory/demo_data.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

void main() {
  test("the demo's rosters start four weeks before the church's today, wherever the phone is", () {
    // Saturday evening in UTC is already Sunday in Taipei, where the demo
    // church is.
    final b = demoBackend(clock: () => DateTime.utc(2026, 10, 10, 20));
    final from = Day(2026, 10, 11).addDays(-28);
    for (final s in demoServices) {
      final first = b.rosters['demo']!.values
          .where((r) => r.type == s.id)
          .map((r) => r.day)
          .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      expect(first, from.nextOnOrAfter(s.weekday), reason: s.name);
    }
  });

  test('the person the demo signs in as serves in the coming weeks, so 首頁 has something soon', () {
    final b = demoBackend(clock: () => DateTime.utc(2026, 10, 10, 20));
    final today = Day(2026, 10, 11);
    final mine = b.rosters['demo']!.values
        .where((r) => r.day.compareTo(today) >= 0 && r.day.compareTo(today.addDays(14)) < 0)
        .where((r) => r.duties.any((d) => d.uids.containsValue('m0')));
    expect(mine.length, greaterThanOrEqualTo(2));
  });

  test("the website's church is settled in: nothing on 首頁 to deal with first, and 小組 reporting 人數", () {
    final b = demoBackend(showcase: true, clock: () => DateTime.utc(2026, 10, 10, 20));
    expect(b.churches.keys, ['demo'], reason: 'no other church waiting to be joined');
    expect(b.churchLinks['demo'], isNull);
    expect(b.churches['demo']!.attendanceSince, isNotNull);
    final groups = b.smallGroups['demo']!.values;
    expect(groups.map((g) => g.name), ['喜樂小組', '以馬內利小組']);
    expect(
      [for (final g in groups) b.members['demo']!.values.where((m) => m.smallGroups.contains(g.id)).length],
      [10, 3],
    );
  });

  test("the website's church has the next two weeks arranged and nobody after, for 安排服事 to fill", () {
    final b = demoBackend(showcase: true, clock: () => DateTime.utc(2026, 10, 10, 20));
    final today = Day(2026, 10, 11);
    bool anyone(Roster r) => r.duties.any((d) => d.people.isNotEmpty);
    final ahead = b.rosters['demo']!.values.where((r) => !r.day.isBefore(today));
    expect(ahead.where((r) => r.day.isBefore(today.addDays(14))).any(anyone), isTrue);
    expect(ahead.where((r) => r.day.isAfter(today.addDays(14))).where(anyone), isEmpty);
    expect(
      demoBackend(
        clock: () => DateTime.utc(2026, 10, 10, 20),
      ).rosters['demo']!.values.where((r) => r.day.isAfter(today.addDays(14))).any(anyone),
      isTrue,
      reason: 'the app’s own demo stays arranged ahead',
    );
  });

  group('the demo church writes in the language the demo opens in', () {
    for (final language in AppLanguage.values) {
      test(language.tag, () {
        final b = demoBackend(language: language);
        final services = demoServicesIn(language);
        expect(b.services['demo']!.services.map((s) => s.name), services.map((s) => s.name));
        for (final (i, s) in services.indexed) {
          expect(
            [s.id, s.weekday, s.duties.length, s.events.length],
            [
              demoServices[i].id,
              demoServices[i].weekday,
              demoServices[i].duties.length,
              demoServices[i].events.length,
            ],
          );
          expect(s.duties.toSet(), hasLength(s.duties.length), reason: 'no duty twice in ${s.name}');
        }
        final names = demoMembers(150, language).map((m) => m.name);
        expect(names.toSet(), hasLength(150), reason: 'no two people with one name');
        if (language == AppLanguage.en) {
          final typed = [
            b.churches['demo']!.name,
            ...services.expand((s) => [s.name, ...s.duties]),
            ...names,
          ];
          expect(typed.where((t) => RegExp(r'[^\x00-\x7F]').hasMatch(t)), isEmpty);
        }
      });
    }
  });
}
