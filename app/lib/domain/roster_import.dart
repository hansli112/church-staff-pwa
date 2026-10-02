import 'day.dart';
import 'models.dart';
import 'roster_edit.dart';
import 'staff_order.dart';

/// Turning recognized (or pasted) roster JSON into days, matched against
/// the church's members. Rules ported from self-host's import parser and
/// StaffDirectory:
///
/// - A name is a member if it matches a full name exactly, or is the end of
///   exactly one member's name (sheets drop the surname).
/// - A name that matches two members, or that is only one character off from
///   someone, is written as it appears with no uid; the report shows it.
///   Never auto-corrected: a wrong guess puts someone's duty on another
///   person and their reminder with it.
/// - 「待定」 means nobody yet; 「暫停」 means no such duty that week.
class ImportReport {
  ImportReport();

  /// Name on the sheet → members one character off (a hint only).
  final notInList = <String, List<String>>{};

  /// Names two or more members could be.
  final ambiguous = <String>{};

  /// Duties the service does not have.
  final unknownDuties = <String>{};

  /// Days before today, skipped.
  final pastDays = <String>[];

  /// Rows that could not be read.
  final badRows = <int>[];

  bool get isClean =>
      notInList.isEmpty && ambiguous.isEmpty && unknownDuties.isEmpty && pastDays.isEmpty && badRows.isEmpty;
}

class ImportPlan {
  ImportPlan(this.rosters, this.order, this.report);

  /// The days to write, already merged with what was saved.
  final List<Roster> rosters;

  /// Staff order learned from the sheet, merged into the existing one.
  final StaffOrder order;
  final ImportReport report;
}

const _placeholder = '待定';
const _suspended = '暫停';

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

  /// The member name [raw] stands for, or null when it is not certain.
  /// [report] collects why.
  String resolve(String raw, ImportReport report) {
    final name = raw.trim();
    final exact = _names.where((n) => n == name).length;
    if (exact == 1) return name;
    if (exact > 1) {
      report.ambiguous.add(name);
      return name;
    }
    final suffix = _names.where((n) => n.length > name.length && n.endsWith(name)).toList();
    if (suffix.length == 1) return suffix.single;
    if (suffix.length > 1) {
      report.ambiguous.add(name);
      return name;
    }
    report.notInList[name] = _nearMatches(name);
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
/// Duties on the sheet replace those duties on the day; duties the sheet
/// does not mention are kept. Events on the sheet replace the day's events
/// and pick up the colour of a common event with the same name.
ImportPlan planImport({
  required List<dynamic> rows,
  required Service service,
  required List<Member> members,
  required Iterable<Roster> saved,
  required StaffOrder order,
  required Day today,
}) {
  final report = ImportReport();
  final matcher = NameMatcher(members);
  final byDay = <Day, Roster>{
    for (final r in saved)
      if (r.type == service.id) r.day: r,
  };
  final imported = <Roster>[];
  final seen = <Day>{};

  for (final (i, row) in rows.indexed) {
    if (row is! Map) {
      report.badRows.add(i + 1);
      continue;
    }
    final day = Day.tryParse(row['date'] as String?);
    if (day == null || !seen.add(day)) {
      report.badRows.add(i + 1);
      continue;
    }
    if (day.isBefore(today)) {
      report.pastDays.add(day.key);
      continue;
    }
    var roster =
        byDay[day] ??
        Roster(
          type: service.id,
          day: day,
          saved: false,
          duties: [for (final d in service.duties) Duty(role: d)],
        );
    final duties = row['duties'];
    if (duties is List) {
      for (final d in duties) {
        if (d is! Map || d['role'] is! String) continue;
        final role = (d['role'] as String).trim();
        final people = [
          for (final p in (d['people'] is List ? d['people'] as List<dynamic> : const <dynamic>[]))
            if (p is String && p.trim().isNotEmpty) p.trim(),
        ];
        if (people.contains(_suspended)) continue;
        if (!service.duties.contains(role)) report.unknownDuties.add(role);
        final names = [
          for (final p in people)
            if (p != _placeholder) matcher.resolve(p, report),
        ];
        roster = Roster(
          type: roster.type,
          day: roster.day,
          events: roster.events,
          saved: roster.saved,
          duties: _replace(roster.duties, role, names, matcher.ids),
        );
      }
    }
    final events = row['events'];
    if (events is List) {
      roster = roster.copyWith(
        events: [
          for (final e in events)
            if (e is String && e.trim().isNotEmpty)
              service.events.where((o) => o.name == e.trim()).firstOrNull ?? EventTag(name: e.trim(), color: 4),
        ],
      );
    }
    imported.add(roster);
  }

  // The sheet lists the main person first: learn that, keep members only.
  final memberNames = {for (final m in members) m.name.trim()};
  final learned = StaffOrder.learnFrom(imported).where(memberNames.contains);
  final nextOrder = order.mergedWith(learned);
  return ImportPlan([for (final r in imported) nextOrder.applyTo(r)], nextOrder, report);
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
