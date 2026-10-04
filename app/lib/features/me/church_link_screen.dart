import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';

/// Admins set the church link shown at the top of everyone's home page.
class ChurchLinkScreen extends ConsumerStatefulWidget {
  const ChurchLinkScreen({super.key});

  @override
  ConsumerState<ChurchLinkScreen> createState() => _ChurchLinkScreenState();
}

class _ChurchLinkScreenState extends ConsumerState<ChurchLinkScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _url = TextEditingController();
  bool _filled = false;
  bool _tried = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _url.dispose();
    super.dispose();
  }

  /// Fills the fields once, from the saved link.
  void _fill(ChurchLink? link) {
    if (_filled) return;
    _filled = true;
    _title.text = link?.title ?? '';
    _body.text = link?.body ?? '';
    _url.text = link?.url ?? 'https://';
  }

  String? get _titleError => _title.text.trim().isEmpty ? L10n.of(context).churchLinkNeedsTitle : null;
  String? get _urlError => ChurchLink.validUrl(_url.text) ? null : L10n.of(context).churchLinkNeedsHttps;

  Future<void> _save() async {
    final l10n = L10n.of(context);
    setState(() => _tried = true);
    if (_titleError != null || _urlError != null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(churchDataProvider)!
          .saveChurchLink(ChurchLink(title: _title.text.trim(), body: _body.text.trim(), url: _url.text.trim()));
      Haptics.success();
      if (!mounted) return;
      showToast(context, l10n.saved);
      context.pop();
    } catch (_) {
      if (mounted) showToast(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ChurchLink link) async {
    final l10n = L10n.of(context);
    final data = ref.read(churchDataProvider)!;
    try {
      await data.saveChurchLink(null);
    } catch (_) {
      if (mounted) showToast(context, l10n.saveFailed);
      return;
    }
    if (!mounted) return;
    showToast(context, l10n.churchLinkRemoved, onUndo: () => data.saveChurchLink(link));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final saved = ref.watch(churchLinkProvider);
    if (!saved.hasValue) return Scaffold(appBar: AppBar(title: Text(l10n.churchLink)));
    final link = saved.value;
    _fill(link);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.churchLink)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          TextField(
            controller: _title,
            maxLength: ChurchLink.titleMax,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: l10n.churchLinkTitle, errorText: _tried ? _titleError : null),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s),
          TextField(
            controller: _body,
            maxLength: ChurchLink.bodyMax,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: l10n.churchLinkBody),
          ),
          const SizedBox(height: Space.s),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l10n.churchLinkUrl, errorText: _tried ? _urlError : null),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.s),
          Text(
            l10n.churchLinkFooter,
            style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
          ),
          const SizedBox(height: Space.l),
          PrimaryButton(label: l10n.save, busy: _busy, onPressed: _save),
          if (link != null) ...[
            const SizedBox(height: Space.l),
            ListSection(
              children: [ListRow(title: l10n.churchLinkRemove, destructive: true, onTap: () => _remove(link))],
            ),
          ],
        ],
      ),
    );
  }
}
