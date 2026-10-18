import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/link_errors.dart';

/// 教會連結 on the home page: title, a line or two, and the link opens in
/// the browser.
class ChurchLinkCard extends StatelessWidget {
  const ChurchLinkCard({super.key, required this.title, required this.body, required this.url});

  final String title;
  final String body;
  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListSection(
      children: [
        Semantics(
          link: true,
          hint: l10n.churchLinkOpens,
          child: ListRow(
            title: title,
            subtitle: body.isEmpty ? null : body,
            trailing: const ExcludeSemantics(child: Icon(Symbols.open_in_new_rounded, size: 20)),
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        ),
      ],
    );
  }
}

/// A sourced church link without today's content: why, and for an admin a
/// retry of the source the church has set. Never the fixed link instead.
class ChurchLinkSourceStatus extends ConsumerStatefulWidget {
  const ChurchLinkSourceStatus({super.key});

  @override
  ConsumerState<ChurchLinkSourceStatus> createState() => _ChurchLinkSourceStatusState();
}

class _ChurchLinkSourceStatusState extends ConsumerState<ChurchLinkSourceStatus> {
  bool _busy = false;

  Future<void> _retry() async {
    final l10n = L10n.of(context);
    final data = ref.churchData;
    setState(() => _busy = true);
    try {
      final result = await data.refreshChurchLink();
      // Another church's answer must not speak here.
      if (!mounted || ref.read(churchDataProvider)?.churchId != data.churchId) return;
      if (!result.ok) showToast(context, l10n.linkSourceFailed(linkErrorText(l10n, result.error!, result.status)));
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final loaded = ref.watch(linkContentProvider);
    if (loaded.hasError) {
      // This device could not read what the backend has: read again.
      return ListSection(
        children: [
          ListRow(
            title: l10n.churchLink,
            subtitle: l10n.loadFailed,
            trailing: TextButton(onPressed: () => ref.invalidate(linkContentProvider), child: Text(l10n.retry)),
          ),
        ],
      );
    }
    final content = loaded.value;
    final admin = ref.watch(meProvider.select((m) => m.value?.isAdmin ?? false));
    final error = content?.error;
    final reason = error == null ? l10n.linkErrNotToday : linkErrorText(l10n, error, content?.errorStatus);
    return ListSection(
      children: [
        ListRow(
          title: l10n.churchLink,
          subtitle: l10n.linkSourceToday(reason),
          trailing: admin
              ? (_busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator.adaptive(strokeWidth: 2.5))
                    : TextButton(onPressed: _retry, child: Text(l10n.retry)))
              : null,
          leading: Icon(Symbols.info_rounded, color: AppColors.of(context).secondaryLabel),
        ),
      ],
    );
  }
}
