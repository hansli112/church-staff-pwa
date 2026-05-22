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

  const EventParseOutcome({this.error, this.names = const [], this.colorOverrides = const {}});
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
        final people = peopleValue
            .whereType<String>()
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .map((name) {
              final result = resolvePersonName(
                name,
                candidateNames,
                roleValue.trim(),
                allowedByRole,
              );
              switch (result.status) {
                case NameMatchStatus.matched:
                  return result.name;
                case NameMatchStatus.roleMismatch:
                  roleMismatchNames.add(result.name);
                  _addRoleMismatch(
                    roleMismatchDetails,
                    result.name,
                    roleValue.trim(),
                  );
                  return null;
                case NameMatchStatus.notInList:
                  notInRosterNames.add(name);
                  return null;
                case NameMatchStatus.other:
                  otherNames.add(name);
                  return null;
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
        return EventParseOutcome.err(
          '第 $rowIndex 筆 events 第 $elemNum 筆名稱不可為空',
        );
      }
    } else if (elem is Map) {
      final nameRaw = elem['name'];
      if (nameRaw == null) {
        return EventParseOutcome.err('第 $rowIndex 筆 events 第 $elemNum 筆缺少 name');
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
      return EventParseOutcome.err(
        '第 $rowIndex 筆 events 第 $elemNum 筆格式錯誤',
      );
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
