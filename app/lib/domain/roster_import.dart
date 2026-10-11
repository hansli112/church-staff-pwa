import 'day.dart';
import 'models.dart';
import 'roster_edit.dart';
import 'staff_order.dart';

/// A deliberate decision for a sheet name. Only a unique exact name
/// auto-links a member; abbreviations, near matches and duplicate names
/// need confirmation. A guest never acquires a UID, even if their name
/// equals a member's name.
class ImportPersonChoice {
  const ImportPersonChoice.member(this.uid);
  const ImportPersonChoice.guest() : uid = null;

  final String? uid;
}

class ImportQualification {
  const ImportQualification({required this.member, required this.role});
  final Member member;
  final String role;
}

enum ImportIssueCode {
  rowObject,
  rowFields,
  date,
  duplicateDate,
  dutiesArray,
  dutyFields,
  role,
  peopleArray,
  duplicatePeople,
  eventsArray,
  eventObject,
  eventName,
  eventColor,
  resolvedDuplicatePeople,
}

/// A language-neutral validation problem. Item positions are one-based
/// `index` arguments; a resolved-name collision carries its `role`.
class ImportIssue {
  const ImportIssue(this.code, {this.args = const {}});
  final ImportIssueCode code;
  final Map<String, Object> args;
}

class ImportReport {
  ImportReport();

  /// Names that still need a confirmed member or an explicit guest choice.
  final unresolved = <String, List<Member>>{};

  /// Name on the sheet → suffix or near-name candidates (hints only).
  final notInList = <String, List<String>>{};

  /// Names two or more members could be.
  final ambiguous = <String>{};

  /// Duties the service does not have.
  final unknownDuties = <String>{};
  final missingQualifications = <ImportQualification>[];
  final unknownEvents = <EventTag>[];

  /// Days before today, skipped.
  final pastDays = <String>[];

  /// Rows that could not be read.
  final badRows = <int>[];

  /// One-based row number → actionable format errors. Any error blocks apply.
  final errors = <int, List<ImportIssue>>{};

  bool get isClean =>
      notInList.isEmpty && ambiguous.isEmpty && unknownDuties.isEmpty && pastDays.isEmpty && badRows.isEmpty;
}

enum ImportMode { merge, replace }

class ImportChange {
  const ImportChange({required this.before, required this.after});

  /// Null means there was no saved roster, only a template draft.
  final Roster? before;
  final Roster after;
}

class ImportPlan {
  ImportPlan(this.rosters, this.order, this.report, {this.changes = const {}});

  /// The days to write, already merged with what was saved.
  final List<Roster> rosters;

  /// Staff order learned from the sheet, merged into the existing one.
  final StaffOrder order;
  final ImportReport report;
  final Map<String, ImportChange> changes;

  bool get canApply => rosters.isNotEmpty && report.badRows.isEmpty && report.unresolved.isEmpty;
}

/// Matches sheet names to members.
class NameMatcher {
  NameMatcher(Iterable<Member> members) {
    for (final m in members) {
      final name = m.name.trim();
      if (name.isEmpty) continue;
      _names.add(name);
    }
    _ids = uniqueNameIds(members);
  }

  final _names = <String>[];
  late final Map<String, String> _ids;

  Map<String, String> get ids => _ids;

  /// The exact name [raw], unchanged when unresolved. Only [ids] can link
  /// unique exact names; [report] records candidates, never corrections.
  String resolve(String raw, ImportReport report) {
    final name = raw.trim();
    final exact = _names.where((n) => n == name).length;
    if (exact == 1) return name;
    if (exact > 1) {
      report.ambiguous.add(name);
      return name;
    }
    final suffix = _names.where((n) => n.length > name.length && n.endsWith(name)).toList();
    if (suffix.length > 1) {
      report.ambiguous.add(name);
      return name;
    }
    report.notInList[name] = suffix.isEmpty ? _nearMatches(name) : suffix;
    return name;
  }

  /// Members whose same-length tail differs from [name] by one character.
  List<String> _nearMatches(String name) {
    final target = name.runes.toList();
    if (target.length < 2) return const [];
    return [
      for (final full in _names)
        if (_oneOff(target, full.runes.toList())) full,
    ];
  }

  static bool _oneOff(List<int> target, List<int> full) {
    if (full.length < target.length) return false;
    final tail = full.sublist(full.length - target.length);
    var diff = 0;
    for (var i = 0; i < target.length; i++) {
      if (target[i] != tail[i] && ++diff > 1) return false;
    }
    return diff == 1;
  }
}

/// Builds the days to write from [rows] (the JSON array), for [service].
///
/// The only accepted format is an array of {date, duties, events?} rows:
/// date is YYYY-MM-DD; duties contain {role, people: [name]}; events contain
/// {name, color: 0..5}. Empty people is [], not a placeholder string.
/// Invalid rows or unresolved identities block the entire apply; past dates
/// are explicitly reported and omitted.
///
/// Merge replaces mentioned duties/events by name and keeps unmentioned
/// arrangements. Explicit replacement keeps only the supplied duties/events.
/// Palette colors are always the explicit imported values, never inferred.
ImportPlan planImport({
  required List<dynamic> rows,
  required Service service,
  required List<Member> members,
  required Iterable<Roster> saved,
  required StaffOrder order,
  required Day today,
  Map<String, ImportPersonChoice> people = const {},
  ImportMode mode = ImportMode.merge,
}) {
  final report = ImportReport();
  final matcher = NameMatcher(members);
  final byDay = <Day, Roster>{
    for (final r in saved)
      if (r.type == service.id) r.day: r,
  };
  final imported = <Roster>[];
  final sheetRosters = <Roster>[];
  final seen = <Day>{};

  for (final (i, row) in rows.indexed) {
    if (row is! Map) {
      report.badRows.add(i + 1);
      report.errors[i + 1] = [const ImportIssue(ImportIssueCode.rowObject)];
      continue;
    }
    final errors = _rowErrors(row);
    if (errors.isNotEmpty) {
      report.badRows.add(i + 1);
      report.errors[i + 1] = errors;
      continue;
    }
    final rawDate = row['date'];
    final day = rawDate is String ? Day.tryParse(rawDate) : null;
    if (day == null || !seen.add(day)) {
      report.badRows.add(i + 1);
      report.errors[i + 1] = [ImportIssue(day == null ? ImportIssueCode.date : ImportIssueCode.duplicateDate)];
      continue;
    }
    if (day.isBefore(today)) {
      report.pastDays.add(day.key);
      continue;
    }
    var roster = mode == ImportMode.replace
        ? Roster(type: service.id, day: day, saved: byDay.containsKey(day))
        : byDay[day] ??
              Roster(
                type: service.id,
                day: day,
                saved: false,
                duties: [for (final d in service.duties) Duty(role: d)],
              );
    final sheetDuties = <Duty>[];
    final duties = row['duties'];
    if (duties is List) {
      for (final d in duties) {
        if (d is! Map || d['role'] is! String) continue;
        final role = (d['role'] as String).trim();
        final peopleOnDuty = [
          for (final p in (d['people'] is List ? d['people'] as List<dynamic> : const <dynamic>[]))
            if (p is String && p.trim().isNotEmpty) p.trim(),
        ];
        if (!service.duties.contains(role)) report.unknownDuties.add(role);
        final ids = <String, String>{};
        final names = <String>[];
        for (final p in peopleOnDuty) {
          final choice = people[p];
          if (choice != null && choice.uid == null) {
            names.add(p);
          } else if (choice != null) {
            final member = members.where((m) => m.uid == choice.uid).firstOrNull;
            if (member == null) {
              report.unresolved[p] = const [];
              names.add(p);
            } else {
              names.add(member.name.trim());
              ids[member.name.trim()] = member.uid;
            }
          } else {
            final name = matcher.resolve(p, report);
            names.add(name);
            final uid = matcher.ids[name];
            if (uid != null) {
              ids[name] = uid;
            } else {
              final candidates = {
                ...?report.notInList[p],
                if (report.ambiguous.contains(p))
                  ...members.where((m) => m.name.trim() == p || m.name.trim().endsWith(p)).map((m) => m.name.trim()),
              };
              report.unresolved[p] = members.where((m) => candidates.contains(m.name.trim())).toList();
            }
          }
        }
        if (names.toSet().length != names.length) {
          if (!report.badRows.contains(i + 1)) report.badRows.add(i + 1);
          report.errors
              .putIfAbsent(i + 1, () => [])
              .add(
                ImportIssue(ImportIssueCode.resolvedDuplicatePeople, args: {'role': role}),
              );
        }
        for (final uid in ids.values) {
          final member = members.firstWhere((m) => m.uid == uid);
          if (!member.serves(service.id, role) &&
              !report.missingQualifications.any((q) => q.member.uid == uid && q.role == role)) {
            report.missingQualifications.add(ImportQualification(member: member, role: role));
          }
        }
        sheetDuties.add(Duty(role: role, people: names, uids: ids));
        roster = Roster(
          type: roster.type,
          day: roster.day,
          events: roster.events,
          saved: roster.saved,
          duties: _replace(roster.duties, role, names, ids),
        );
      }
    }
    final events = row['events'];
    if (events is List) {
      final incoming = [
        for (final e in events) EventTag(name: (e['name'] as String).trim(), color: e['color'] as int),
      ];
      for (final event in incoming) {
        if (!service.events.any((e) => e.name == event.name) && !report.unknownEvents.contains(event)) {
          report.unknownEvents.add(event);
        }
      }
      roster = roster.copyWith(
        events: mode == ImportMode.replace
            ? incoming
            : [
                for (final e in roster.events) incoming.where((next) => next.name == e.name).firstOrNull ?? e,
                for (final e in incoming)
                  if (!roster.events.any((old) => old.name == e.name)) e,
              ],
      );
    }
    imported.add(roster);
    sheetRosters.add(Roster(type: service.id, day: day, duties: sheetDuties));
  }

  // Only deliberately linked members teach an order, never an unresolved
  // sheet name or a guest who happens to share a member's name.
  final learned = StaffOrder.learnFrom([
    for (final r in sheetRosters)
      r.copyWith(
        duties: [
          for (final d in r.duties) d.copyWith(people: d.people.where(d.uids.containsKey).toList()),
        ],
      ),
  ]);
  final nextOrder = order.mergedWith(learned);
  final rosters = [for (final r in imported) nextOrder.applyTo(r)];
  return ImportPlan(
    rosters,
    nextOrder,
    report,
    changes: {
      for (final r in rosters) r.id: ImportChange(before: byDay[r.day], after: r),
    },
  );
}

List<ImportIssue> _rowErrors(Map<dynamic, dynamic> row) {
  final errors = <ImportIssue>[];
  if (row.keys.any((k) => !['date', 'duties', 'events'].contains(k))) {
    errors.add(const ImportIssue(ImportIssueCode.rowFields));
  }
  if (row['date'] is! String || Day.tryParse(row['date'] as String?) == null) {
    errors.add(const ImportIssue(ImportIssueCode.date));
  }
  final duties = row['duties'];
  if (duties is! List) {
    errors.add(const ImportIssue(ImportIssueCode.dutiesArray));
  } else {
    final seen = <String>{};
    for (final (i, duty) in duties.indexed) {
      final args = <String, Object>{'index': i + 1};
      if (duty is! Map || duty.keys.any((k) => !['role', 'people'].contains(k))) {
        errors.add(ImportIssue(ImportIssueCode.dutyFields, args: args));
        continue;
      }
      final role = duty['role'];
      if (role is! String || role.trim().isEmpty || !seen.add(role.trim())) {
        errors.add(ImportIssue(ImportIssueCode.role, args: args));
      }
      final people = duty['people'];
      if (people is! List || people.any((p) => p is! String || p.trim().isEmpty)) {
        errors.add(ImportIssue(ImportIssueCode.peopleArray, args: args));
      } else if (people.map((p) => (p as String).trim()).toSet().length != people.length) {
        errors.add(ImportIssue(ImportIssueCode.duplicatePeople, args: args));
      }
    }
  }
  final events = row['events'];
  if (row.containsKey('events')) {
    if (events is! List) {
      errors.add(const ImportIssue(ImportIssueCode.eventsArray));
    } else {
      final seen = <String>{};
      for (final (i, event) in events.indexed) {
        final args = <String, Object>{'index': i + 1};
        if (event is! Map || event.keys.any((k) => !['name', 'color'].contains(k))) {
          errors.add(ImportIssue(ImportIssueCode.eventObject, args: args));
          continue;
        }
        final name = event['name'];
        if (name is! String || name.trim().isEmpty || !seen.add(name.trim())) {
          errors.add(ImportIssue(ImportIssueCode.eventName, args: args));
        }
        final color = event['color'];
        if (color is! int || color < 0 || color > 5) errors.add(ImportIssue(ImportIssueCode.eventColor, args: args));
      }
    }
  }
  return errors;
}

List<Duty> _replace(List<Duty> duties, String role, List<String> names, Map<String, String> ids) {
  final duty = Duty(
    role: role,
    people: names,
    uids: {
      for (final n in names) n: ?ids[n],
    },
  );
  final exists = duties.any((d) => d.role == role);
  return exists ? [for (final d in duties) d.role == role ? duty : d] : [...duties, duty];
}
