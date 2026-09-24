// 匯入的內部實作：把 JSON 讀成逐日的服事與活動，並記下哪些名字沒對上。
//
// app 裡只有 roster_import.dart（planRosterImport）用它 —— 對到現有服事表、
// 樣板排序、報告都在那邊，直接呼叫這裡等於繞過那些檢查。
// test/roster_import_plan_test.dart 有一個測試守著這件事。直接用它的只有它
// 自己的測試，和 scripts/preview-roster-import.py（要逐日印出排序結果）。

import 'dart:convert';

import 'entities/event_option.dart';
import 'entities/service_roster.dart';
import 'staff_directory.dart';

// ── Public result type ──────────────────────────────────────────────────────

class RosterImportParseResult {
  /// Fatal error — stop everything if this is non-null.
  final String? error;

  /// dutiesByDate: only dates where "duties" key existed AND parsed OK.
  final Map<String, List<RosterEntry>> dutiesByDate;

  /// Dates where the "duties" key was present in JSON (may be empty list if
  /// duties array was empty — but the validator rejects that, so in practice
  /// only non-empty arrays appear here).
  final Set<String> dutiesProvidedDates;

  /// eventsByDate: only dates where "events" key existed (empty array included).
  final Map<String, List<String>> eventsByDate;

  /// Dates where the "events" key was present in JSON (includes empty array).
  final Set<String> eventsProvidedDates;

  /// Per-date color overrides — only includes events where JSON explicitly
  /// provided a color value.
  final Map<String, Map<String, int>> colorsByDate;

  /// Names that did not appear in the candidate-name list.
  ///
  /// 不含 [guestSpeakerNames] —— 那些人另外列，不算問題。
  final List<String> notInRosterNames;

  /// 只出現在「信息」這一格、名單裡沒有、也沒有很像的人：外來講員。
  ///
  /// 名字一樣照寫進服事表，只是報告上不把他們當成要處理的事。講員一年可能
  /// 就來一次，沒有帳號是正常的；跟「新同工還沒開帳號」混在同一段，真正要
  /// 注意的那幾個名字就被淹掉了。
  final List<String> guestSpeakerNames;

  /// Names whose role assignment did not match the allowed-by-role map.
  final List<String> roleMismatchNames;

  /// Detail: role(s) that triggered the mismatch, keyed by person name.
  final Map<String, Set<String>> roleMismatchDetails;

  /// Names that matched more than one candidate: a suffix several people share,
  /// or a full name two people on the list both have.
  final List<String> otherNames;

  /// 表上原字 → 名單裡跟它只差一個字的那幾位。**只是提示，沒有套用。**
  ///
  /// 這些名字一律照表上原文寫進服事表，沒有 uid —— 也就是同時會出現在
  /// [notInRosterNames]。列出候選是為了讓管理者一眼看出「這是不是某位的
  /// 別寫法」，該不該改由他決定。
  final Map<String, List<String>> nearMatchSuggestions;

  /// Event names that were not found in the supplied catalog.
  final List<String> notInEventCatalog;

  const RosterImportParseResult({
    this.error,
    this.dutiesByDate = const {},
    this.dutiesProvidedDates = const {},
    this.eventsByDate = const {},
    this.eventsProvidedDates = const {},
    this.colorsByDate = const {},
    this.notInRosterNames = const [],
    this.guestSpeakerNames = const [],
    this.roleMismatchNames = const [],
    this.roleMismatchDetails = const {},
    this.otherNames = const [],
    this.nearMatchSuggestions = const {},
    this.notInEventCatalog = const [],
  });

  /// Convenience: fatal-error constructor.
  const RosterImportParseResult.fatal(String message)
    : error = message,
      dutiesByDate = const {},
      dutiesProvidedDates = const {},
      eventsByDate = const {},
      eventsProvidedDates = const {},
      colorsByDate = const {},
      notInRosterNames = const [],
      guestSpeakerNames = const [],
      roleMismatchNames = const [],
      roleMismatchDetails = const {},
      otherNames = const [],
      nearMatchSuggestions = const {},
      notInEventCatalog = const [];
}

/// 常由外面的人來擔任的服事。三個崇拜的講道在服事項目樣板裡都叫「信息」。
///
/// 只放這一項：其他服事由沒帳號的人擔任時，多半是新同工還沒開帳號，
/// 那正是匯入報告要讓人看到的。
///
/// 寫死而不是做成設定：三個崇拜都叫這個名字，為一個不會變的值多做一個
/// 設定畫面不划算。**服事項目設定裡把「信息」改名的話，這裡要跟著改**，
/// 否則講員會回到「名單裡沒有這個人」—— 沒有測試會替你抓到這件事。
const Set<String> guestSpeakerRoles = {'信息'};

/// 名稱裡帶著自己日期的活動，例如「感恩聚餐（12/26 六）」。
///
/// 主日的辨識規則會把「表旁邊寫在星期六」這種活動放到之後那個主日，名稱
/// 後面帶上它真正的日期。這種活動一次性、名字每次都不同，**不該**進活動
/// 清單：放進去也永遠對不上下一次的名稱。所以不列進「活動沒有固定顏色」，
/// 也就不會有人對它按「加入活動清單」。
bool isDatedOneOffEvent(String name) =>
    RegExp(r'[（(]\s*\d{1,2}/\d{1,2}').hasMatch(name);

// ── Helper types ────────────────────────────────────────────────────────────

class EventParseOutcome {
  final String? error;
  final List<String> names;

  /// Only includes entries where the caller explicitly supplied a color.
  final Map<String, int> colorOverrides;

  const EventParseOutcome({
    this.error,
    this.names = const [],
    this.colorOverrides = const {},
  });
  const EventParseOutcome.err(String message)
    : error = message,
      names = const [],
      colorOverrides = const {};
}

// ── Top-level pure parser ───────────────────────────────────────────────────

/// Parse the raw JSON string for roster import.
///
/// [input]         — raw text from the text field.
/// [staff]         — who is on the staff list and what they may serve.
/// [catalogByName] — map of event name → EventOption (for the relevant type).
RosterImportParseResult parseRosterImportJson({
  required String input,
  required StaffDirectory staff,
  required Map<String, EventOption> catalogByName,
}) {
  if (input.trim().isEmpty) {
    return const RosterImportParseResult.fatal('請貼上 JSON 內容');
  }

  dynamic decoded;
  try {
    decoded = jsonDecode(input);
  } catch (_) {
    return const RosterImportParseResult.fatal('JSON 格式錯誤');
  }

  if (decoded is! List) {
    return const RosterImportParseResult.fatal('JSON 最外層需為陣列');
  }

  final dutiesByDate = <String, List<RosterEntry>>{};
  final dutiesProvidedDates = <String>{};
  final eventsByDate = <String, List<String>>{};
  final eventsProvidedDates = <String>{};
  final colorsByDate = <String, Map<String, int>>{};
  final duplicateDates = <String>[];

  final notInRosterNames = <String>[];
  // 沒對到的人各自出現在哪些服事 —— 用來分出外來講員。
  final notInRosterRoles = <String, Set<String>>{};
  final roleMismatchNames = <String>[];
  final roleMismatchDetails = <String, Set<String>>{};
  final otherNames = <String>[];
  final nearMatchSuggestions = <String, List<String>>{};
  final notInEventCatalog = <String>[];

  for (var i = 0; i < decoded.length; i++) {
    final rowNum = i + 1;
    final item = decoded[i];
    if (item is! Map) {
      return RosterImportParseResult.fatal('第 $rowNum 筆不是物件');
    }

    // ── date ──────────────────────────────────────────────────────────────
    final dateValue = item['date'];
    if (dateValue is! String) {
      return RosterImportParseResult.fatal('第 $rowNum 筆缺少 date');
    }
    final parsedDate = _parseDateKey(dateValue);
    if (parsedDate == null) {
      return RosterImportParseResult.fatal('第 $rowNum 筆 date 格式錯誤');
    }

    // ── duties (optional key) ─────────────────────────────────────────────
    final hasDutiesKey = item.containsKey('duties');
    List<RosterEntry>? parsedDuties;
    if (hasDutiesKey) {
      final dutiesValue = item['duties'];
      if (dutiesValue is! List) {
        return RosterImportParseResult.fatal('第 $rowNum 筆 duties 格式錯誤');
      }
      final duties = <RosterEntry>[];
      for (var j = 0; j < dutiesValue.length; j++) {
        final dutyNum = j + 1;
        final duty = dutiesValue[j];
        if (duty is! Map) {
          return RosterImportParseResult.fatal(
            '第 $rowNum 筆 duties 第 $dutyNum 筆不是物件',
          );
        }
        final roleValue = duty['role'];
        if (roleValue is! String || roleValue.trim().isEmpty) {
          return RosterImportParseResult.fatal(
            '第 $rowNum 筆 duties 第 $dutyNum 筆 role 缺失',
          );
        }
        final peopleValue = duty['people'];
        if (peopleValue is! List) {
          return RosterImportParseResult.fatal(
            '第 $rowNum 筆 duties 第 $dutyNum 筆 people 格式錯誤',
          );
        }
        // 非字串的元素（null、數字）以前被 whereType 靜靜濾掉 —— 跟這次要
        // 消滅的「名字無聲失蹤」是同一件事，只是更難察覺：它連報告都不會進。
        // 這種資料就是壞掉的，直接讓整份匯入停下來說明是哪一筆。
        for (var k = 0; k < peopleValue.length; k++) {
          if (peopleValue[k] is! String) {
            return RosterImportParseResult.fatal(
              '第 $rowNum 筆 duties 第 $dutyNum 筆 people 第 ${k + 1} 個不是文字',
            );
          }
        }
        final people = peopleValue
            .cast<String>()
            .map((name) => name.trim())
            // 空字串不是名字，跳過。這是唯一會被靜靜略過的東西。
            .where((name) => name.isNotEmpty)
            .map((name) {
              final result = staff.resolve(name, roleValue.trim());
              // 沒對到的名字一律照樣寫進服事表，只記進報告，不丟掉。
              //
              // 以前是丟掉的，那格於是變成「待定」，同一格還有別人時甚至什麼
              // 痕跡都沒有 —— 牆上的表寫著兩個人，app 顯示一個，肉眼分不出來。
              // 臨時支援別的崇拜是正常狀況，不該被當成錯誤資料刪掉。
              //
              // 首頁的「我的服事」在 uid 對不上時會退回姓名比對，所以名字留著
              // 本人就看得到自己被排到；名字刪掉才是真的把人弄丟。
              if (result.suggestions.isNotEmpty) {
                // 名單裡很像的那幾位。名字照原文寫進去了，這只是提示。
                nearMatchSuggestions[name] = result.suggestions;
              }
              switch (result.status) {
                case NameMatchStatus.matched:
                  return result.name;
                case NameMatchStatus.roleMismatch:
                  // 人是名單上的真人，uid 也查得到（下面的 personIdsByName
                  // 會自動帶上），只是沒設定這個服事。
                  roleMismatchNames.add(result.name);
                  _addRoleMismatch(
                    roleMismatchDetails,
                    result.name,
                    roleValue.trim(),
                  );
                  return result.name;
                case NameMatchStatus.notInList:
                  // 名單上沒有這個人 —— 存純文字，沒有 uid，收不到通知。
                  notInRosterNames.add(name);
                  notInRosterRoles
                      .putIfAbsent(name, () => <String>{})
                      .add(roleValue.trim());
                  return name;
                case NameMatchStatus.other:
                  // 對到兩個以上同名的人，系統無從判斷是誰，原字串照留。
                  otherNames.add(name);
                  return name;
              }
            })
            .whereType<String>()
            .toList();
        duties.add(
          RosterEntry(
            role: roleValue.trim(),
            people: people.isEmpty ? const [placeholderPerson] : people,
            personIdsByName: staff.idsOf(people),
          ),
        );
      }
      // duties key 存在但 array 為空 → reject
      if (duties.isEmpty) {
        return RosterImportParseResult.fatal('第 $rowNum 筆 duties 不可為空');
      }
      parsedDuties = duties;
    }

    // ── events (optional key) ─────────────────────────────────────────────
    final hasEventsKey = item.containsKey('events');
    List<String>? parsedEventNames;
    Map<String, int>? parsedColorOverrides;
    if (hasEventsKey) {
      final outcome = parseEventsList(rowNum, item['events'], catalogByName);
      if (outcome.error != null) {
        return RosterImportParseResult.fatal(outcome.error!);
      }
      parsedEventNames = outcome.names;
      parsedColorOverrides = outcome.colorOverrides;

      // Collect catalog misses
      for (final name in outcome.names) {
        if (!catalogByName.containsKey(name) &&
            !isDatedOneOffEvent(name) &&
            !notInEventCatalog.contains(name)) {
          notInEventCatalog.add(name);
        }
      }
    }

    // ── at least one of duties / events must be provided ─────────────────
    if (!hasDutiesKey && !hasEventsKey) {
      return RosterImportParseResult.fatal('第 $rowNum 筆需至少包含 duties 或 events');
    }

    // ── duplicate date detection ──────────────────────────────────────────
    final alreadyExists =
        dutiesProvidedDates.contains(parsedDate) ||
        eventsProvidedDates.contains(parsedDate) ||
        dutiesByDate.containsKey(parsedDate) ||
        eventsByDate.containsKey(parsedDate);
    if (alreadyExists) {
      duplicateDates.add(parsedDate);
    }

    if (hasDutiesKey && parsedDuties != null) {
      dutiesByDate[parsedDate] = parsedDuties;
      dutiesProvidedDates.add(parsedDate);
    }
    if (hasEventsKey) {
      eventsByDate[parsedDate] = parsedEventNames ?? const [];
      eventsProvidedDates.add(parsedDate);
      colorsByDate[parsedDate] = parsedColorOverrides ?? const {};
    }
  }

  if (duplicateDates.isNotEmpty) {
    return RosterImportParseResult.fatal('重複日期：${duplicateDates.join(', ')}');
  }

  final unmatched = uniqueNames(notInRosterNames);
  bool isGuestSpeaker(String name) =>
      notInRosterRoles[name]!.every(guestSpeakerRoles.contains) &&
      // 名單裡有很像的，多半是某位同工的名字被讀錯一個字，不是外人。
      (nearMatchSuggestions[name] ?? const []).isEmpty;

  return RosterImportParseResult(
    dutiesByDate: dutiesByDate,
    dutiesProvidedDates: dutiesProvidedDates,
    eventsByDate: eventsByDate,
    eventsProvidedDates: eventsProvidedDates,
    colorsByDate: colorsByDate,
    notInRosterNames: [
      for (final name in unmatched)
        if (!isGuestSpeaker(name)) name,
    ],
    guestSpeakerNames: [
      for (final name in unmatched)
        if (isGuestSpeaker(name)) name,
    ],
    roleMismatchNames: uniqueNames(roleMismatchNames),
    roleMismatchDetails: roleMismatchDetails,
    otherNames: uniqueNames(otherNames),
    nearMatchSuggestions: nearMatchSuggestions,
    notInEventCatalog: notInEventCatalog,
  );
}

// ── orderDutiesByTemplate ───────────────────────────────────────────────────

/// 依「服事項目樣板」的角色順序重排匯入進來的服事項目。
///
/// JSON 自己的順序刻意不採用。樣板是唯一的排序依據 —— 不管 JSON 是誰產生的、
/// 用什麼順序寫，同一個類別的服事表在畫面上的項目順序都一致。
///
/// 樣板裡沒有的角色一律接在最後，彼此之間才維持 JSON 的相對順序。
///
/// [templateRoles] 為空時所有角色並列，等於整份退回 JSON 順序 —— 呼叫端必須
/// 先確認樣板真的載入過再進來，否則同一份 JSON 匯入兩次會排出兩種結果。
List<RosterEntry> orderDutiesByTemplate(
  List<RosterEntry> duties,
  List<String> templateRoles,
) {
  final roleOrder = <String, int>{};
  for (var i = 0; i < templateRoles.length; i++) {
    // 樣板理論上不會有重複角色（設定畫面擋掉了），真的有的話取第一次出現的
    // 位置，跟人看樣板的直覺一致。
    roleOrder.putIfAbsent(templateRoles[i], () => i);
  }

  // 先把 JSON 的原始索引綁上去再排。Dart 的 List.sort 不保證穩定，同一個角色
  // 在 JSON 裡出現兩次時，不自己 tie-break 的話相對順序是未定義的。
  // 用索引而不是 indexOf：indexOf 走的是 ==，將來 RosterEntry 若加上值相等，
  // 兩個相等的項目會拿到同一個索引，tie-break 就失效了。
  final indexed = <MapEntry<int, RosterEntry>>[
    for (var i = 0; i < duties.length; i++) MapEntry(i, duties[i]),
  ];
  indexed.sort((a, b) {
    final ai = roleOrder[a.value.role] ?? templateRoles.length;
    final bi = roleOrder[b.value.role] ?? templateRoles.length;
    if (ai != bi) return ai.compareTo(bi);
    return a.key.compareTo(b.key);
  });

  return [for (final entry in indexed) entry.value];
}

// ── parseEventsList ─────────────────────────────────────────────────────────

/// Parse the value of an "events" key from a single JSON row.
///
/// [rowIndex] is 1-based row number for error messages.
/// [raw]      is the raw value of item['events'].
/// [catalogByName] is used to decide whether JSON color overrides are needed.
EventParseOutcome parseEventsList(
  int rowIndex,
  dynamic raw,
  Map<String, EventOption> catalogByName,
) {
  if (raw is! List) {
    return EventParseOutcome.err('第 $rowIndex 筆 events 格式錯誤');
  }

  final names = <String>[];
  final colorOverrides = <String, int>{};
  final seenNames = <String>{};

  for (var k = 0; k < raw.length; k++) {
    final elemNum = k + 1;
    final elem = raw[k];
    String eventName;
    int? explicitColor;

    if (elem is String) {
      eventName = elem.trim();
      if (eventName.isEmpty) {
        return EventParseOutcome.err('第 $rowIndex 筆 events 第 $elemNum 筆名稱不可為空');
      }
    } else if (elem is Map) {
      final nameRaw = elem['name'];
      if (nameRaw == null) {
        return EventParseOutcome.err(
          '第 $rowIndex 筆 events 第 $elemNum 筆缺少 name',
        );
      }
      if (nameRaw is! String || nameRaw.trim().isEmpty) {
        return EventParseOutcome.err(
          '第 $rowIndex 筆 events 第 $elemNum 筆 name 格式錯誤',
        );
      }
      eventName = nameRaw.trim();

      if (elem.containsKey('color')) {
        final colorRaw = elem['color'];
        final parsed = parseColor(colorRaw);
        if (parsed == null) {
          return EventParseOutcome.err(
            '第 $rowIndex 筆 events 第 $elemNum 筆 color 格式錯誤',
          );
        }
        explicitColor = parsed;
      }
    } else {
      return EventParseOutcome.err('第 $rowIndex 筆 events 第 $elemNum 筆格式錯誤');
    }

    // Duplicate name check within the same day
    if (seenNames.contains(eventName)) {
      return EventParseOutcome.err('第 $rowIndex 筆 events 名稱重複：$eventName');
    }
    seenNames.add(eventName);
    names.add(eventName);

    // Color override: only store if JSON explicitly provided one.
    // If no JSON color but catalog has one → do NOT store (let UI read from catalog).
    if (explicitColor != null) {
      colorOverrides[eventName] = explicitColor;
    }
  }

  return EventParseOutcome(names: names, colorOverrides: colorOverrides);
}

// ── parseColor ───────────────────────────────────────────────────────────────

/// Parse a color value from JSON.
///
/// Accepts:
///  - int in range [0, 0xFFFFFFFF]
///  - "#RRGGBB"   → 0xFF_RR_GG_BB
///  - "#AARRGGBB" → 0xAA_RR_GG_BB
///  - "0xRRGGBB"  → 0xFF_RR_GG_BB
///  - "0xAARRGGBB"→ 0xAA_RR_GG_BB  (case-insensitive for hex digits)
///
/// Returns null on failure (including named colors like "red").
int? parseColor(dynamic raw) {
  if (raw is int) {
    if (raw >= 0 && raw <= 0xFFFFFFFF) return raw;
    return null;
  }
  if (raw is! String) return null;

  final s = raw.trim();
  if (s.isEmpty) return null;

  // Handle "#RRGGBB" or "#AARRGGBB"
  if (s.startsWith('#')) {
    final hex = s.substring(1);
    if (hex.length == 6) {
      final value = int.tryParse(hex, radix: 16);
      if (value == null) return null;
      return 0xFF000000 | value;
    }
    if (hex.length == 8) {
      return int.tryParse(hex, radix: 16);
    }
    return null;
  }

  // Handle "0xRRGGBB" or "0xAARRGGBB" (case-insensitive)
  if (s.toLowerCase().startsWith('0x')) {
    final hex = s.substring(2);
    if (hex.length == 6) {
      final value = int.tryParse(hex, radix: 16);
      if (value == null) return null;
      return 0xFF000000 | value;
    }
    if (hex.length == 8) {
      return int.tryParse(hex, radix: 16);
    }
    return null;
  }

  return null;
}

// ── Internal helpers ─────────────────────────────────────────────────────────

String? _parseDateKey(String raw) {
  try {
    final parsed = DateTime.parse(raw);
    final y = parsed.year.toString().padLeft(4, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    final d = parsed.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  } catch (_) {
    return null;
  }
}

List<String> uniqueNames(List<String> names) {
  final seen = <String>{};
  final result = <String>[];
  for (final name in names) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || seen.contains(trimmed)) continue;
    seen.add(trimmed);
    result.add(trimmed);
  }
  return result;
}

void _addRoleMismatch(
  Map<String, Set<String>> bucket,
  String name,
  String role,
) {
  final trimmedName = name.trim();
  final trimmedRole = role.trim();
  if (trimmedName.isEmpty || trimmedRole.isEmpty) return;
  bucket.putIfAbsent(trimmedName, () => <String>{});
  bucket[trimmedName]!.add(trimmedRole);
}
