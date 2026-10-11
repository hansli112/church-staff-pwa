import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import '../domain/roster_import.dart';
import 'church_writes.dart';
import 'providers.dart';
import 'roster_actions.dart';

/// What is being imported into one service before it is applied: the rows,
/// from photos or pasted JSON, as edited; who each name is; merge or
/// replace. It belongs to the church and account that opened it.
@immutable
class ImportDraft {
  const ImportDraft({
    this.rows = const [],
    this.loaded = false,
    this.people = const {},
    this.mode = ImportMode.merge,
    this.busy = false,
    this.error,
    this.scopeChanged = false,
  });

  /// The rows in the documented JSON format, each a decoded JSON value.
  final List<dynamic> rows;

  /// Whether rows were loaded: an empty list from a photo still previews.
  final bool loaded;

  /// Names the person said who they are: a member, or 外請.
  final Map<String, ImportPersonChoice> people;

  final ImportMode mode;

  /// Recognizing photos or changing the service's settings.
  final bool busy;

  /// Why the last photos or pasted text gave no rows: a [CloudException],
  /// a [FormatException], or the photos could not be read.
  final Object? error;

  /// The church or account changed, which dropped the earlier draft. Said
  /// until rows are loaded or something else goes wrong.
  final bool scopeChanged;

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
    ImportMode? mode,
    bool? busy,
    Object? error,
    bool clearError = false,
  }) => ImportDraft(
    rows: rows ?? this.rows,
    loaded: loaded ?? this.loaded,
    people: people ?? this.people,
    mode: mode ?? this.mode,
    busy: busy ?? this.busy,
    error: clearError ? null : error ?? this.error,
    scopeChanged: scopeChanged && !clearError && error == null,
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

  /// Reads [images] into rows, replacing the draft's.
  Future<void> recognize(List<PhotoInput> images) async {
    final draft = _draft;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final rows = await ref.churchData.recognizeRoster(serviceType, images);
      if (_isCurrent(draft)) load(rows);
    } catch (e) {
      if (_isCurrent(draft)) fail(e);
    } finally {
      if (_isCurrent(draft)) state = state.copyWith(busy: false);
    }
  }

  /// No rows came, because of [error].
  void fail(Object error) => state = state.copyWith(error: error);

  /// Loads [rows] as new: who each name is is asked again.
  void load(List<dynamic> rows) => state = state.copyWith(
    // Never share the recognizer's response or a caller's list.
    rows: jsonDecode(jsonEncode(rows)) as List<dynamic>,
    loaded: true,
    people: const {},
    clearError: true,
  );

  /// Loads pasted [text], which must be a JSON array.
  void paste(String text) {
    try {
      final rows = jsonDecode(text);
      if (rows is! List) throw const FormatException();
      load(rows);
    } on FormatException catch (e) {
      fail(e);
    }
  }

  /// Replaces the rows with [rows], edited: who each name is stays.
  void edit(List<dynamic> rows) =>
      state = state.copyWith(rows: jsonDecode(jsonEncode(rows)) as List<dynamic>, clearError: true);

  void updateRow(int index, Map<String, dynamic> row) =>
      edit([for (final (i, old) in state.rows.indexed) i == index ? row : old]);

  void choose(String name, ImportPersonChoice choice) =>
      state = state.copyWith(people: {...state.people, name: choice});

  void setMode(ImportMode mode) => state = state.copyWith(mode: mode);

  /// The members [name] could be: same name, or what it may shorten.
  List<Member> candidates(String name) {
    final members = ref.read(membersProvider).value ?? const <Member>[];
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

  /// Admins: lets the member serve the duty, so their name binds.
  Future<void> grantDuty(ImportQualification qualification) =>
      _repair(() => ref.read(rosterActionsProvider).grantDuty(qualification.member, serviceType, qualification.role));

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
  ChurchWrite apply(ImportPlan shown) => ref
      .read(rosterActionsProvider)
      .applyImport(serviceType, state.rows, people: state.people, mode: state.mode, preview: shown);
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
    ..watch(membersProvider)
    ..watch(staffOrderProvider(serviceType))
    ..watch(todayProvider);
  if (!draft.loaded || !ready) return null;
  return ref.read(rosterActionsProvider).previewImport(serviceType, draft.rows, people: draft.people, mode: draft.mode);
});
