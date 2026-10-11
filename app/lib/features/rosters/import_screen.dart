import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/roster_import.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_update.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import 'format.dart';

final _quotaProvider = FutureProvider.autoDispose<PhotoQuota>((ref) => openChurch(ref).photoQuota());

/// Photos and the documented JSON format enter the same editable preview.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.serviceType});
  final String serviceType;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _busy = false;
  bool _ready = false;
  bool _paste = false;
  String? _error;
  ImportPlan? _plan;
  List<dynamic> _rows = const [];
  TextEditingController _json = TextEditingController();
  ({String? cid, String? uid})? _sourceScope;
  int _scopeEpoch = 0;
  ({String? cid, String? uid}) get _scope => (cid: ref.read(currentChurchIdProvider), uid: ref.read(uidProvider));
  bool get _sameScope => _scope == _sourceScope && _scope.cid != null && _scope.uid != null;
  final _people = <String, ImportPersonChoice>{};
  ImportMode _mode = ImportMode.merge;

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<T> _during<T>(Future<T> Function() work) => ref.read(updateEditLockProvider).during(work);

  Future<void> _photos(ImageSource source) => _during(() => _readPhotos(source));

  Future<void> _readPhotos(ImageSource source) async {
    final l10n = L10n.of(context);
    final scope = _scope;
    final epoch = _scopeEpoch;
    final data = ref.churchData;
    bool current() => mounted && _scope == scope && _scopeEpoch == epoch;
    try {
      final picker = ImagePicker();
      final files = source == ImageSource.camera
          ? [?await picker.pickImage(source: source, maxWidth: 2400, imageQuality: 85)]
          : await picker.pickMultiImage(maxWidth: 2400, imageQuality: 85, limit: 3);
      if (!current() || files.isEmpty) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final images = [
        for (final f in files.take(3)) PhotoInput(mimeType: f.mimeType ?? 'image/jpeg', bytes: await f.readAsBytes()),
      ];
      final rows = await data.recognizeRoster(widget.serviceType, images);
      if (!current()) return;
      ref.invalidate(_quotaProvider);
      _makePlan(rows, clearChoices: true);
    } on CloudException catch (e) {
      if (!current()) return;
      setState(
        () => _error = switch ((e.code, e.reason)) {
          (CloudErrorCode.quotaExceeded, CloudReason.platform) => l10n.photoPlatformOff,
          (CloudErrorCode.quotaExceeded, _) => l10n.photoChurchLimit(ref.read(_quotaProvider).value?.limit ?? 30),
          (_, CloudReason.tooLarge) => l10n.photoTooLarge,
          (_, CloudReason.unparseable) => l10n.importPhotoFormatError,
          (CloudErrorCode.unavailable, CloudReason.offlineReadOnly) => l10n.errOfflineReadOnly,
          (CloudErrorCode.unavailable, _) => l10n.photoUnavailable,
          _ => l10n.photoFailed,
        },
      );
    } catch (_) {
      if (current()) setState(() => _error = l10n.photoFailed);
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  ImportPlan _planFor(List<dynamic> rows) =>
      ref.read(rosterActionsProvider).previewImport(widget.serviceType, rows, people: _people, mode: _mode);

  void _makePlan(List<dynamic> rows, {bool clearChoices = false}) {
    if (!_sameScope) return;
    setState(() {
      // Do not mutate the recognizer's response or a backend-owned fixture.
      _rows = jsonDecode(jsonEncode(rows)) as List<dynamic>;
      if (clearChoices) _people.clear();
      _plan = _planFor(_rows);
      _error = null;
    });
  }

  void _parsePasted() {
    if (!_sameScope || !_ready || _busy) return;
    try {
      final rows = jsonDecode(_json.text);
      if (rows is! List) throw const FormatException();
      _makePlan(rows, clearChoices: true);
    } on FormatException {
      setState(() => _error = L10n.of(context).importJsonSyntaxError);
    }
  }

  Future<void> _resolveName(String raw, List<Member> candidates) => _during(() => _confirmName(raw, candidates));

  Future<void> _confirmName(String raw, List<Member> candidates) async {
    final epoch = _scopeEpoch;
    final choice = await showAppSheet<ImportPersonChoice>(
      context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          ListRow(title: L10n.of(context).importConfirmName(raw), subtitle: L10n.of(context).importSameNameScope),
          for (final member in candidates)
            ListRow(
              title: member.name,
              subtitle: member.email.isEmpty ? member.uid : member.email,
              onTap: () => Navigator.pop(sheetContext, ImportPersonChoice.member(member.uid)),
            ),
          ListRow(
            title: L10n.of(context).importGuestChoice(raw),
            onTap: () => Navigator.pop(sheetContext, const ImportPersonChoice.guest()),
          ),
          ListRow(title: L10n.of(context).cancel, onTap: () => Navigator.pop(sheetContext)),
        ],
      ),
    );
    if (!mounted || choice == null || !_ready || !_sameScope || epoch != _scopeEpoch) return;
    setState(() {
      _people[raw] = choice;
      _plan = _planFor(_rows);
    });
  }

  Future<_ImportEdit?> _edit({
    required String title,
    required List<_ImportField> fields,
    int? color,
    bool removable = false,
  }) async {
    final epoch = _scopeEpoch;
    final result = await _during(
      () => showAppSheet<_ImportEdit>(
        context,
        builder: (_) => _ImportEditor(title: title, fields: fields, color: color, removable: removable),
      ),
    );
    return mounted && _sameScope && epoch == _scopeEpoch ? result : null;
  }

  Future<void> _editJson() async {
    final result = await _edit(
      title: L10n.of(context).importJsonEdit,
      fields: [
        _ImportField(
          'JSON',
          const JsonEncoder.withIndent('  ').convert(_rows),
          lines: 10,
          validate: (text) {
            try {
              if (jsonDecode(text) is List) return null;
            } on FormatException {
              // The field stays open so the entered text can be corrected.
            }
            return L10n.of(context).importJsonArrayRequired;
          },
        ),
      ],
    );
    if (!mounted || result == null || !_ready) return;
    _makePlan(jsonDecode(result.values.single) as List<dynamic>);
  }

  void _updateRow(int index, Map<String, dynamic> row) {
    _makePlan([for (final (i, old) in _rows.indexed) i == index ? row : old]);
  }

  Future<void> _editDate(int index, Map<dynamic, dynamic> row) async {
    final result = await _edit(
      title: L10n.of(context).importEditDate,
      fields: [
        _ImportField(
          L10n.of(context).importDateFormatLabel,
          row['date'] is String ? row['date'] as String : '',
          validate: (text) => Day.tryParse(text.trim()) == null ? L10n.of(context).importValidDate : null,
        ),
      ],
    );
    if (!mounted || result == null || !_ready) return;
    _updateRow(index, Map<String, dynamic>.from(row)..['date'] = result.values.single.trim());
  }

  Future<void> _editDuty(int index, Map<dynamic, dynamic> row, int? dutyIndex) async {
    final duties = row['duties'] is List ? List<dynamic>.of(row['duties'] as List<dynamic>) : <dynamic>[];
    final duty = dutyIndex == null ? const <String, dynamic>{} : duties[dutyIndex];
    if (duty is! Map) return _editJson();
    final result = await _edit(
      title: dutyIndex == null ? L10n.of(context).addDuty : L10n.of(context).importEditDuty,
      fields: [
        _ImportField(L10n.of(context).importDutyLabel, duty['role'] is String ? duty['role'] as String : ''),
        _ImportField(
          L10n.of(context).importPeopleLines,
          duty['people'] is List ? (duty['people'] as List<dynamic>).join('\n') : '',
          lines: 4,
          validate: (_) => null,
        ),
      ],
      removable: dutyIndex != null,
    );
    if (!mounted || result == null || !_ready) return;
    if (result.remove) {
      duties.removeAt(dutyIndex!);
    } else {
      final next = {
        'role': result.values[0].trim(),
        'people': result.values[1].split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      };
      if (dutyIndex == null) {
        duties.add(next);
      } else {
        duties[dutyIndex] = next;
      }
    }
    _updateRow(index, Map<String, dynamic>.from(row)..['duties'] = duties);
  }

  Future<void> _editEvent(int index, Map<dynamic, dynamic> row, int? eventIndex) async {
    final events = row['events'] is List ? List<dynamic>.of(row['events'] as List<dynamic>) : <dynamic>[];
    final event = eventIndex == null ? const <String, dynamic>{} : events[eventIndex];
    if (event is! Map) return _editJson();
    final color = event['color'];
    final result = await _edit(
      title: eventIndex == null ? L10n.of(context).importAddEventAction : L10n.of(context).importEditEvent,
      fields: [_ImportField(L10n.of(context).eventName, event['name'] is String ? event['name'] as String : '')],
      color: color is int && color >= 0 && color < EventColors.count ? color : 0,
      removable: eventIndex != null,
    );
    if (!mounted || result == null || !_ready) return;
    if (result.remove) {
      events.removeAt(eventIndex!);
    } else {
      final next = {'name': result.values.single.trim(), 'color': result.color};
      if (eventIndex == null) {
        events.add(next);
      } else {
        events[eventIndex] = next;
      }
    }
    _updateRow(index, Map<String, dynamic>.from(row)..['events'] = events);
  }

  Future<void> _repair(Future<void> Function() write) => _during(() => _repairSettings(write));

  Future<void> _repairSettings(Future<void> Function() write) async {
    if (!_sameScope || !_ready || _busy || ref.read(meProvider).value?.isAdmin != true) return;
    final epoch = _scopeEpoch;
    setState(() => _busy = true);
    try {
      await write();
      if (mounted && _sameScope && epoch == _scopeEpoch) Haptics.success();
    } catch (_) {
      if (mounted && _sameScope && epoch == _scopeEpoch) showToast(context, L10n.of(context).saveFailed);
    } finally {
      if (mounted && _sameScope && epoch == _scopeEpoch) setState(() => _busy = false);
    }
  }

  Service get _service =>
      ref.read(servicesProvider).requireValue.byId(widget.serviceType) ?? (throw StateError('No service'));

  Future<void> _repairDuty(String role) => _repair(() async {
    final before = _service;
    if (before.duties.contains(role)) return;
    await ref.churchData.compareAndSetService(
      before: before,
      after: before.copyWith(duties: [...before.duties, role]),
    );
  });

  Future<void> _repairQualification(ImportQualification qualification) =>
      _repair(() => ref.churchData.grantDuty(qualification.member.uid, widget.serviceType, qualification.role));

  Future<void> _repairEvent(EventTag event) => _repair(() async {
    final before = _service;
    if (before.events.any((e) => e.name == event.name)) return;
    await ref.churchData.compareAndSetService(
      before: before,
      after: before.copyWith(events: [...before.events, event]),
    );
  });

  Future<void> _apply() => _during(_applyRows);

  Future<void> _applyRows() async {
    final l10n = L10n.of(context);
    if (!_sameScope || !_ready || _busy || _plan?.canApply != true) return;
    final epoch = _scopeEpoch;
    final days = _plan!.rosters.length;
    setState(() => _busy = true);
    try {
      final write = ref
          .read(rosterActionsProvider)
          .applyImport(widget.serviceType, _rows, people: _people, mode: _mode, preview: _plan);
      await write.done;
      Haptics.success();
      if (!mounted || !_sameScope || epoch != _scopeEpoch) return;
      showToast(context, l10n.importApplied(days), onUndo: write.undo);
      Navigator.of(context).pop();
    } on CloudException catch (error) {
      if (mounted && _sameScope && epoch == _scopeEpoch) {
        showToast(context, error.code == CloudErrorCode.conflict ? l10n.importConflict : l10n.saveFailed);
      }
    } catch (_) {
      if (mounted && _sameScope && epoch == _scopeEpoch) showToast(context, l10n.saveFailed);
    } finally {
      if (mounted && _sameScope && epoch == _scopeEpoch) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final scope = (cid: ref.watch(currentChurchIdProvider), uid: ref.watch(uidProvider));
    if (_sourceScope != null && _sourceScope != scope) {
      _scopeEpoch++;
      _rows = const [];
      _plan = null;
      _people.clear();
      _mode = ImportMode.merge;
      _paste = false;
      _busy = false;
      _error = l10n.importScopeChanged;
      // The old field is removed in this frame; do not notify it mid-build.
      final old = _json;
      _json = TextEditingController();
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _sourceScope = scope;
    _ready =
        ref.watch(rosterEditingProvider(widget.serviceType)) &&
        ref.watch(churchOpenProvider) &&
        (ref.watch(meProvider).value?.canEditRosters(widget.serviceType) ?? false);
    if (_plan != null) {
      // Readiness stays true when loaded data changes. Watch the actual
      // preview inputs so a rendered frame records the latest baseline.
      ref.watch(savedRostersProvider);
      ref.watch(servicesProvider);
      ref.watch(membersProvider);
      ref.watch(staffOrderProvider(widget.serviceType));
      ref.watch(todayProvider);
    }
    if (_ready && _plan != null) _plan = _planFor(_rows);
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: Text(plan == null ? l10n.photoImport : l10n.importPreview),
        actions: [
          if (plan != null)
            IconButton(
              tooltip: l10n.importJsonEdit,
              onPressed: _ready && !_busy ? _editJson : null,
              icon: const Icon(Icons.code),
            ),
        ],
      ),
      body: plan != null ? _preview(plan, l10n) : _start(l10n, c),
    );
  }

  Widget _start(L10n l10n, AppColors c) {
    final quota = ref.watch(_quotaProvider).value;
    final blocked = !_ready || (quota != null && (!quota.platformOpen || quota.remaining <= 0));
    return ListView(
      padding: const EdgeInsets.all(Space.m),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: Text(
            quota == null
                ? ' '
                : !quota.platformOpen
                ? l10n.photoPlatformOff
                : quota.remaining <= 0
                ? l10n.photoChurchLimit(quota.limit)
                : l10n.photoRemaining(quota.remaining),
            style: AppText.subheadline.copyWith(color: c.secondaryLabel),
          ),
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              children: [
                const CircularProgressIndicator.adaptive(),
                const SizedBox(height: Space.m),
                Text(l10n.photoRecognizing, style: AppText.body.copyWith(color: c.secondaryLabel)),
              ],
            ),
          )
        else ...[
          PrimaryButton(
            label: l10n.photoTake,
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: blocked ? null : () => _photos(ImageSource.camera),
          ),
          const SizedBox(height: Space.s),
          SecondaryButton(
            label: l10n.photoPick,
            expand: true,
            onPressed: blocked ? null : () => _photos(ImageSource.gallery),
          ),
          ExpansionTile(
            title: Text(l10n.importAdvanced),
            children: [
              SecondaryButton(
                label: l10n.photoPasteJson,
                expand: true,
                onPressed: _ready ? () => setState(() => _paste = !_paste) : null,
              ),
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: SelectableText(
                  // The JSON protocol example is never translated.
                  '[{"date":"2026-10-18","duties":[{"role":"司琴","people":["李美玉"]}],'
                  '"events":[{"name":"聖餐","color":0}]}]\n'
                  '${l10n.importFormatHelp}',
                  style: AppText.footnote,
                ),
              ),
            ],
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: Text(_error!, style: AppText.subheadline.copyWith(color: c.destructive)),
          ),
        if (_paste) ...[
          const SizedBox(height: Space.m),
          TextField(
            controller: _json,
            maxLines: 8,
            style: AppText.footnote.copyWith(fontFamily: 'monospace'),
            decoration: InputDecoration(hintText: l10n.jsonHint),
          ),
          const SizedBox(height: Space.s),
          SecondaryButton(label: l10n.next2, expand: true, onPressed: _ready && !_busy ? _parsePasted : null),
        ],
      ],
    );
  }

  Widget _inputRow(int index, Map<dynamic, dynamic> row, L10n l10n) {
    final rawDate = row['date'];
    final day = rawDate is String ? Day.tryParse(rawDate) : null;
    final duties = row['duties'];
    final events = row['events'];
    final enabled = _ready && !_busy;
    return ListSection(
      header: day == null ? l10n.importRow(index + 1) : dayLabel(l10n, day, ref.read(todayProvider)),
      children: [
        ListRow(
          title: l10n.importDateLabel,
          subtitle: rawDate is String ? rawDate : l10n.importDateMissing,
          onTap: enabled ? () => _editDate(index, row) : null,
        ),
        if (duties is List)
          for (final (i, duty) in duties.indexed)
            ListRow(
              title: duty is Map && duty['role'] is String ? duty['role'] as String : l10n.importFixDuty,
              subtitle: duty is Map && duty['people'] is List
                  ? (duty['people'] as List<dynamic>).isEmpty
                        ? l10n.nobodyYet
                        : (duty['people'] as List<dynamic>).join('、')
                  : l10n.importPeopleArrayHint,
              onTap: enabled ? () => _editDuty(index, row, i) : null,
            ),
        ListRow(
          title: l10n.addDuty,
          leading: const Icon(Icons.add),
          onTap: enabled ? () => _editDuty(index, row, null) : null,
        ),
        if (events is List)
          for (final (i, event) in events.indexed)
            ListRow(
              title: event is Map && event['name'] is String ? event['name'] as String : l10n.importFixEvent,
              leading:
                  event is Map &&
                      event['color'] is int &&
                      (event['color'] as int) >= 0 &&
                      (event['color'] as int) < EventColors.count
                  ? Tag.event(context, ' ', event['color'] as int)
                  : null,
              onTap: enabled ? () => _editEvent(index, row, i) : null,
            ),
        ListRow(
          title: l10n.importAddEventAction,
          leading: const Icon(Icons.add),
          onTap: enabled ? () => _editEvent(index, row, null) : null,
        ),
      ],
    );
  }

  List<Widget> _diffRows(ImportChange change, L10n l10n) {
    final before = change.before;
    final after = change.after;
    final rows = <Widget>[];
    for (final duty in before?.duties ?? const <Duty>[]) {
      if (!after.duties.any((d) => d.role == duty.role)) {
        rows.add(
          ListRow(
            title: l10n.importRemoveDuty(duty.role, duty.people.isEmpty ? l10n.nobodyYet : duty.people.join('、')),
          ),
        );
      }
    }
    for (final duty in after.duties) {
      final old = before?.duties.where((d) => d.role == duty.role).firstOrNull;
      if (old == duty) continue;
      final names = duty.people.isEmpty ? l10n.nobodyYet : duty.people.join('、');
      rows.add(
        ListRow(
          title: old == null
              ? l10n.importAddDuty(duty.role, names)
              : l10n.importChangeDuty(duty.role, old.people.isEmpty ? l10n.nobodyYet : old.people.join('、'), names),
          subtitle: [
            for (final name in duty.people)
              duty.uids.containsKey(name) ? l10n.importMemberIdentity(name) : l10n.importGuestIdentity(name),
          ].join('、'),
        ),
      );
    }
    for (final event in before?.events ?? const <EventTag>[]) {
      if (!after.events.any((e) => e.name == event.name)) rows.add(ListRow(title: l10n.importRemoveEvent(event.name)));
    }
    for (final event in after.events) {
      final old = before?.events.where((e) => e.name == event.name).firstOrNull;
      if (old == event) continue;
      rows.add(
        ListRow(
          title: old == null ? l10n.importAddEvent(event.name) : l10n.importChangeEvent(event.name),
          subtitle: old == null
              ? _colorName(l10n, event.color)
              : l10n.importChangedColor(_colorName(l10n, old.color), _colorName(l10n, event.color)),
        ),
      );
    }
    return rows.isEmpty ? [ListRow(title: l10n.importNoChange)] : rows;
  }

  Set<String> get _sheetNames {
    final names = <String>{};
    for (final row in _rows) {
      if (row is! Map || row['duties'] is! List) continue;
      for (final duty in row['duties'] as List<dynamic>) {
        if (duty is! Map || duty['people'] is! List) continue;
        for (final name in duty['people'] as List<dynamic>) {
          if (name is String && name.trim().isNotEmpty) names.add(name.trim());
        }
      }
    }
    return names;
  }

  List<Member> _candidates(String raw) {
    final members = ref.read(membersProvider).value ?? const <Member>[];
    final hints = ImportReport();
    NameMatcher(members).resolve(raw, hints);
    return [
      for (final member in members)
        if (member.name.trim() == raw ||
            hints.notInList[raw]?.contains(member.name.trim()) == true ||
            (hints.ambiguous.contains(raw) && member.name.trim().endsWith(raw)) ||
            member.uid == _people[raw]?.uid)
          member,
    ];
  }

  String _nameStatus(String raw, ImportReport report, L10n l10n) {
    if (report.unresolved.containsKey(raw)) {
      final candidates = report.unresolved[raw]!;
      return candidates.isEmpty
          ? l10n.importNoCandidate
          : l10n.importCandidates(candidates.map((m) => m.name).join('、'));
    }
    final choice = _people[raw];
    if (choice != null && choice.uid == null) return l10n.importGuestUnlinked;
    final member = _candidates(
      raw,
    ).where((m) => choice == null ? m.name.trim() == raw : m.uid == choice.uid).firstOrNull;
    return member == null ? l10n.importNameNeedsConfirm : l10n.importLinkedMember(member.name);
  }

  Widget _preview(ImportPlan plan, L10n l10n) {
    final report = plan.report;
    final admin = ref.watch(meProvider).value?.isAdmin ?? false;
    final repairable = _ready && !_busy && admin;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              if (_rows.isEmpty) EmptyState(message: l10n.importNothing),
              ListSection(
                header: l10n.importMode,
                children: [
                  ListRow(
                    title: l10n.importMerge,
                    selected: _mode == ImportMode.merge,
                    onTap: _ready && !_busy ? () => setState(() => _mode = ImportMode.merge) : null,
                  ),
                  ListRow(
                    title: l10n.importReplace,
                    selected: _mode == ImportMode.replace,
                    subtitle: l10n.importReplaceHelp,
                    onTap: _ready && !_busy ? () => setState(() => _mode = ImportMode.replace) : null,
                  ),
                ],
              ),
              if (report.badRows.isNotEmpty)
                ListSection(
                  header: l10n.importFixData,
                  children: [
                    for (final row in report.badRows)
                      ListRow(
                        title: l10n.importRow(row),
                        subtitle:
                            report.errors[row]?.map((issue) => importIssueText(l10n, issue)).join('\n') ??
                            l10n.importFixRow,
                        onTap: _ready && !_busy ? _editJson : null,
                      ),
                  ],
                ),
              if (_sheetNames.isNotEmpty)
                ListSection(
                  header: report.unresolved.isEmpty ? l10n.importNameLinks : l10n.importNamesNeedConfirm,
                  children: [
                    for (final name in {...report.unresolved.keys, ..._sheetNames})
                      ListRow(
                        title: name,
                        subtitle: _nameStatus(name, report, l10n),
                        onTap: _ready && !_busy ? () => _resolveName(name, _candidates(name)) : null,
                      ),
                  ],
                ),
              if (report.unknownDuties.isNotEmpty ||
                  report.missingQualifications.isNotEmpty ||
                  report.unknownEvents.isNotEmpty)
                ListSection(
                  header: admin ? l10n.importRepairSettings : l10n.importNoSettingsChange,
                  children: [
                    for (final role in report.unknownDuties)
                      ListRow(
                        title: admin ? l10n.importAddConfiguredDuty(role) : l10n.importUnconfiguredDuty(role),
                        onTap: repairable ? () => _repairDuty(role) : null,
                      ),
                    for (final qualification in report.missingQualifications)
                      ListRow(
                        title: admin
                            ? l10n.importGrantQualification(qualification.member.name, qualification.role)
                            : l10n.importMissingQualification(qualification.member.name, qualification.role),
                        onTap: repairable ? () => _repairQualification(qualification) : null,
                      ),
                    for (final event in report.unknownEvents)
                      ListRow(
                        title: admin ? l10n.importAddCommonEvent(event.name) : l10n.importNotCommonEvent(event.name),
                        onTap: repairable ? () => _repairEvent(event) : null,
                      ),
                  ],
                ),
              if (report.pastDays.isNotEmpty)
                ListSection(
                  header: l10n.importPastDays,
                  children: [for (final day in report.pastDays) ListRow(title: day)],
                ),
              for (final (i, row) in _rows.indexed)
                if (row is Map) _inputRow(i, row, l10n),
              for (final change in plan.changes.values)
                ListSection(
                  header: l10n.importDiff(dayLabel(l10n, change.after.day, ref.read(todayProvider))),
                  children: _diffRows(change, l10n),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: PrimaryButton(
              label: l10n.importApply,
              busy: _busy,
              onPressed: _ready && plan.canApply ? _apply : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportField {
  const _ImportField(this.label, this.initial, {this.lines = 1, this.validate});
  final String label;
  final String initial;
  final int lines;
  final String? Function(String)? validate;
}

class _ImportEdit {
  const _ImportEdit(this.values, {this.color, this.remove = false});
  final List<String> values;
  final int? color;
  final bool remove;
}

class _ImportEditor extends StatefulWidget {
  const _ImportEditor({required this.title, required this.fields, this.color, this.removable = false});
  final String title;
  final List<_ImportField> fields;
  final int? color;
  final bool removable;

  @override
  State<_ImportEditor> createState() => _ImportEditorState();
}

class _ImportEditorState extends State<_ImportEditor> {
  final _form = GlobalKey<FormState>();
  late final _controllers = [for (final field in widget.fields) TextEditingController(text: field.initial)];
  late int? _color = widget.color;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.m, 0, Space.m, MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(widget.title, style: AppText.title3),
              for (final (i, field) in widget.fields.indexed)
                Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: TextFormField(
                    controller: _controllers[i],
                    maxLines: field.lines,
                    decoration: InputDecoration(labelText: field.label),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) => field.validate != null
                        ? field.validate!(value ?? '')
                        : (value?.trim().isEmpty ?? true)
                        ? l10n.importRequiredField(field.label)
                        : null,
                  ),
                ),
              if (_color != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: DropdownButtonFormField<int>(
                    initialValue: _color,
                    decoration: InputDecoration(labelText: l10n.importColor),
                    items: [
                      for (var i = 0; i < EventColors.count; i++)
                        DropdownMenuItem(value: i, child: Text(_colorName(l10n, i))),
                    ],
                    onChanged: (value) => setState(() => _color = value),
                  ),
                ),
              const SizedBox(height: Space.m),
              PrimaryButton(
                label: l10n.done,
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(
                      context,
                      _ImportEdit([for (final controller in _controllers) controller.text], color: _color),
                    );
                  }
                },
              ),
              SecondaryButton(label: l10n.cancel, expand: true, onPressed: () => Navigator.pop(context)),
              if (widget.removable)
                SecondaryButton(
                  label: l10n.remove,
                  expand: true,
                  destructive: true,
                  onPressed: () => Navigator.pop(context, const _ImportEdit([], remove: true)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Presentation belongs here, never in the domain validation contract.
String importIssueText(L10n l10n, ImportIssue issue) {
  int index() => issue.args['index'] as int;
  return switch (issue.code) {
    ImportIssueCode.rowObject => l10n.importIssueRowObject,
    ImportIssueCode.rowFields => l10n.importIssueRowFields,
    ImportIssueCode.date => l10n.importIssueDate,
    ImportIssueCode.duplicateDate => l10n.importIssueDuplicateDate,
    ImportIssueCode.dutiesArray => l10n.importIssueDutiesArray,
    ImportIssueCode.dutyFields => l10n.importIssueDutyFields(index()),
    ImportIssueCode.role => l10n.importIssueRole(index()),
    ImportIssueCode.peopleArray => l10n.importIssuePeopleArray(index()),
    ImportIssueCode.duplicatePeople => l10n.importIssueDuplicatePeople(index()),
    ImportIssueCode.eventsArray => l10n.importIssueEventsArray,
    // The protocol literal is never translated.
    ImportIssueCode.eventObject => l10n.importIssueEventObject(index(), '{"name":"活動名稱","color":0}'),
    ImportIssueCode.eventName => l10n.importIssueEventName(index()),
    ImportIssueCode.eventColor => l10n.importIssueEventColor(index()),
    ImportIssueCode.resolvedDuplicatePeople => l10n.importIssueResolvedDuplicatePeople(issue.args['role'] as String),
  };
}

String _colorName(L10n l10n, int i) => switch (i) {
  0 => l10n.colorName0,
  1 => l10n.colorName1,
  2 => l10n.colorName2,
  3 => l10n.colorName3,
  4 => l10n.colorName4,
  _ => l10n.colorName5,
};
