import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/roster_import_parser.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Build a minimal catalog from a list of (name, color) pairs.
Map<String, EventOption> _catalog(List<(String, int)> entries) {
  return {for (final e in entries) e.$1: EventOption(name: e.$1, color: e.$2)};
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
        final result = _parse(json, catalog: _catalog([('聖餐', 0xFFAAAAAA)]));
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
    test(
      '15. "events": "聖餐" (string not array) → error: 第 1 筆 events 格式錯誤',
      () {
        const json = '[{"date": "2026-01-04", "events": "聖餐"}]';
        final result = _parse(json);
        expect(result.error, equals('第 1 筆 events 格式錯誤'));
      },
    );
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
        expect(result.colorsByDate['2026-02-01']?['受洗禮'], equals(0xFFF39C12));
        // 聖餐 had no explicit color → not in colorsByDate
        expect(result.colorsByDate['2026-02-01']?.containsKey('聖餐'), isFalse);
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

  // ══════════════════════════════════════════════════════════════════════════
  // 沒對到的名字一律照樣匯入
  //
  // 以前這三種都是直接丟掉，那格變成「待定」，同一格還有別人時甚至完全沒有
  // 痕跡。臨時支援別的崇拜是正常狀況，不該被當成髒資料刪掉。
  // ══════════════════════════════════════════════════════════════════════════

  group('未匹配的名字照樣匯入', () {
    const db = ['王大明', '李小華', '陳大明'];
    // 王大明 只被設定為司琴，沒有招待。
    const allowed = {
      '司琴': {'王大明'},
      '招待': {'李小華'},
    };
    const ids = {'王大明': 'uid-daming', '李小華': 'uid-xiaohua'};

    RosterImportParseResult run(String people, {String role = '招待'}) => _parse(
      '[{"date":"2026-01-04","duties":[{"role":"$role","people":$people}]}]',
      candidates: db,
      allowedByRole: allowed,
      nameToId: ids,
    );

    RosterEntry dutyOf(RosterImportParseResult r) =>
        r.dutiesByDate['2026-01-04']!.single;

    test('沒設定該服事的人照樣排進去，uid 也留著', () {
      final r = run('["王大明"]');
      expect(dutyOf(r).people, ['王大明']);
      expect(
        dutyOf(r).personIdsByName['王大明'],
        'uid-daming',
        reason: '人是名單上的真人，uid 查得到就該帶上，否則收不到服事提醒',
      );
      expect(r.roleMismatchNames, ['王大明'], reason: '照樣匯入不等於不用報告');
      expect(r.roleMismatchDetails['王大明'], contains('招待'));
    });

    test('不在名單的人以純文字排進去，但沒有 uid', () {
      final r = run('["陳訪客"]');
      expect(dutyOf(r).people, ['陳訪客']);
      expect(dutyOf(r).personIdsByName, isEmpty);
      expect(r.notInRosterNames, ['陳訪客']);
    });

    test('對到多個同名的人時保留原字串', () {
      // 「大明」同時是 王大明 與 陳大明 的結尾，系統無從判斷。
      final r = run('["大明"]', role: '司琴');
      expect(dutyOf(r).people, ['大明']);
      expect(dutyOf(r).personIdsByName, isEmpty);
      expect(r.otherNames, ['大明']);
    });

    test('同一格混合時不會有人靜靜消失', () {
      // 這格最容易出事：以前畫面只顯示「李小華」，看起來完全正常，
      // 沒有任何跡象顯示少了一個人。
      final r = run('["李小華","王大明"]');
      expect(dutyOf(r).people, ['李小華', '王大明']);
      expect(dutyOf(r).personIdsByName, {
        '李小華': 'uid-xiaohua',
        '王大明': 'uid-daming',
      });
    });

    test('真的沒填人時才會是待定', () {
      final r = run('[]');
      expect(dutyOf(r).people, ['待定']);
    });

    test('非字串的元素會停下來說明是哪一筆，不會被靜靜濾掉', () {
      // 以前 whereType<String>() 直接濾掉 null 與數字，既不寫進表也不進報告
      // —— 牆上寫兩個人、app 顯示一個，比 roleMismatch 更難察覺。
      expect(run('["李小華", null]').error, '第 1 筆 duties 第 1 筆 people 第 2 個不是文字');
      expect(
        run('["李小華", 12345]').error,
        '第 1 筆 duties 第 1 筆 people 第 2 個不是文字',
      );
    });

    test('空字串仍然略過（那不是名字）', () {
      final r = run('["李小華", "", "  "]');
      expect(r.error, isNull);
      expect(dutyOf(r).people, ['李小華']);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // orderDutiesByTemplate — 匯入後的排序規格
  //
  // 規格是「一律照樣板排」，JSON 自己的順序不算數。這一組就是這條規則的
  // 白紙黑字，改動排序邏輯前先看這裡。
  // ══════════════════════════════════════════════════════════════════════════

  group('orderDutiesByTemplate（照樣板排）', () {
    List<String> rolesOf(List<RosterEntry> duties) =>
        duties.map((d) => d.role).toList();

    List<RosterEntry> dutiesOf(List<String> roles) => [
      for (final role in roles) RosterEntry(role: role, people: const ['待定']),
    ];

    test('JSON 順序不算數，一律照樣板排', () {
      final sorted = orderDutiesByTemplate(dutiesOf(['領詩', '司琴', '主席']), const [
        '主席',
        '司琴',
        '領詩',
      ]);
      expect(rolesOf(sorted), ['主席', '司琴', '領詩']);
    });

    test('樣板裡沒有的角色接在最後，彼此維持 JSON 的相對順序', () {
      final sorted = orderDutiesByTemplate(
        dutiesOf(['音控', '司琴', '招待', '主席']),
        const ['主席', '司琴'],
      );
      expect(rolesOf(sorted), ['主席', '司琴', '音控', '招待']);
    });

    test('只排序，不會把樣板有、JSON 沒有的角色補進來', () {
      final sorted = orderDutiesByTemplate(dutiesOf(['司琴']), const [
        '主席',
        '司琴',
        '領詩',
      ]);
      expect(rolesOf(sorted), ['司琴']);
    });

    test('同一角色在 JSON 出現兩次時維持原本的先後（sort 不保證穩定，要自己 tie-break）', () {
      // 用 people 分辨兩筆同名角色誰先誰後。
      final duties = [
        RosterEntry(role: '司琴', people: const ['第一筆']),
        RosterEntry(role: '主席', people: const ['主席甲']),
        RosterEntry(role: '司琴', people: const ['第二筆']),
      ];
      final sorted = orderDutiesByTemplate(duties, const ['主席', '司琴']);
      expect(rolesOf(sorted), ['主席', '司琴', '司琴']);
      expect(sorted[1].people, ['第一筆']);
      expect(sorted[2].people, ['第二筆']);
    });

    test('項目數超過 32 時同名角色仍維持原順序（這裡才真的測到 tie-break）', () {
      // 上面那條三筆的測試其實咬不到 tie-break：Dart 的 List.sort 在 32 個
      // 元素以下走 insertion sort，本身就是穩定的。超過 32 才換成 dual-pivot
      // quicksort，同分元素的相對順序這時才會被打亂。拿掉 tie-break 的話
      // 只有這一條會紅。
      const count = 40;
      final duties = [
        for (var i = 0; i < count; i++)
          RosterEntry(role: i.isEven ? '司琴' : '主席', people: ['第$i筆']),
      ];

      final sorted = orderDutiesByTemplate(duties, const ['主席', '司琴']);

      expect(rolesOf(sorted).toSet(), {'主席', '司琴'});
      expect(sorted.take(count ~/ 2).map((d) => d.people.single), [
        for (var i = 1; i < count; i += 2) '第$i筆',
      ], reason: '主席應照原順序排在前半');
      expect(sorted.skip(count ~/ 2).map((d) => d.people.single), [
        for (var i = 0; i < count; i += 2) '第$i筆',
      ], reason: '司琴應照原順序排在後半');
    });

    test('角色全部都不在樣板裡時，整份維持 JSON 順序', () {
      final sorted = orderDutiesByTemplate(dutiesOf(['音控', '招待']), const [
        '主席',
      ]);
      expect(rolesOf(sorted), ['音控', '招待']);
    });

    test('樣板為空時退回 JSON 順序 —— 呼叫端必須先擋掉這種情況', () {
      // 這條不是「期望的行為」，是把後果寫下來：樣板沒載到就匯入會排出
      // JSON 順序。roster_edit_screen 用 RosterProvider.templatesLoaded
      // 在進到這裡之前就擋掉了。
      final sorted = orderDutiesByTemplate(
        dutiesOf(['領詩', '司琴']),
        const <String>[],
      );
      expect(rolesOf(sorted), ['領詩', '司琴']);
    });

    test('樣板有重複角色時取第一次出現的位置', () {
      final sorted = orderDutiesByTemplate(dutiesOf(['司琴', '主席']), const [
        '司琴',
        '主席',
        '司琴',
      ]);
      expect(rolesOf(sorted), ['司琴', '主席']);
    });

    test('不會改動傳進來的 list', () {
      final original = dutiesOf(['領詩', '主席']);
      orderDutiesByTemplate(original, const ['主席', '領詩']);
      expect(rolesOf(original), ['領詩', '主席']);
    });

    test('空輸入不會炸', () {
      expect(orderDutiesByTemplate(const [], const ['主席']), isEmpty);
    });

    test('parser 保留 JSON 順序，重排是後面那一層的事', () {
      // 兩層的分工：parser 忠實反映 JSON，orderDutiesByTemplate 才決定顯示
      // 順序。parser 若自作主張排序，這裡會紅。
      const json = '''
[
  {
    "date": "2026-01-04",
    "duties": [
      {"role": "領詩", "people": ["王大明"]},
      {"role": "主席", "people": ["李小華"]}
    ]
  }
]
''';
      final result = _parse(
        json,
        candidates: const ['王大明', '李小華'],
        allowedByRole: const {
          '領詩': {'王大明'},
          '主席': {'李小華'},
        },
      );
      final parsed = result.dutiesByDate['2026-01-04']!;
      expect(rolesOf(parsed), ['領詩', '主席']);
      expect(rolesOf(orderDutiesByTemplate(parsed, const ['主席', '領詩'])), [
        '主席',
        '領詩',
      ]);
    });
  });
}
