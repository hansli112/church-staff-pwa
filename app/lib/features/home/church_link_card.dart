import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../l10n/app_localizations.dart';

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
            trailing: const ExcludeSemantics(child: Icon(Icons.open_in_new, size: 20)),
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        ),
      ],
    );
  }
}
