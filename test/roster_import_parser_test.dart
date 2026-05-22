import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/roster_import_parser.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Build a minimal catalog from a list of (name, color) pairs.
Map<String, EventOption> _catalog(List<(String, int)> entries) {
  return {
    for (final e in entries) e.$1: EventOption(name: e.$1, color: e.$2),
  };
}

/// Run the parser with sensible defaults so tests only need to supply
/// the fields they care about.
RosterImportParseResult _parse(
  String json, {
  List<String> candidates = const [],
  Map<String, Set<String>> allowedByRole = const {},
  Map<String, EventOption> catalog = const {},
  Map<String, String> nameToId = const {},
}) {
  return parseRosterImportJson(
    input: json,
    candidateNames: candidates,
    allowedByRole: allowedByRole,
    catalogByName: catalog,
    nameToIdMap: nameToId,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Basic / backward-compatible behaviour
  // ══════════════════════════════════════════════════════════════════════════

  group('duties-only (既有相容)', () {
    test(
      '1. happy path: only duties, no events key → dutiesProvidedDates contains date; eventsProvidedDates empty',
      () {
        const json = '''
[
  {
    "date": "2026-01-04",
    "duties": [{"role": "敬拜主領", "people": ["待定"]}]
  }
]''';
        final result = _parse(
          json,
          candidates: ['待定'],
          allowedByRole: {
            '敬拜主領': {'待定'},
          },
        );
        expect(result.error, isNull);
        expect(result.dutiesProvidedDates, contains('2026-01-04'));
        expect(result.eventsProvidedDates, isEmpty);
        expect(result.dutiesByDate['2026-01-04'], isNotEmpty);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // events-only
  // ══════════════════════════════════════════════════════════════════════════

  group('events-only', () {
    test(
      '2. no duties key, events: ["聖餐"] → eventsProvidedDates contains date; dutiesProvidedDates empty',
      () {
        const json = '''
[
  {
    "date": "2026-01-04",
    "events": ["聖餐"]
  }
]''';
        final result = _parse(json);
        expect(result.error, isNull);
        expect(result.eventsProvidedDates, contains('2026-01-04'));
        expect(result.dutiesProvidedDates, isEmpty);
        expect(result.eventsByDate['2026-01-04'], equals(['聖餐']));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Mixed duties + events
  // ══════════════════════════════════════════════════════════════════════════

  group('mixed duties + events', () {
    test('3. both keys → both providedDate sets contain the date', () {
      const json = '''
[
  {
    "date": "2026-01-11",
    "duties": [{"role": "司琴", "people": ["待定"]}],
    "events": ["聖餐"]
  }
]''';
      final result = _parse(
        json,
        candidates: ['待定'],
        allowedByRole: {
          '司琴': {'待定'},
        },
      );
      expect(result.error, isNull);
      expect(result.dutiesProvidedDates, contains('2026-01-11'));
      expect(result.eventsProvidedDates, contains('2026-01-11'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Color parsing
  // ══════════════════════════════════════════════════════════════════════════

  group('parseColor', () {
    test('4. hex 6-digit "#F39C12" → 0xFFF39C12', () {
      expect(parseColor('#F39C12'), equals(0xFFF39C12));
    });

    test('5. hex 8-digit "#FFE74C3C" → 0xFFE74C3C', () {
      expect(parseColor('#FFE74C3C'), equals(0xFFE74C3C));
    });

    test('6. int literal → returned unchanged', () {
      expect(parseColor(0xFFF39C12), equals(0xFFF39C12));
    });

    test('7. "0x" string "0xFFF39C12" → 0xFFF39C12', () {
      expect(parseColor('0xFFF39C12'), equals(0xFFF39C12));
    });

    test('8. named color "red" → null (parse failure)', () {
      expect(parseColor('red'), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Color in events → error message
  // ══════════════════════════════════════════════════════════════════════════

  group('color error in events', () {
    test(
      '8b. invalid color in events element → error contains correct row/element',
      () {
        const json = '''
[
  {
    "date": "2026-01-04",
    "events": [{"name": "聖餐", "color": "red"}]
  }
]''';
        final result = _parse(json);
        expect(result.error, contains('第 1 筆 events 第 1 筆 color 格式錯誤'));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Catalog miss / hit
  // ══════════════════════════════════════════════════════════════════════════

  group('event catalog', () {
    test('9. catalog miss → no error; notInEventCatalog contains the name', () {
      const json = '''
[
  {
    "date": "2026-01-04",
    "events": ["不存在的事件"]
  }
]''';
      final result = _parse(json, catalog: _catalog([]));
      expect(result.error, isNull);
      expect(result.notInEventCatalog, contains('不存在的事件'));
    });

    test(
      '10. catalog hit + JSON color override → colorsByDate[date][name] == parsed color',
      () {
        const json = '''
[
  {
    "date": "2026-01-04",
    "events": [{"name": "聖餐", "color": "#000000"}]
  }
]''';
        final result = _parse(
          json,
          catalog: _catalog([('聖餐', 0xFFAAAAAA)]),
        );
        expect(result.error, isNull);
        expect(result.colorsByDate['2026-01-04']?['聖餐'], equals(0xFF000000));
      },
    );

    test(
      '11. catalog hit + no JSON color → colorsByDate[date] does NOT contain key',
      () {
        const json = '''
[
  {
    "date": "2026-01-04",
    "events": ["聖餐"]
  }
]''';
        final result = _parse(json, catalog: _catalog([('聖餐', 0xFFAAAAAA)]));
        expect(result.error, isNull);
        // No explicit color → key must be absent (UI reads from catalog)
        final colors = result.colorsByDate['2026-01-04'];
        expect(colors, isNotNull);
        expect(colors!.containsKey('聖餐'), isFalse);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Explicit empty events array
  // ══════════════════════════════════════════════════════════════════════════

  group('explicit empty events array', () {
    test(
      '12. events: [] → eventsProvidedDates contains date; eventsByDate[date] == []; colorsByDate[date] == {}',
      () {
        const json = '[{"date": "2026-01-04", "events": []}]';
        final result = _parse(json);
        expect(result.error, isNull);
        expect(result.eventsProvidedDates, contains('2026-01-04'));
        expect(result.eventsByDate['2026-01-04'], equals([]));
        expect(result.colorsByDate['2026-01-04'], equals({}));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // events key absent
  // ══════════════════════════════════════════════════════════════════════════

  group('events key absent', () {
    test(
      '13. no events key → eventsProvidedDates does NOT contain the date',
      () {
        const json = '''
[
  {
    "date": "2026-01-04",
    "duties": [{"role": "司琴", "people": ["待定"]}]
  }
]''';
        final result = _parse(
          json,
          candidates: ['待定'],
          allowedByRole: {
            '司琴': {'待定'},
          },
        );
        expect(result.error, isNull);
        expect(result.eventsProvidedDates, isNot(contains('2026-01-04')));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Duplicate event name within day
  // ══════════════════════════════════════════════════════════════════════════

  group('duplicate event name', () {
    test('14. ["聖餐","聖餐"] → error contains 第 1 筆 events 名稱重複：聖餐', () {
      const json = '[{"date": "2026-01-04", "events": ["聖餐", "聖餐"]}]';
      final result = _parse(json);
      expect(result.error, contains('第 1 筆 events 名稱重複：聖餐'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // events not a list
  // ══════════════════════════════════════════════════════════════════════════

  group('events wrong type', () {
    test('15. "events": "聖餐" (string not array) → error: 第 1 筆 events 格式錯誤', () {
      const json = '[{"date": "2026-01-04", "events": "聖餐"}]';
      final result = _parse(json);
      expect(result.error, equals('第 1 筆 events 格式錯誤'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Extra cases
  // ══════════════════════════════════════════════════════════════════════════

  group('extra edge cases', () {
    test('object missing name key → error: 第 1 筆 events 第 1 筆缺少 name', () {
      const json = '[{"date": "2026-01-04", "events": [{"color": "#fff000"}]}]';
      final result = _parse(json);
      expect(result.error, contains('第 1 筆 events 第 1 筆缺少 name'));
    });

    test('trim: "  聖餐 " is treated as "聖餐"', () {
      const json = '[{"date": "2026-01-04", "events": ["  聖餐 "]}]';
      final result = _parse(json, catalog: _catalog([('聖餐', 0xFFAAAAAA)]));
      expect(result.error, isNull);
      expect(result.eventsByDate['2026-01-04'], equals(['聖餐']));
      // Should not appear as catalog miss since trimmed == catalog name
      expect(result.notInEventCatalog, isNot(contains('聖餐')));
    });

    test('duties and events both absent → 第 1 筆需至少包含 duties 或 events', () {
      const json = '[{"date": "2026-01-04"}]';
      final result = _parse(json);
      expect(result.error, equals('第 1 筆需至少包含 duties 或 events'));
    });

    test('empty input → 請貼上 JSON 內容', () {
      final result = _parse('   ');
      expect(result.error, equals('請貼上 JSON 內容'));
    });

    test('not a JSON array at top level → JSON 最外層需為陣列', () {
      final result = _parse('{"date":"2026-01-04","events":[]}');
      expect(result.error, equals('JSON 最外層需為陣列'));
    });

    test('duties key exists but not a List → 第 1 筆 duties 格式錯誤', () {
      const json = '[{"date":"2026-01-04","duties":"wrong"}]';
      final result = _parse(json);
      expect(result.error, equals('第 1 筆 duties 格式錯誤'));
    });

    test(
      'duties present with valid entry + events present → both dates tracked',
      () {
        const json = '''
[
  {
    "date": "2026-02-01",
    "duties": [{"role": "領會", "people": ["待定"]}],
    "events": ["聖餐", {"name": "受洗禮", "color": "#F39C12"}]
  }
]''';
        final result = _parse(
          json,
          candidates: ['待定'],
          allowedByRole: {
            '領會': {'待定'},
          },
          catalog: _catalog([('聖餐', 0xFF000001)]),
        );
        expect(result.error, isNull);
        expect(result.dutiesProvidedDates, contains('2026-02-01'));
        expect(result.eventsProvidedDates, contains('2026-02-01'));
        expect(result.eventsByDate['2026-02-01'], equals(['聖餐', '受洗禮']));
        // 受洗禮 had explicit color in JSON
        expect(
          result.colorsByDate['2026-02-01']?['受洗禮'],
          equals(0xFFF39C12),
        );
        // 聖餐 had no explicit color → not in colorsByDate
        expect(
          result.colorsByDate['2026-02-01']?.containsKey('聖餐'),
          isFalse,
        );
        // 受洗禮 not in catalog
        expect(result.notInEventCatalog, contains('受洗禮'));
        // 聖餐 IS in catalog
        expect(result.notInEventCatalog, isNot(contains('聖餐')));
      },
    );

    test('0x lowercase prefix also parsed correctly', () {
      expect(parseColor('0xfff39c12'), equals(0xFFF39C12));
    });

    test('parseColor: int out of range → null', () {
      expect(parseColor(0x1FFFFFFFF), isNull);
    });

    test('parseColor: empty string → null', () {
      expect(parseColor(''), isNull);
    });

    test('parseColor: "#" with wrong digit count → null', () {
      expect(parseColor('#FFF'), isNull);
      expect(parseColor('#FFFFF'), isNull);
    });
  });
}
