import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/swap.dart';

/// The rows functions/test/swaps.test.ts runs too: both sides must agree.
final _rules = jsonDecode(File('../testdata/swaps.json').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _rows(String name) => (_rules[name] as List).cast<Map<String, dynamic>>();

List<Duty> _duties(Object? list) => [
  for (final d in list as List)
    Duty(
      role: d['role'] as String,
      people: (d['people'] as List).cast<String>(),
      uids: (d['uids'] as Map).cast<String, String>(),
    ),
];

void main() {
  group('coverAsked', () {
    for (final r in _rows('coverAsked')) {
      test(r['why'] as String, () {
        final members = [
          for (final m in r['members'] as List)
            Member(
              uid: m['uid'] as String,
              name: m['uid'] as String,
              zones: [
                for (final z in m['zones'] as List)
                  Zone(serviceType: z['serviceType'] as String, duties: (z['duties'] as List).cast<String>()),
              ],
            ),
        ];
        final away = {
          for (final MapEntry(:key, :value) in (r['away'] as Map).entries)
            key as String: [
              for (final s in value as List)
                UnavailableSpan(Day.parse(s['from'] as String), Day.parse(s['to'] as String)),
            ].fold(const UnavailableDays(), (days, s) => days.add(s.from, s.to)),
        };
        final roster = Roster(
          type: r['service'] as String,
          day: Day.parse(r['dateKey'] as String),
          duties: _duties(r['duties']),
        );
        expect(coverAsked(members, roster, r['duty'] as String, r['from'] as String, unavailable: away), r['asked']);
      });
    }
  });

  group('stillHolds', () {
    for (final r in _rows('stillHolds')) {
      test(r['why'] as String, () {
        final day = Day(2026, 11, 15);
        final other = Day(2026, 11, 22);
        final request = SwapRequest(
          id: 'r',
          kind: SwapKind.values.byName(r['kind'] as String),
          serviceId: 'sunday',
          day: day,
          duty: r['duty'] as String,
          from: r['from'] as String,
          fromName: '',
          to: r['to'] as String?,
          toDay: r['to'] == null ? null : other,
        );
        Roster? on(Day d, Object? duties) =>
            duties == null ? null : Roster(type: 'sunday', day: d, duties: _duties(duties));
        expect(swapStillHolds(request, on(day, r['duties']), on(other, r['other'])), r['holds']);
      });
    }
  });

  test('taking it puts the taker where who asked was, and keeps the rest', () {
    final roster = Roster(
      type: 'sunday',
      day: Day(2026, 11, 15),
      duties: const [
        Duty(role: '招待', people: ['王小明', '陳志豪'], uids: {'王小明': 'wang', '陳志豪': 'hao'}),
      ],
    );
    expect(
      replacedOnDuty(roster, '招待', 'wang', 'mei', '李美玉').duties.single,
      const Duty(role: '招待', people: ['李美玉', '陳志豪'], uids: {'陳志豪': 'hao', '李美玉': 'mei'}),
    );
  });
}
