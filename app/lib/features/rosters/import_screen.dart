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
import '../../domain/staff.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_update.dart';
import '../../state/import_session.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../../state/session.dart';
import '../common/errors.dart';
import 'format.dart';

final _quotaProvider = FutureProvider.autoDispose<PhotoQuota>((ref) => openChurch(ref).photos.quota());

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
  bool _applying = false;
  bool _advanced = false;
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

  /// Whether [me] may add a 同工 to the service, as 新增同工 does.
  bool _addsStaff(Member? me) => me?.addsStaffTo(ServiceGroup(widget.serviceType)) ?? false;

  Future<void> _resolveName(String raw) => _during(() => _confirmName(raw));

  /// Asks who [raw] is, as picking someone for a duty does: someone in the
  /// church, a 同工 to add by that name or one typed, or arranged this once.
  Future<void> _confirmName(String raw) async {
    final key = _session.draftKey;
    final who = await showAppSheet<_Who>(
      context,
      expand: true,
      builder: (_) => _WhoSheet(
        name: raw,
        suggested: _session.candidates(raw),
        staff: ref.read(staffProvider).value ?? Staff.empty,
        addsStaff: _addsStaff(ref.read(meProvider).value),
      ),
    );
    if (who == null || !_ready || _busy || !(mounted && _sameDraft(key))) return;
    switch (who) {
      case _Member(:final uid):
        _session.choose(raw, ImportPersonChoice.member(uid));
      case _Once(:final name):
        if (name != raw) _session.rename(raw, name);
        _session.choose(name, const ImportPersonChoice.guest());
      case _Staff(:final name):
        if (!await _addStaff([name], key)) return;
        if (name != raw && mounted && _sameDraft(key)) _session.rename(raw, name);
    }
  }

  /// Adds [names] as 同工 without an account, in turn; one refused says
  /// so, and stops there. Whether all were added.
  Future<bool> _addStaff(List<String> names, Object key) async {
    final l10n = L10n.of(context);
    for (final name in names) {
      try {
        await _session.addStaff(name);
      } catch (e) {
        if (mounted && _sameDraft(key)) showToast(context, nameErrorText(l10n, e, name));
        return false;
      }
      if (!(mounted && _sameDraft(key))) return false;
    }
    return true;
  }

  Future<void> _addAllStaff(List<String> names) => _during(() async {
    if (!_ready || _busy) return;
    final key = _session.draftKey;
    if (await _addStaff(names, key) && mounted && _sameDraft(key)) Haptics.success();
  });

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
    _session.setDate(index, Day(picked.year, picked.month, picked.day));
  }

  Future<void> _editDuty(int index, Map<dynamic, dynamic> row, int? dutyIndex) async {
    final duty = dutyIndex == null ? const <String, dynamic>{} : (row['duties'] as List<dynamic>)[dutyIndex];
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
      _session.removeDuty(index, dutyIndex!);
    } else {
      _session.putDuty(index, dutyIndex, role: result.values[0], people: result.values[1].split('\n'));
    }
  }

  Future<void> _editEvent(int index, Map<dynamic, dynamic> row, int? eventIndex) async {
    final event = eventIndex == null ? const <String, dynamic>{} : (row['events'] as List<dynamic>)[eventIndex];
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
      _session.removeEvent(index, eventIndex!);
    } else {
      _session.putEvent(index, eventIndex, name: result.values.single, color: result.color ?? 0);
    }
  }

  /// Admins: changes the service's settings so the import fits them.
  Future<void> _repair(Future<void> Function() write) => _during(() async {
    if (!_ready || _busy || ref.read(meProvider).value?.editsServiceSettings != true) return;
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
      if (ref.read(meProvider).value?.editsServiceSettings ?? false) {
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
      final prompt = await ref.churchData.photos.prompt(widget.serviceType);
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
        ref.watch(arrangesProvider(widget.serviceType)).any;
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
        BalancedText(l10n.photoIntro, textAlign: TextAlign.start, style: AppText.body),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs, bottom: Space.m),
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
          const SizedBox(height: Space.l),
          // 進階 and what it opens, one card: the row its header.
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.m),
            child: Material(
              color: c.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListRow(
                    title: l10n.importAdvanced,
                    trailing: AnimatedRotation(
                      turns: _advanced ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Symbols.expand_more_rounded, color: c.tertiaryLabel),
                    ),
                    onTap: () => setState(() => _advanced = !_advanced),
                  ),
                  if (_advanced) ...[
                    Divider(height: 0.5, thickness: 0.5, indent: Space.m, color: c.separator),
                    Padding(
                      padding: const EdgeInsets.all(Space.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SecondaryButton(
                            label: l10n.importCopyPrompt,
                            expand: true,
                            onPressed: _ready ? _copyPrompt : null,
                          ),
                          const SizedBox(height: Space.s),
                          // The reply pasted straight in: no button to open a field.
                          TextField(
                            controller: _json,
                            maxLines: 6,
                            style: AppText.footnote.copyWith(fontFamily: 'monospace'),
                            decoration: InputDecoration(hintText: l10n.jsonHint),
                            onChanged: (_) => setState(() {}),
                          ),
                          if (_json.text.trim().isNotEmpty) ...[
                            const SizedBox(height: Space.s),
                            SecondaryButton(
                              label: l10n.next2,
                              expand: true,
                              onPressed: _ready && !_busy ? _parsePasted : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
      ],
    );
  }

  /// What is wrong with a day as a whole ([text]): fixed in its JSON.
  Widget _jsonFixRow(String text, L10n l10n) => ListRow(
    title: l10n.importJsonEdit,
    subtitle: text,
    subtitleAlert: true,
    onTap: _ready && !_busy ? _editJson : null,
  );

  /// One imported day, what is wrong with it ([issues]) said where it is:
  /// tapped, it is fixed there.
  Widget _inputRow(int index, Map<dynamic, dynamic> row, List<ImportIssue> issues, L10n l10n) {
    final rawDate = row['date'];
    final day = rawDate is String ? Day.tryParse(rawDate) : null;
    final duties = row['duties'];
    final events = row['events'];
    final enabled = _ready && !_busy;
    String? wrong(String place) {
      final texts = [
        for (final issue in issues)
          if (_placeOf(issue) == place) importIssueText(l10n, issue),
      ];
      return texts.isEmpty ? null : texts.join('\n');
    }

    final dateIssue = issues.where((i) => _placeOf(i) == 'date').firstOrNull;
    return ListSection(
      header: day == null ? l10n.importNoDay : dayLabel(l10n, day, ref.read(todayProvider)),
      children: [
        if (wrong('row') case final text?) _jsonFixRow(text, l10n),
        ListRow(
          title: l10n.importDateLabel,
          subtitle: switch (dateIssue?.code) {
            ImportIssueCode.date => l10n.importDateMissing,
            ImportIssueCode.duplicateDate => l10n.importIssueDuplicateDate,
            _ => rawDate is String ? rawDate : l10n.importDateMissing,
          },
          subtitleAlert: dateIssue != null,
          onTap: enabled ? () => _editDate(index, row) : null,
        ),
        if (duties is List)
          for (final (i, duty) in duties.indexed)
            ListRow(
              title: duty is Map && duty['role'] is String ? duty['role'] as String : l10n.importFixDuty,
              subtitle:
                  wrong('duty/${i + 1}') ??
                  (duty is Map && duty['people'] is List
                      ? (duty['people'] as List<dynamic>).isEmpty
                            ? l10n.nobodyYet
                            : (duty['people'] as List<dynamic>).join(l10n.listSeparator)
                      : l10n.importPeopleArrayHint),
              subtitleAlert: wrong('duty/${i + 1}') != null,
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
              // Only ever what is wrong with it.
              subtitle: wrong('event/${i + 1}'),
              subtitleAlert: true,
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

  Widget _preview(ImportPlan plan, ImportDraft draft, L10n l10n) {
    final report = plan.report;
    final editsSettings = ref.watch(meProvider).value?.editsServiceSettings ?? false;
    final repairable = _ready && !_busy && editsSettings;
    // Names on the sheet nobody in the church has, nor could be: added at
    // once, the first time a church's rosters come in.
    final staff = ref.watch(staffProvider).value ?? Staff.empty;
    final newStaff = _addsStaff(ref.watch(meProvider).value)
        ? [
            for (final MapEntry(key: name, value: candidates) in report.unresolved.entries)
              if (candidates.isEmpty && !staff.hasName(name)) name,
          ]
        : const <String>[];
    final toFix = {
      for (final MapEntry(key: row, value: issues) in report.errors.entries)
        for (final issue in issues) (row, _placeOf(issue)),
    }.length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              if (draft.rows.isEmpty) EmptyState(message: l10n.importNothing),
              // Only those still to confirm: a name confirmed, or matched
              // by itself, leaves the list.
              if (report.unresolved.isNotEmpty)
                ListSection(
                  header: l10n.importNamesNeedConfirm,
                  children: [
                    if (newStaff.length > 1)
                      ListRow(
                        title: l10n.importAddAllStaff,
                        subtitle: newStaff.join(l10n.listSeparator),
                        leading: const Icon(Symbols.group_add_rounded),
                        tinted: true,
                        onTap: _ready && !_busy ? () => _addAllStaff(newStaff) : null,
                      ),
                    for (final MapEntry(key: name, value: candidates) in report.unresolved.entries)
                      ListRow(
                        title: name,
                        subtitle: candidates.isEmpty
                            ? l10n.importNoCandidate
                            : l10n.importCandidates(candidates.map((m) => m.name).join(l10n.listSeparator)),
                        onTap: _ready && !_busy ? () => _resolveName(name) : null,
                      ),
                  ],
                ),
              // Who was scheduled for a duty they are not on the list for
              // is put on it when applied (admins), not asked about here.
              if (report.unknownDuties.isNotEmpty || report.unknownEvents.isNotEmpty)
                ListSection(
                  header: editsSettings ? l10n.importRepairSettings : l10n.importNoSettingsChange,
                  children: [
                    for (final role in report.unknownDuties)
                      ListRow(
                        title: editsSettings ? l10n.importAddConfiguredDuty(role) : l10n.importUnconfiguredDuty(role),
                        onTap: repairable ? () => _repair(() => _session.addDuty(role)) : null,
                      ),
                    for (final event in report.unknownEvents)
                      ListRow(
                        title: editsSettings
                            ? l10n.importAddCommonEvent(event.name)
                            : l10n.importNotCommonEvent(event.name),
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
                if (row is Map)
                  _inputRow(i, row, report.errors[i + 1] ?? const [], l10n)
                else
                  ListSection(
                    header: l10n.importRow(i + 1),
                    children: [
                      _jsonFixRow(
                        [
                          for (final issue in report.errors[i + 1] ?? const <ImportIssue>[])
                            importIssueText(l10n, issue),
                        ].join('\n'),
                        l10n,
                      ),
                    ],
                  ),
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
              // Waiting on something: says so, not only greyed out.
              label: toFix > 0
                  ? l10n.importFixFirst(toFix)
                  : report.unresolved.isNotEmpty
                  ? l10n.importConfirmNamesFirst(report.unresolved.length)
                  : l10n.importApply,
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
    return UnsavedChanges(
      changed: () =>
          _color != widget.color ||
          [for (final (i, f) in widget.fields.indexed) _controllers[i].text != f.initial].any((c) => c),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetBar(
                  title: widget.title,
                  actions: [
                    SecondaryButton(
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
                  ],
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: Space.m),
                    children: [
                      for (final (i, field) in widget.fields.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.m),
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
                          padding: const EdgeInsets.only(bottom: Space.m),
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
              ],
            ),
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

/// Where on its day [issue] is said: its date, its n-th duty or event
/// (one-based, as the issue counts them), or the day as a whole.
String _placeOf(ImportIssue issue) => switch (issue.code) {
  ImportIssueCode.date || ImportIssueCode.duplicateDate => 'date',
  ImportIssueCode.dutyFields ||
  ImportIssueCode.role ||
  ImportIssueCode.peopleArray ||
  ImportIssueCode.duplicatePeople => 'duty/${issue.args['index']}',
  ImportIssueCode.eventObject ||
  ImportIssueCode.eventName ||
  ImportIssueCode.eventColor => 'event/${issue.args['index']}',
  ImportIssueCode.rowObject ||
  ImportIssueCode.rowFields ||
  ImportIssueCode.dutiesArray ||
  ImportIssueCode.eventsArray => 'row',
};

/// Who an imported name is, as [_WhoSheet] closes.
sealed class _Who {
  const _Who();
}

/// Someone in the church.
class _Member extends _Who {
  const _Member(this.uid);
  final String uid;
}

/// [name] arranged this once (臨時排), without an account.
class _Once extends _Who {
  const _Once(this.name);
  final String name;
}

/// [name] made one of the service's 同工 without an account (新增同工).
class _Staff extends _Who {
  const _Staff(this.name);
  final String name;
}

/// Who an imported [name] is, picked as someone is for a duty: those it
/// may be first, then everyone; a search over the church; a name nobody
/// has added as a 同工, or arranged this once, as on the sheet or typed.
class _WhoSheet extends StatefulWidget {
  const _WhoSheet({required this.name, required this.suggested, required this.staff, required this.addsStaff});
  final String name;
  final List<Member> suggested;
  final Staff staff;

  /// May add a 同工 to the service (Member.addsStaffTo).
  final bool addsStaff;

  @override
  State<_WhoSheet> createState() => _WhoSheetState();
}

class _WhoSheetState extends State<_WhoSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final typed = _query.trim();
    final name = typed.isEmpty ? widget.name : typed;
    final suggested = {for (final m in widget.suggested) m.uid};
    int byName(Member a, Member b) => a.name.compareTo(b.name);
    final others = [
      for (final m in widget.staff.all)
        if (!suggested.contains(m.uid)) m,
    ]..sort(byName);
    final found = [...widget.staff.search(_query)]..sort(byName);
    // Nobody in the church by that name, however written: adding would
    // refuse it.
    final nameIsFree = !widget.staff.hasName(name);
    Widget member(Member m, {bool email = false}) => ListRow(
      title: m.name,
      subtitle: email && m.email.isNotEmpty ? m.email : null,
      chevron: false,
      onTap: () => Navigator.pop(context, _Member(m.uid)),
    );
    return Column(
      children: [
        SheetBar(title: l10n.importWhoIs(widget.name), actions: const []),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: SearchField(hint: l10n.pickerSearchHint, onChanged: (v) => setState(() => _query = v)),
        ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.viewInsetsOf(context).bottom),
            children: [
              if (typed.isNotEmpty)
                for (final m in found) member(m)
              else ...[
                if (widget.suggested.isNotEmpty) ...[
                  SectionHeader(l10n.pickerServes),
                  for (final m in widget.suggested) member(m, email: true),
                ],
                if (others.isNotEmpty) ...[
                  SectionHeader(widget.suggested.isEmpty ? l10n.pickerEveryone : l10n.pickerOthers),
                  for (final m in others) member(m),
                ],
              ],
              const SizedBox(height: Space.l),
              if (widget.addsStaff && nameIsFree)
                ListRow(
                  title: l10n.pickerAddStaff(name),
                  subtitle: l10n.pickerAddStaffDetail,
                  leading: const Icon(Symbols.person_add_rounded),
                  // Done at once: nothing further to open.
                  chevron: false,
                  onTap: () => Navigator.pop(context, _Staff(name)),
                ),
              // A typed name someone has is them, listed above: not for
              // the whole sheet's 「X」 to lose its link to them.
              if (typed.isEmpty || nameIsFree)
                ListRow(
                  title: l10n.pickerOnce(name),
                  leading: const Icon(Symbols.add_rounded),
                  chevron: false,
                  onTap: () => Navigator.pop(context, _Once(name)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
