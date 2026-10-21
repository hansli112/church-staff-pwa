import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
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
import '../../state/import_session.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../../state/session.dart';
import '../common/errors.dart';
import 'format.dart';

final _quotaProvider = FutureProvider.autoDispose<PhotoQuota>((ref) => openChurch(ref).photoQuota());

/// Photos and the documented JSON format enter the same editable preview.
/// What is being imported lives in [importSessionProvider]; this screen
/// shows it and asks.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.serviceType});
  final String serviceType;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _ready = false;
  bool _paste = false;
  bool _applying = false;
  TextEditingController _json = TextEditingController();

  ImportSession get _session => ref.read(importSessionProvider(widget.serviceType).notifier);

  ImportDraft get _draft => ref.read(importSessionProvider(widget.serviceType));

  bool get _busy => _draft.busy || _applying;

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<T> _during<T>(Future<T> Function() work) => ref.read(updateEditLockProvider).during(work);

  /// Whether the draft that was current at [key] still is.
  bool _sameDraft(Object key) => identical(_session.draftKey, key);

  /// The draft this page last showed: a new one (another church or account)
  /// drops the pasted text.
  Object? _shownDraft;

  /// The preview last planned, still shown (its controls off) while the
  /// page cannot edit for a moment: offline, or data reloading.
  ImportPlan? _lastPlan;

  Future<void> _photos(ImageSource source) => _during(() => _readPhotos(source));

  Future<void> _readPhotos(ImageSource source) async {
    final key = _session.draftKey;
    if (!await _agreedToPhotoAi()) return;
    try {
      final picker = ImagePicker();
      final files = source == ImageSource.camera
          ? [?await picker.pickImage(source: source, maxWidth: 2400, imageQuality: 85)]
          : await picker.pickMultiImage(maxWidth: 2400, imageQuality: 85, limit: 3);
      if (!(mounted && _sameDraft(key)) || files.isEmpty) return;
      final images = [
        for (final f in files.take(3)) PhotoInput(mimeType: f.mimeType ?? 'image/jpeg', bytes: await f.readAsBytes()),
      ];
      if (!(mounted && _sameDraft(key))) return;
      await _session.recognize(images);
    } catch (e) {
      // The picker or the files failing: nothing was read.
      if (mounted && _sameDraft(key)) _session.fail(e);
    }
    if (mounted) ref.invalidate(_quotaProvider);
  }

  /// Whether this account agreed that recognition sends the photos and the
  /// member list to Google's Gemini (App Store 5.1.2(i)); asks the first
  /// time. Pasting JSON from one's own AI sends nothing and never asks.
  Future<bool> _agreedToPhotoAi() async {
    final l10n = L10n.of(context);
    final UserProfile? profile;
    try {
      profile = await ref.read(profileProvider.future);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
      return false;
    }
    if (profile == null || !mounted) return false;
    if (profile.photoAiConsent) return true;
    final yes = await askChoice(
      context,
      title: l10n.photoAiTitle,
      message: l10n.photoAiBody,
      yes: l10n.photoAiAgree,
      no: l10n.cancel,
    );
    if (yes != true || !mounted) return false;
    try {
      await ref.read(backendProvider).profiles.agreeToPhotoAi(profile.uid);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
      return false;
    }
    return mounted;
  }

  void _parsePasted() {
    if (!_ready || _busy) return;
    _session.paste(_json.text);
  }

  Future<void> _resolveName(String raw, List<Member> candidates) => _during(() => _confirmName(raw, candidates));

  Future<void> _confirmName(String raw, List<Member> candidates) async {
    final key = _session.draftKey;
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
    if (choice == null || !_ready || !(mounted && _sameDraft(key))) return;
    _session.choose(raw, choice);
  }

  Future<_ImportEdit?> _edit({
    required String title,
    required List<_ImportField> fields,
    int? color,
    bool removable = false,
  }) async {
    final key = _session.draftKey;
    final result = await _during(
      () => showAppSheet<_ImportEdit>(
        context,
        builder: (_) => _ImportEditor(title: title, fields: fields, color: color, removable: removable),
      ),
    );
    return mounted && _sameDraft(key) && _ready ? result : null;
  }

  Future<void> _editJson() async {
    final result = await _edit(
      title: L10n.of(context).importJsonEdit,
      fields: [
        _ImportField(
          'JSON',
          const JsonEncoder.withIndent('  ').convert(_draft.rows),
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
    if (result == null) return;
    _session.edit(jsonDecode(result.values.single) as List<dynamic>);
  }

  Future<void> _editDate(int index, Map<dynamic, dynamic> row) async {
    final key = _session.draftKey;
    final today = ref.read(todayProvider);
    final day = row['date'] is String ? Day.tryParse((row['date'] as String).trim()) : null;
    // From today on: days before it are skipped by the import.
    final picked = await _during(
      () => pickDay(
        context,
        title: L10n.of(context).importEditDate,
        initial: (day ?? today).midnight,
        first: today.midnight,
        last: DateTime.utc(today.year + 2, 12, 31),
      ),
    );
    if (picked == null || !(mounted && _sameDraft(key) && _ready)) return;
    final date = Day(picked.year, picked.month, picked.day);
    _session.updateRow(index, Map<String, dynamic>.from(row)..['date'] = date.toString());
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
    if (result == null) return;
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
    _session.updateRow(index, Map<String, dynamic>.from(row)..['duties'] = duties);
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
    if (result == null) return;
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
    _session.updateRow(index, Map<String, dynamic>.from(row)..['events'] = events);
  }

  /// Admins: changes the service's settings so the import fits them.
  Future<void> _repair(Future<void> Function() write) => _during(() async {
    if (!_ready || _busy || ref.read(meProvider).value?.isAdmin != true) return;
    final key = _session.draftKey;
    try {
      await write();
      if (mounted && _sameDraft(key)) Haptics.success();
    } catch (e) {
      if (mounted && _sameDraft(key)) showToast(context, saveErrorText(L10n.of(context), e));
    }
  });

  Future<void> _apply(ImportPlan shown) => _during(() => _applyShown(shown));

  Future<void> _applyShown(ImportPlan shown) async {
    final l10n = L10n.of(context);
    if (!_ready || _busy || !shown.canApply) return;
    final key = _session.draftKey;
    setState(() => _applying = true);
    try {
      final write = _session.apply(shown);
      await write.done;
      Future<void> Function()? forget;
      if (ref.read(meProvider).value?.isAdmin ?? false) {
        // Goes on after this page closes: one that fails only means a
        // search next time, so it is recorded, not shown.
        final telemetry = ref.read(telemetryProvider);
        final remembered = _session.rememberDuties(shown);
        unawaited(remembered.done.catchError((Object e, StackTrace s) => telemetry.recordError(e, s)));
        forget = remembered.undo;
      }
      Haptics.success();
      if (!(mounted && _sameDraft(key))) return;
      showToast(
        context,
        l10n.importApplied(shown.rosters.length),
        onUndo: () async {
          await write.undo();
          await forget?.call();
        },
      );
      Navigator.of(context).pop();
    } on CloudException catch (error) {
      if (mounted && _sameDraft(key)) {
        showToast(context, error.code == CloudErrorCode.conflict ? l10n.importConflict : errorText(l10n, error));
      }
    } catch (_) {
      if (mounted && _sameDraft(key)) showToast(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// The backend's photo prompt, for the editor's own AI; its JSON comes
  /// back through 貼上 JSON.
  Future<void> _copyPrompt() async {
    final l10n = L10n.of(context);
    try {
      final prompt = await ref.churchData.photoPrompt(widget.serviceType);
      await Clipboard.setData(ClipboardData(text: prompt));
      if (mounted) showToast(context, l10n.importPromptCopied);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    }
  }

  /// What to say about why the last photos or pasted text gave no rows.
  String? _errorText(ImportDraft draft, L10n l10n) => switch (draft.error) {
    FormatException() => l10n.importJsonSyntaxError,
    CloudException(:final code, :final reason) => switch ((code, reason)) {
      (CloudErrorCode.quotaExceeded, CloudReason.platform) => l10n.photoPlatformOff,
      (CloudErrorCode.quotaExceeded, _) => l10n.photoChurchLimit(ref.read(_quotaProvider).value?.limit ?? 30),
      (_, CloudReason.tooLarge) => l10n.photoTooLarge,
      (_, CloudReason.unparseable) => l10n.importPhotoFormatError,
      (CloudErrorCode.unavailable, CloudReason.offlineReadOnly) => l10n.errOfflineReadOnly,
      (CloudErrorCode.unavailable, _) => l10n.photoUnavailable,
      _ => l10n.photoFailed,
    },
    null => draft.scopeChanged ? l10n.importScopeChanged : null,
    _ => l10n.photoFailed,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final draft = ref.watch(importSessionProvider(widget.serviceType));
    final key = _session.draftKey;
    if (_shownDraft != null && !identical(_shownDraft, key)) {
      _paste = false;
      _applying = false;
      _lastPlan = null;
      // The old field is removed in this frame; do not notify it mid-build.
      final old = _json;
      _json = TextEditingController();
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _shownDraft = key;
    final plan = ref.watch(importPlanProvider(widget.serviceType));
    _ready =
        ref.watch(rosterEditingProvider(widget.serviceType)) &&
        ref.watch(churchOpenProvider) &&
        arrangesAny(ref.watch(arrangesProvider(widget.serviceType)));
    if (_ready && plan != null) _lastPlan = plan;
    if (!draft.loaded) _lastPlan = null;
    final shown = _ready ? plan : _lastPlan;
    return Scaffold(
      appBar: AppBar(
        title: Text(shown == null ? l10n.photoImport : l10n.importPreview),
        actions: [
          if (shown != null)
            IconButton(
              tooltip: l10n.importJsonEdit,
              onPressed: _ready && !_busy ? _editJson : null,
              icon: const Icon(Symbols.code_rounded),
            ),
        ],
      ),
      body: shown != null ? _preview(shown, draft, l10n) : _start(draft, l10n, c),
    );
  }

  Widget _start(ImportDraft draft, L10n l10n, AppColors c) {
    final quota = ref.watch(_quotaProvider).value;
    final blocked = !_ready || (quota != null && (!quota.platformOpen || quota.remaining <= 0));
    return ListView(
      padding: const EdgeInsets.all(Space.m),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: BalancedText(
            quota == null
                ? ' '
                : !quota.platformOpen
                ? l10n.photoPlatformOff
                : quota.remaining <= 0
                ? l10n.photoChurchLimit(quota.limit)
                : l10n.photoRemaining(quota.remaining),
            textAlign: TextAlign.start,
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
                BalancedText(
                  l10n.photoRecognizing,
                  textAlign: TextAlign.start,
                  style: AppText.body.copyWith(color: c.secondaryLabel),
                ),
              ],
            ),
          )
        else ...[
          PrimaryButton(
            label: l10n.photoTake,
            icon: const Icon(Symbols.photo_camera_rounded),
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
                label: l10n.importCopyPrompt,
                expand: true,
                onPressed: _ready ? _copyPrompt : null,
              ),
              SecondaryButton(
                label: l10n.photoPasteJson,
                expand: true,
                onPressed: _ready ? () => setState(() => _paste = !_paste) : null,
              ),
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: SelectableText(
                  // The JSON protocol's field names are never translated;
                  // its example values are.
                  '[{"date":"2026-10-18","duties":[{"role":${jsonEncode(l10n.importExampleRole)},'
                  '"people":[${jsonEncode(l10n.importExamplePerson)}]}],'
                  '"events":[{"name":${jsonEncode(l10n.importExampleEvent)},"color":0}]}]\n'
                  '${l10n.importFormatHelp}',
                  style: AppText.footnote,
                ),
              ),
            ],
          ),
        ],
        if (_errorText(draft, l10n) case final error?)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: BalancedText(
              error,
              textAlign: TextAlign.start,
              style: AppText.subheadline.copyWith(color: c.destructive),
            ),
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
                        : (duty['people'] as List<dynamic>).join(l10n.listSeparator)
                  : l10n.importPeopleArrayHint,
              onTap: enabled ? () => _editDuty(index, row, i) : null,
            ),
        ListRow(
          title: l10n.addDuty,
          leading: const Icon(Symbols.add_rounded),
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
          leading: const Icon(Symbols.add_rounded),
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
            title: l10n.importRemoveDuty(
              duty.role,
              duty.people.isEmpty ? l10n.nobodyYet : duty.people.join(l10n.listSeparator),
            ),
          ),
        );
      }
    }
    for (final duty in after.duties) {
      final old = before?.duties.where((d) => d.role == duty.role).firstOrNull;
      if (old == duty) continue;
      final names = duty.people.isEmpty ? l10n.nobodyYet : duty.people.join(l10n.listSeparator);
      rows.add(
        ListRow(
          title: old == null
              ? l10n.importAddDuty(duty.role, names)
              : l10n.importChangeDuty(
                  duty.role,
                  old.people.isEmpty ? l10n.nobodyYet : old.people.join(l10n.listSeparator),
                  names,
                ),
          subtitle: [
            for (final name in duty.people)
              duty.uids.containsKey(name) ? l10n.importMemberIdentity(name) : l10n.importGuestIdentity(name),
          ].join(l10n.listSeparator),
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

  String _nameStatus(String raw, ImportDraft draft, ImportReport report, L10n l10n) {
    if (report.unresolved.containsKey(raw)) {
      final candidates = report.unresolved[raw]!;
      return candidates.isEmpty
          ? l10n.importNoCandidate
          : l10n.importCandidates(candidates.map((m) => m.name).join(l10n.listSeparator));
    }
    final choice = draft.people[raw];
    if (choice != null && choice.uid == null) return l10n.importGuestUnlinked;
    final member = _session
        .candidates(raw)
        .where((m) => choice == null ? m.name.trim() == raw : m.uid == choice.uid)
        .firstOrNull;
    return member == null ? l10n.importNameNeedsConfirm : l10n.importLinkedMember(member.name);
  }

  Widget _preview(ImportPlan plan, ImportDraft draft, L10n l10n) {
    final report = plan.report;
    final admin = ref.watch(meProvider).value?.isAdmin ?? false;
    final repairable = _ready && !_busy && admin;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              if (draft.rows.isEmpty) EmptyState(message: l10n.importNothing),
              ListSection(
                header: l10n.importMode,
                children: [
                  ListRow(
                    title: l10n.importMerge,
                    selected: draft.mode == ImportMode.merge,
                    onTap: _ready && !_busy ? () => _session.setMode(ImportMode.merge) : null,
                  ),
                  // Not for a 事工's 負責人: the rest of the day is not theirs.
                  if (_session.only == null)
                    ListRow(
                      title: l10n.importReplace,
                      selected: draft.mode == ImportMode.replace,
                      subtitle: l10n.importReplaceHelp,
                      onTap: _ready && !_busy ? () => _session.setMode(ImportMode.replace) : null,
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
              if (draft.names.isNotEmpty)
                ListSection(
                  header: report.unresolved.isEmpty ? l10n.importNameLinks : l10n.importNamesNeedConfirm,
                  children: [
                    for (final name in {...report.unresolved.keys, ...draft.names})
                      ListRow(
                        title: name,
                        subtitle: _nameStatus(name, draft, report, l10n),
                        onTap: _ready && !_busy ? () => _resolveName(name, _session.candidates(name)) : null,
                      ),
                  ],
                ),
              // Who was scheduled for a duty they are not on the list for
              // is put on it when applied (admins), not asked about here.
              if (report.unknownDuties.isNotEmpty || report.unknownEvents.isNotEmpty)
                ListSection(
                  header: admin ? l10n.importRepairSettings : l10n.importNoSettingsChange,
                  children: [
                    for (final role in report.unknownDuties)
                      ListRow(
                        title: admin ? l10n.importAddConfiguredDuty(role) : l10n.importUnconfiguredDuty(role),
                        onTap: repairable ? () => _repair(() => _session.addDuty(role)) : null,
                      ),
                    for (final event in report.unknownEvents)
                      ListRow(
                        title: admin ? l10n.importAddCommonEvent(event.name) : l10n.importNotCommonEvent(event.name),
                        onTap: repairable ? () => _repair(() => _session.addCommonEvent(event)) : null,
                      ),
                  ],
                ),
              if (report.pastDays.isNotEmpty)
                ListSection(
                  header: l10n.importPastDays,
                  children: [for (final day in report.pastDays) ListRow(title: day)],
                ),
              for (final (i, row) in draft.rows.indexed)
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
              onPressed: _ready && plan.canApply ? () => _apply(plan) : null,
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
                    // The keyboard goes, not left over the colours.
                    onTap: () => FocusScope.of(context).unfocus(),
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
    // The protocol's field names are never translated; the example value is.
    ImportIssueCode.eventObject => l10n.importIssueEventObject(
      index(),
      '{"name":${jsonEncode(l10n.eventName)},"color":0}',
    ),
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
