import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/roster_import.dart';
import '../../domain/staff_order.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import 'format.dart';

final _quotaProvider = FutureProvider.autoDispose<PhotoQuota>((ref) {
  final cid = ref.watch(currentChurchIdProvider)!;
  return ref.watch(backendProvider).cloud.photoQuota(cid);
});

/// 照片匯入: photograph a paper roster, check what was read, apply it.
/// Pasting JSON is the way in when the monthly photos are used up.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.serviceType});

  final String serviceType;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _busy = false;
  String? _error;
  ImportPlan? _plan;
  bool _paste = false;
  final _json = TextEditingController();

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _photos(ImageSource source) async {
    final l10n = L10n.of(context);
    final picker = ImagePicker();
    final files = source == ImageSource.camera
        ? [?await picker.pickImage(source: source, maxWidth: 2400, imageQuality: 85)]
        : await picker.pickMultiImage(maxWidth: 2400, imageQuality: 85, limit: 3);
    if (files.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final images = [
        for (final f in files.take(3)) PhotoInput(mimeType: f.mimeType ?? 'image/jpeg', bytes: await f.readAsBytes()),
      ];
      final rows = await ref
          .read(backendProvider)
          .cloud
          .recognizeRoster(ref.read(currentChurchIdProvider)!, widget.serviceType, images);
      ref.invalidate(_quotaProvider);
      _makePlan(rows);
    } on CloudException catch (e) {
      setState(
        () => _error = switch ((e.code, e.detail)) {
          (CloudErrorCode.quotaExceeded, 'platform') => l10n.photoPlatformOff,
          (CloudErrorCode.quotaExceeded, _) => l10n.photoChurchLimit(30),
          (_, 'tooLarge') => l10n.photoTooLarge,
          _ => l10n.photoFailed,
        },
      );
    } catch (_) {
      setState(() => _error = l10n.photoFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _makePlan(List<dynamic> rows) {
    final service = ref.read(servicesProvider).value!.byId(widget.serviceType)!;
    setState(() {
      _plan = planImport(
        rows: rows,
        service: service,
        members: ref.read(membersProvider).value ?? const [],
        saved: ref.read(savedRostersProvider).value ?? const [],
        order: ref.read(staffOrderProvider(widget.serviceType)).value ?? StaffOrder(),
        today: ref.read(todayProvider),
      );
    });
  }

  void _parsePasted() {
    try {
      final rows = jsonDecode(_json.text);
      if (rows is! List) throw const FormatException();
      _makePlan(rows);
    } on FormatException {
      setState(() => _error = L10n.of(context).importBadRows);
    }
  }

  Future<void> _apply(ImportPlan plan) async {
    final l10n = L10n.of(context);
    final data = ref.read(churchDataProvider)!;
    final before = ref.read(staffOrderProvider(widget.serviceType)).value ?? StaffOrder();
    setState(() => _busy = true);
    try {
      await data.saveRosters(plan.rosters);
      final changes = before.changesTo(plan.order);
      if (changes.isNotEmpty) await data.updateStaffOrder(widget.serviceType, changes);
      Haptics.success();
      if (!mounted) return;
      showToast(context, l10n.importApplied(plan.rosters.length));
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) showToast(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    ref.watch(membersProvider);
    ref.watch(staffOrderProvider(widget.serviceType));
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: Text(plan == null ? l10n.photoImport : l10n.importPreview)),
      body: plan != null ? _preview(plan, l10n, c) : _start(l10n, c),
    );
  }

  Widget _start(L10n l10n, AppColors c) {
    final quota = ref.watch(_quotaProvider).value;
    final blocked = quota != null && (!quota.platformOpen || quota.remaining <= 0);
    return ListView(
      padding: const EdgeInsets.all(Space.m),
      children: [
        if (quota != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Text(
              !quota.platformOpen
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
          SecondaryButton(
            label: l10n.photoPasteJson,
            expand: true,
            onPressed: () => setState(() => _paste = !_paste),
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
          SecondaryButton(label: l10n.next2, expand: true, onPressed: _parsePasted),
        ],
      ],
    );
  }

  Widget _preview(ImportPlan plan, L10n l10n, AppColors c) {
    final today = ref.read(todayProvider);
    final r = plan.report;
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xl),
      children: [
        if (plan.rosters.isEmpty) EmptyState(message: l10n.importNothing),
        if (r.notInList.isNotEmpty)
          ListSection(
            header: l10n.importNotInList,
            children: [
              for (final e in r.notInList.entries)
                ListRow(title: e.key, subtitle: e.value.isEmpty ? null : l10n.importNear(e.value.join('、'))),
            ],
          ),
        if (r.ambiguous.isNotEmpty)
          ListSection(
            header: l10n.importAmbiguous,
            children: [for (final n in r.ambiguous) ListRow(title: n)],
          ),
        if (r.unknownDuties.isNotEmpty)
          ListSection(
            header: l10n.importUnknownDuties,
            children: [for (final n in r.unknownDuties) ListRow(title: n)],
          ),
        if (r.pastDays.isNotEmpty)
          ListSection(
            header: l10n.importPastDays,
            children: [for (final d in r.pastDays) ListRow(title: d)],
          ),
        if (r.badRows.isNotEmpty)
          ListSection(
            header: l10n.importBadRows,
            children: [ListRow(title: r.badRows.join('、'))],
          ),
        for (final roster in plan.rosters)
          ListSection(
            header: dayLabel(l10n, roster.day, today),
            children: [
              for (final d in roster.duties)
                ListRow(
                  title: d.role,
                  value: d.people.isEmpty ? l10n.nobodyYet : d.people.join('、'),
                ),
            ],
          ),
        if (plan.rosters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: PrimaryButton(label: l10n.importApply, busy: _busy, onPressed: () => _apply(plan)),
          ),
      ],
    );
  }
}
