import 'dart:convert';

import '../../domain/entities/event_option.dart';
import '../../domain/entities/service_roster.dart';

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
  final List<String> notInRosterNames;

  /// Names whose role assignment did not match the allowed-by-role map.
  final List<String> roleMismatchNames;

  /// Detail: role(s) that triggered the mismatch, keyed by person name.
  final Map<String, Set<String>> roleMismatchDetails;

  /// Names that matched more than one candidate (ambiguous suffix match).
  final List<String> otherNames;

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
    this.roleMismatchNames = const [],
    this.roleMismatchDetails = const {},
    this.otherNames = const [],
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
      roleMismatchNames = const [],
      roleMismatchDetails = const {},
      otherNames = const [],
      notInEventCatalog = const [];
}

// ── Helper types (public so tests can import them if needed) ────────────────

enum NameMatchStatus { matched, notInList, roleMismatch, other }

class NameMatchResult {
  final NameMatchStatus status;
  final String name;

  const NameMatchResult(this.status, this.name);
  const NameMatchResult.matched(this.name) : status = NameMatchStatus.matched;
  const NameMatchResult.notInList(this.name)
    : status = NameMatchStatus.notInList;
  const NameMatchResult.roleMismatch(this.name)
    : status = NameMatchStatus.roleMismatch;
  const NameMatchResult.other(this.name) : status = NameMatchStatus.other;
}

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
/// [candidateNames] — trimmed, non-empty names of all known users.
/// [allowedByRole] — map of role → set of allowed user names.
/// [catalogByName] — map of event name → EventOption (for the relevant type).
/// [nameToIdMap]   — map of user name → user id.
RosterImportParseResult parseRosterImportJson({
  required String input,
  required List<String> candidateNames,
  required Map<String, Set<String>> allowedByRole,
  required Map<String, EventOption> catalogByName,
  required Map<String, String> nameToIdMap,
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
  final roleMismatchNames = <String>[];
  final roleMismatchDetails = <String, Set<String>>{};
  final otherNames = <String>[];
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
              final result = resolvePersonName(
                name,
                candidateNames,
                roleValue.trim(),
                allowedByRole,
              );
              // 沒對到的名字一律照樣寫進服事表，只記進報告，不丟掉。
              //
              // 以前是丟掉的，那格於是變成「待定」，同一格還有別人時甚至什麼
              // 痕跡都沒有 —— 牆上的表寫著兩個人，app 顯示一個，肉眼分不出來。
              // 臨時支援別的崇拜是正常狀況，不該被當成錯誤資料刪掉。
              //
              // 首頁的「我的服事」在 uid 對不上時會退回姓名比對，所以名字留著
              // 本人就看得到自己被排到；名字刪掉才是真的把人弄丟。
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
                  return name;
                case NameMatchStatus.other:
                  // 對到兩個以上同名的人，系統無從判斷是誰，原字串照留。
                  otherNames.add(name);
                  return name;
              }
            })
            .whereType<String>()
            .toList();
        final personIdsByName = <String, String>{
          for (final name in people)
            if (nameToIdMap.containsKey(name)) name: nameToIdMap[name]!,
        };
        duties.add(
          RosterEntry(
            role: roleValue.trim(),
            people: people.isEmpty ? const ['待定'] : people,
            peopleOrder: people.isEmpty ? const [] : List<String>.from(people),
            personIdsByName: personIdsByName,
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

  return RosterImportParseResult(
    dutiesByDate: dutiesByDate,
    dutiesProvidedDates: dutiesProvidedDates,
    eventsByDate: eventsByDate,
    eventsProvidedDates: eventsProvidedDates,
    colorsByDate: colorsByDate,
    notInRosterNames: uniqueNames(notInRosterNames),
    roleMismatchNames: uniqueNames(roleMismatchNames),
    roleMismatchDetails: roleMismatchDetails,
    otherNames: uniqueNames(otherNames),
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

NameMatchResult resolvePersonName(
  String raw,
  List<String> userNames,
  String role,
  Map<String, Set<String>> allowedByRole,
) {
  final name = raw.trim();
  if (name.isEmpty || name == '待定') {
    return const NameMatchResult.matched('待定');
  }
  if (userNames.contains(name)) {
    return _isAllowedForRole(name, role, allowedByRole)
        ? NameMatchResult.matched(name)
        : NameMatchResult.roleMismatch(name);
  }
  final matches = userNames
      .where((full) => full.length > name.length && full.endsWith(name))
      .toList();
  if (matches.length == 1) {
    final full = matches.first;
    return _isAllowedForRole(full, role, allowedByRole)
        ? NameMatchResult.matched(full)
        : NameMatchResult.roleMismatch(full);
  }
  if (matches.length > 1) {
    return NameMatchResult.other(name);
  }
  return NameMatchResult.notInList(name);
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

bool _isAllowedForRole(
  String name,
  String role,
  Map<String, Set<String>> allowedByRole,
) {
  final normalizedRole = role.trim();
  if (normalizedRole.isEmpty) return false;
  final allowed = allowedByRole[normalizedRole];
  if (allowed == null || allowed.isEmpty) return false;
  return allowed.contains(name);
}
