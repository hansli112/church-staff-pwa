import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/church_link.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';

/// Admins set the church link shown at the top of everyone's home page,
/// and optionally a content source fetched once a day at a time they pick.
class ChurchLinkScreen extends ConsumerStatefulWidget {
  const ChurchLinkScreen({super.key});

  @override
  ConsumerState<ChurchLinkScreen> createState() => _ChurchLinkScreenState();
}

class _ChurchLinkScreenState extends ConsumerState<ChurchLinkScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _url = TextEditingController();
  final _source = TextEditingController();
  int _fetchMinute = ChurchLink.defaultFetchMinute;
  String? _sourceProblem;
  bool _filled = false;
  bool _tried = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _url.dispose();
    _source.dispose();
    super.dispose();
  }

  /// Fills the fields once, from the saved link.
  void _fill(ChurchLink? link) {
    if (_filled) return;
    _filled = true;
    _title.text = link?.title ?? '';
    _body.text = link?.body ?? '';
    _url.text = link?.url ?? 'https://';
    _source.text = link?.source ?? '';
    _fetchMinute = link?.fetchMinute ?? ChurchLink.defaultFetchMinute;
  }

  String? get _titleError => _title.text.trim().isEmpty ? L10n.of(context).churchLinkNeedsTitle : null;
  String? get _urlError => ChurchLink.validUrl(_url.text) ? null : L10n.of(context).churchLinkNeedsHttps;
  String? get _sourceError {
    final s = _source.text.trim();
    return s.isEmpty || ChurchLink.validUrl(s) ? null : L10n.of(context).churchLinkNeedsHttps;
  }

  Future<void> _save(ChurchLink? saved) async {
    final l10n = L10n.of(context);
    setState(() {
      _tried = true;
      _sourceProblem = null;
    });
    if (_titleError != null || _urlError != null || _sourceError != null) return;
    setState(() => _busy = true);
    final source = _source.text.trim();
    final sourceChanged = source != (saved?.source ?? '') || (source.isNotEmpty && _fetchMinute != saved?.fetchMinute);
    try {
      await ref
          .read(churchDataProvider)!
          .saveChurchLink(ChurchLink(title: _title.text.trim(), body: _body.text.trim(), url: _url.text.trim()));
      LinkSourceResult? result;
      if (sourceChanged) {
        result = await ref.read(churchDataProvider)!.setLinkSource(source.isEmpty ? null : source, _fetchMinute);
      }
      if (!mounted) return;
      if (result != null && !result.ok) {
        // Saved, but the source did not give anything: stay and say why.
        showToast(context, l10n.saved);
        setState(() => _sourceProblem = linkErrorText(l10n, result!.error!, result.status));
        return;
      }
      Haptics.success();
      final fetched = result?.content?.title;
      showToast(context, fetched == null ? l10n.saved : l10n.linkSourceFetched(fetched));
      context.pop();
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
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

  Future<void> _pickTime() async {
    final picked = await showAppSheet<int>(context, builder: (context) => _TimeSheet(selected: _fetchMinute));
    if (picked != null) setState(() => _fetchMinute = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final saved = ref.watch(churchLinkProvider);
    if (!saved.hasValue) return Scaffold(appBar: AppBar(title: Text(l10n.churchLink)));
    final link = saved.value;
    _fill(link);
    final content = ref.watch(linkContentProvider).value;
    final c = AppColors.of(context);
    final status = _sourceProblem != null
        ? l10n.linkSourceFailed(_sourceProblem!)
        : link?.source == null || content == null || content.source != link!.source
        ? null
        : content.error != null
        ? l10n.linkSourceFailed(linkErrorText(l10n, content.error!, content.errorStatus))
        : content.fetchedAt == null
        ? null
        : l10n.linkSourceUpdated(DateFormat('M/d HH:mm').format(content.fetchedAt!));
    final fieldPadding = const EdgeInsets.symmetric(horizontal: Space.m);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.churchLink)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.m),
        children: [
          Padding(
            padding: fieldPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _title,
                  maxLength: TextLimits.linkTitle,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.churchLinkTitle, errorText: _tried ? _titleError : null),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Space.s),
                TextField(
                  controller: _body,
                  maxLength: TextLimits.linkBody,
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
                ),
                const SizedBox(height: Space.s),
                Text(l10n.churchLinkFooter, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: Space.xl),
                Text(l10n.linkSource, style: AppText.headline),
                const SizedBox(height: Space.m),
                TextField(
                  controller: _source,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.linkSourceUrl,
                    hintText: 'https://',
                    errorText: _tried ? _sourceError : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          if (_source.text.trim().isNotEmpty)
            ListSection(
              children: [ListRow(title: l10n.linkFetchTime, value: fetchTimeLabel(_fetchMinute), onTap: _pickTime)],
            ),
          Padding(
            padding: fieldPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (status != null) ...[
                  Text(
                    status,
                    style: AppText.footnote.copyWith(
                      color: _sourceProblem != null || content?.error != null ? c.destructive : c.secondaryLabel,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                ],
                Text(l10n.linkSourceFooter, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: Space.l),
                PrimaryButton(label: l10n.save, busy: _busy, onPressed: () => _save(link)),
              ],
            ),
          ),
          if (link != null) ...[
            const SizedBox(height: Space.l),
            ListSection(
              children: [ListRow(title: l10n.churchLinkRemove, destructive: true, onTap: () => _remove(link))],
            ),
          ],
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

/// Every quarter hour of the day, opened at the one picked now.
class _TimeSheet extends StatefulWidget {
  const _TimeSheet({required this.selected});

  final int selected;

  @override
  State<_TimeSheet> createState() => _TimeSheetState();
}

class _TimeSheetState extends State<_TimeSheet> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _selectedKey.currentContext;
      if (row != null) Scrollable.ensureVisible(row, alignment: 0.3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => SingleChildScrollView(
          controller: scroll,
          child: ListSection(
            header: l10n.linkFetchTime,
            children: [
              for (var m = 0; m < 24 * 60; m += 15)
                ListRow(
                  key: m == widget.selected ? _selectedKey : null,
                  title: fetchTimeLabel(m),
                  selected: m == widget.selected,
                  onTap: () => Navigator.pop(context, m),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why the content source could not be fetched, for the admin.
String linkErrorText(L10n l10n, LinkFetchError error, int? status) => switch (error) {
  LinkFetchError.timeout => l10n.linkErrTimeout,
  LinkFetchError.tooLarge => l10n.linkErrTooLarge,
  LinkFetchError.badFormat => l10n.linkErrBadFormat,
  LinkFetchError.notHttps => l10n.linkErrNotHttps,
  LinkFetchError.http => l10n.linkErrHttp('${status ?? ''}'),
  LinkFetchError.network => l10n.linkErrNetwork,
  LinkFetchError.unknown => l10n.linkErrUnknown,
};
