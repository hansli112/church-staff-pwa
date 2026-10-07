import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import 'welcome_screen.dart' show VerifyEmailBanner;

/// Picks the move file; null when cancelled. Overridden in tests.
final moveFilePickerProvider = Provider<Future<List<int>?> Function()>(
  (ref) => () async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['json']);
    return file?.xFile.readAsBytes();
  },
);

/// 從舊版搬過來: upload the move file made in the self-host version's Cloud
/// Shell, check the preview, then create the church with everything in it.
/// The uploader becomes its admin, whatever account they signed in with.
class MoveScreen extends ConsumerStatefulWidget {
  const MoveScreen({super.key});

  @override
  ConsumerState<MoveScreen> createState() => _MoveScreenState();
}

class _MoveScreenState extends ConsumerState<MoveScreen> {
  final _name = TextEditingController();
  String? _path;
  MovePreview? _preview;
  String? _me;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final l10n = L10n.of(context);
    final bytes = await ref.read(moveFilePickerProvider)();
    if (bytes == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cloud = ref.read(backendProvider).cloud;
      final path = await cloud.uploadMoveFile(bytes);
      final preview = await cloud.movePreview(path);
      final email = ref.read(authUserProvider).value?.email.trim().toLowerCase();
      setState(() {
        _path = path;
        _preview = preview;
        // Most often the uploader is in the file under the same email.
        _me = preview.people.where((p) => p.email.trim().toLowerCase() == email).firstOrNull?.id;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final l10n = L10n.of(context);
    final name = _name.text.trim();
    if (name.isEmpty || _path == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cid = await ref.read(backendProvider).cloud.moveCommit(_path!, churchName: name, me: _me);
      ref.read(selectedChurchProvider.notifier).select(cid);
      Haptics.success();
      if (!mounted) return;
      showToast(context, l10n.moveDone(name));
      context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final verified = ref.watch(authUserProvider.select((u) => u.value?.verified ?? false));
    final preview = _preview;
    final error = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Text(_error!, style: AppText.subheadline.copyWith(color: c.destructive)),
          );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moveFromSelfHost)),
      body: ListView(
        children: [
          if (preview == null) ...[
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const VerifyEmailBanner(),
                  Text(l10n.moveIntro, style: AppText.body.copyWith(color: c.secondaryLabel)),
                  const SizedBox(height: Space.l),
                  PrimaryButton(label: l10n.movePickFile, busy: _busy, onPressed: verified ? _pick : null),
                ],
              ),
            ),
            ?error,
          ] else ...[
            ListSection(
              header: l10n.moveContents,
              children: [
                ListRow(title: l10n.moveMembers, value: l10n.moveMembersCount(preview.members)),
                ListRow(title: l10n.moveRosters, value: l10n.moveRostersCount(preview.rosters)),
                ListRow(title: l10n.moveServices, subtitle: preview.services.join('、')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: TextField(
                controller: _name,
                maxLength: TextLimits.churchName,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: l10n.churchName, counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
            ),
            ListSection(
              header: l10n.moveWhoAmI,
              footer: l10n.moveWhoAmIFooter,
              children: [
                for (final p in preview.people)
                  ListRow(
                    title: p.name.isEmpty ? p.email : p.name,
                    subtitle: p.name.isEmpty || p.email.isEmpty ? null : p.email,
                    selected: _me == p.id,
                    onTap: () => setState(() => _me = _me == p.id ? null : p.id),
                  ),
              ],
            ),
            ?error,
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: PrimaryButton(
                label: l10n.moveCreate,
                busy: _busy,
                onPressed: _name.text.trim().isEmpty ? null : _commit,
              ),
            ),
          ],
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}
