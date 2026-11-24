import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../data/backend.dart';
import '../domain/day.dart';
import '../domain/models.dart';
import '../domain/roster_import.dart';
import 'church_writes.dart';
import 'providers.dart';
import 'roster_actions.dart';
import 'session.dart';
import 'staff_actions.dart';

/// What is being imported into one service before it is applied: the rows,
/// from photos or pasted JSON, as edited, merged into the days; who each
/// name is. It belongs to the church and account that opened it.
@immutable
class ImportDraft {
  const ImportDraft({
    this.rows = const [],
    this.loaded = false,
    this.people = const {},
    this.busy = false,
    this.error,
    this.scopeChanged = false,
    this.fromPhotos = false,
  });

  /// The rows in the documented JSON format, each a decoded JSON value.
  final List<dynamic> rows;

  /// Whether rows were loaded: an empty list from a photo still previews.
  final bool loaded;

  /// Names the person said who they are: a member, or arranged this once.
  final Map<String, ImportPersonChoice> people;

  /// Recognizing photos or changing the service's settings.
  final bool busy;

  /// Why the last photos or pasted text gave no rows: a [CloudException],
  /// a [FormatException], or the photos could not be read.
  final Object? error;

  /// The church or account changed, which dropped the earlier draft. Said
  /// until rows are loaded or something else goes wrong.
  final bool scopeChanged;

  /// The rows were read from photos, not pasted.
  final bool fromPhotos;

  /// Every name on the rows, trimmed.
  Set<String> get names => {
    for (final row in rows)
      if (row case {'duties': final List<dynamic> duties})
        for (final duty in duties)
          if (duty case {'people': final List<dynamic> people})
            for (final name in people)
              if (name is String && name.trim().isNotEmpty) name.trim(),
  };

  ImportDraft copyWith({
    List<dynamic>? rows,
    bool? loaded,
    Map<String, ImportPersonChoice>? people,
    bool? busy,
    Object? error,
    bool clearError = false,
    bool? fromPhotos,
  }) => ImportDraft(
    rows: rows ?? this.rows,
    loaded: loaded ?? this.loaded,
    people: people ?? this.people,
    busy: busy ?? this.busy,
    error: clearError ? null : error ?? this.error,
    scopeChanged: scopeChanged && !clearError && error == null,
    fromPhotos: fromPhotos ?? this.fromPhotos,
  );
}

/// One service's import, from rows to applying them. A change of church or
/// account starts over, and work begun before it (photos being read, a
/// settings change) never lands in the new draft.
class ImportSession extends Notifier<ImportDraft> {
  ImportSession(this.serviceType);

  final String serviceType;

  /// Which draft is current; work begun on an earlier one is dropped.
  Object _draft = Object();

  @override
  ImportDraft build() {
    ref.onCancel(_onLeft);
    // Built again, the links made before are gone with it.
    _kept = null;
    final scope = (ref.watch(currentChurchIdProvider), ref.watch(uidProvider));
    final changed = _scope != null && _scope != scope;
    _scope = scope;
    _draft = Object();
    return ImportDraft(scopeChanged: changed);
  }

  (String?, String?)? _scope;

  /// Names the current draft: a caller that waited (on a sheet, a photo
  /// picker) checks it is still the same before acting.
  Object get draftKey => _draft;

  /// Whether [draft] is still the current one: work begun on an earlier
  /// draft is dropped.
  bool _isCurrent(Object draft) => ref.mounted && identical(draft, _draft);

  /// Reads [images] into rows, replacing the draft's. Kept while it reads,
  /// and its rows until the page is next left: the photos were counted,
  /// and the page left meanwhile shows them when opened again.
  Future<void> recognize(List<PhotoInput> images) async {
    final draft = _draft;
    _kept ??= ref.keepAlive();
    _reading++;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final rows = await ref.churchData.photos.recognize(serviceType, images);
      if (_isCurrent(draft)) load(rows, fromPhotos: true);
    } catch (e) {
      if (_isCurrent(draft)) fail(e);
    } finally {
      _reading--;
      if (_isCurrent(draft)) state = state.copyWith(busy: false);
    }
  }

  /// Photos being read, and what keeps this alive for them.
  int _reading = 0;
  KeepAliveLink? _kept;

  /// The page left: let go, unless photos are still being read; then once
  /// it is opened on their rows and left again.
  void _onLeft() {
    if (_reading > 0) return;
    _kept?.close();
    _kept = null;
  }

  /// No rows came, because of [error].
  void fail(Object error) => state = state.copyWith(error: error);

  /// What I arrange in this service: a 事工's 負責人 only its duties (#82).
  Arranges get arranges => ref.read(arrangesProvider(serviceType));

  /// [rows] as given, or for a 事工's 負責人 with only the duties it leads
  /// and no 特別活動: the rest of the day is not theirs to import.
  List<dynamic> _scoped(List<dynamic> rows) {
    final copy = jsonDecode(jsonEncode(rows)) as List<dynamic>;
    final arranges = this.arranges;
    if (arranges.all) return copy;
    return [
      for (final row in copy)
        if (row is Map)
          {
            for (final e in row.entries)
              if (e.key != 'events') e.key: e.value,
            if (row['duties'] is List)
              'duties': [
                for (final d in row['duties'] as List)
                  if (d is Map && d['role'] is String && arranges.has(d['role'] as String)) d,
              ],
          }
        else
          row,
    ];
  }

  /// Loads [rows] as new: who each name is is asked again. [fromPhotos]:
  /// read from photos rather than pasted.
  void load(List<dynamic> rows, {bool fromPhotos = false}) => state = state.copyWith(
    // Never share the recognizer's response or a caller's list.
    rows: _scoped(fromPhotos ? mergeRepeats(rows) : rows),
    loaded: true,
    people: const {},
    clearError: true,
    fromPhotos: fromPhotos,
  );

  /// Loads pasted [text], which must be a JSON array.
  /// [text] may be an AI's whole reply: a ```json fence or a sentence
  /// around the array is left out.
  void paste(String text) {
    final start = text.indexOf('['), end = text.lastIndexOf(']');
    try {
      final rows = jsonDecode(start >= 0 && end > start ? text.substring(start, end + 1) : text);
      if (rows is! List) throw const FormatException();
      load(rows);
    } on FormatException catch (e) {
      fail(e);
    }
  }

  /// Replaces the rows with [rows], edited: who each name is stays.
  void edit(List<dynamic> rows) => state = state.copyWith(rows: _scoped(rows), clearError: true);

  /// Row [index] as it is now, changed by [change]; a row that is not an
  /// object (JSON pasted wrong) is left.
  void _change(int index, void Function(Map<String, dynamic> row) change) {
    final rows = state.rows;
    if (index >= rows.length || rows[index] is! Map) return;
    final row = Map<String, dynamic>.from(rows[index] as Map);
    change(row);
    edit([for (final (i, old) in rows.indexed) i == index ? row : old]);
  }

  /// [key]'s list in [row], a copy, empty when it has none.
  static List<dynamic> _list(Map<String, dynamic> row, String key) =>
      row[key] is List ? List<dynamic>.of(row[key] as List<dynamic>) : <dynamic>[];

  /// Puts [item] at [at] of [list], or after the rest when null.
  static void _put(List<dynamic> list, int? at, Object item) =>
      at == null || at >= list.length ? list.add(item) : list[at] = item;

  /// Row [index] is for [date].
  void setDate(int index, Day date) => _change(index, (row) => row['date'] = date.toString());

  /// Duty [at] of row [index] (null: a new one, last) is [role], served by
  /// [people], each trimmed, blank ones left out.
  void putDuty(int index, int? at, {required String role, required List<String> people}) => _change(index, (row) {
    final duties = _list(row, 'duties');
    _put(duties, at, {
      'role': role.trim(),
      'people': [
        for (final p in people)
          if (p.trim().isNotEmpty) p.trim(),
      ],
    });
    row['duties'] = duties;
  });

  /// Takes duty [at] off row [index].
  void removeDuty(int index, int at) => _change(index, (row) => row['duties'] = _list(row, 'duties')..removeAt(at));

  /// 特別活動 [at] of row [index] (null: a new one, last) is [name] in
  /// [color].
  void putEvent(int index, int? at, {required String name, required int color}) => _change(index, (row) {
    final events = _list(row, 'events');
    _put(events, at, {'name': name.trim(), 'color': color});
    row['events'] = events;
  });

  /// Takes 特別活動 [at] off row [index].
  void removeEvent(int index, int at) => _change(index, (row) => row['events'] = _list(row, 'events')..removeAt(at));

  void choose(String name, ImportPersonChoice choice) =>
      state = state.copyWith(people: {...state.people, name: choice});

  /// [from] written as [to] wherever the rows have it: a name the person
  /// typed for one on the sheet. Who [to] is is asked as for any name.
  void rename(String from, String to) => edit([
    for (final row in state.rows)
      if (row case {'duties': final List<dynamic> duties})
        {
          for (final e in row.entries) e.key: e.value,
          'duties': [
            for (final duty in duties)
              if (duty case {
                'people': final List<dynamic> people,
              } when people.any((n) => n is String && n.trim() == from))
                {
                  for (final e in duty.entries) e.key: e.value,
                  'people': {
                    for (final name in people) name is String && name.trim() == from ? to : name,
                  }.toList(),
                }
              else
                duty,
          ],
        }
      else
        row,
  ]);

  /// Makes [name] one of the service's 同工 without an account (新增同工),
  /// as picking someone for a duty does. Done once the church's list has
  /// them, the rows' [name] theirs: until then, busy, so nobody adds them
  /// twice.
  Future<void> addStaff(String name) => _repair(() => ref.read(staffActionsProvider).add(name, serviceType));

  /// The members [name] could be: same name, or what it may shorten.
  List<Member> candidates(String name) {
    // The 同工 without an account too, as the plan matches them.
    final members = ref.read(staffProvider).value?.all ?? const <Member>[];
    final hints = ImportReport();
    NameMatcher(members).resolve(name, hints);
    return [
      for (final member in members)
        if (member.name.trim() == name ||
            hints.notInList[name]?.contains(member.name.trim()) == true ||
            (hints.ambiguous.contains(name) && member.name.trim().endsWith(name)) ||
            member.uid == state.people[name]?.uid)
          member,
    ];
  }

  Service get _service =>
      ref.read(servicesProvider).requireValue.byId(serviceType) ?? (throw StateError('No service $serviceType'));

  /// Admins: adds [role] to the service's duties.
  Future<void> addDuty(String role) => _repair(() {
    final before = _service;
    if (before.duties.contains(role)) return Future.value();
    return ref.read(churchWritesProvider).service(before, before.copyWith(duties: [...before.duties, role])).done;
  });

  /// Admins, once [shown] is applied: everyone it scheduled for one of the
  /// service's duties they were not on the list for is put on it, as
  /// picking them by hand does. A duty not in the settings puts nobody on.
  /// Answers with the undo, for the import's 復原.
  ({Future<void> done, Future<void> Function() undo}) rememberDuties(ImportPlan shown) {
    final actions = ref.read(rosterActionsProvider);
    final duties = _service.duties;
    final added = [
      for (final q in shown.report.missingQualifications)
        if (duties.contains(q.role)) q,
    ];
    return (
      done: Future.wait([for (final q in added) actions.grantDuty(q.member, serviceType, q.role)]),
      undo: () => Future.wait([for (final q in added) actions.revokeDuty(q.member, serviceType, q.role)]),
    );
  }

  /// Admins: adds [event] to the service's common events.
  Future<void> addCommonEvent(EventTag event) => _repair(() {
    final before = _service;
    if (before.events.any((e) => e.name == event.name)) return Future.value();
    return ref.read(churchWritesProvider).service(before, before.copyWith(events: [...before.events, event])).done;
  });

  /// Rethrows a failure, unless the draft changed meanwhile.
  Future<void> _repair(Future<void> Function() write) async {
    if (state.busy) return;
    state = state.copyWith(busy: true);
    final draft = _draft;
    try {
      await write();
    } catch (_) {
      if (_isCurrent(draft)) rethrow;
    } finally {
      if (_isCurrent(draft)) state = state.copyWith(busy: false);
    }
  }

  /// Applies [shown], the preview the person saw. If the rosters changed
  /// since, [CloudErrorCode.conflict]: the new difference must be seen first.
  ChurchWrite apply(ImportPlan shown) {
    final write = ref
        .read(rosterActionsProvider)
        .applyImport(serviceType, state.rows, people: state.people, preview: shown);
    final telemetry = ref.read(telemetryProvider);
    final method = state.fromPhotos ? 'photo' : 'text';
    // Counted once written (GA4), by where the rows came from: photos go
    // through Gemini, which costs.
    return (
      done: write.done.then((_) => telemetry.logEvent('roster_import', {'method': method})),
      undo: write.undo,
    );
  }
}

final importSessionProvider = NotifierProvider.autoDispose.family<ImportSession, ImportDraft, String>(
  ImportSession.new,
);

/// The import of [serviceType]'s draft as it would be applied now, planned
/// again whenever the draft or the church's data changes. Null until rows
/// are loaded, or while what it reads is not loaded.
final importPlanProvider = Provider.autoDispose.family<ImportPlan?, String>((ref, serviceType) {
  final draft = ref.watch(importSessionProvider(serviceType));
  final ready = ref.watch(rosterEditingProvider(serviceType));
  // What the plan reads, so it is planned again when any of it changes;
  // the day too, since past days are left out.
  ref
    ..watch(savedRostersProvider)
    ..watch(servicesProvider)
    ..watch(staffProvider)
    ..watch(staffOrderProvider(serviceType))
    ..watch(todayProvider);
  if (!draft.loaded || !ready) return null;
  return ref.read(rosterActionsProvider).previewImport(serviceType, draft.rows, people: draft.people);
});
