import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/languages.dart';
import '../../env.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';

/// A page of the website: the privacy policy and the terms, which the stores
/// require the app to link to, the guides, and on the web the support page.
/// The stores forbid the iOS and Android apps to lead to paying elsewhere,
/// so they open it with `fromApp` (AppLanguage.sitePage).
void openSitePage(BuildContext context, WidgetRef ref, String page) => launchUrl(
  Uri.parse(
    '${Env.current.webOrigin}${AppLanguage.shownIn(context).sitePage(page, fromApp: !ref.read(isWebProvider))}',
  ),
);

/// The website's guides (`landing/blog/<slug>.md`) a page opens, for whoever
/// has forgotten how it works.
enum Guide {
  planWeeks('plan-weeks'),
  smallGroups('small-groups'),
  notifications('notifications')
  ;

  const Guide(this.slug);

  final String slug;
}

/// [guide], or all the guides.
void openGuide(BuildContext context, WidgetRef ref, [Guide? guide]) =>
    openSitePage(context, ref, guide == null ? '/blog/' : '/blog/${guide.slug}/');

/// 怎麼用？ in the app bar of a page with a guide of its own. In words: an
/// icon a patch adds would not be in the store release's font.
class GuideButton extends ConsumerWidget {
  const GuideButton(this.guide, {super.key});

  final Guide guide;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      TextButton(onPressed: () => openGuide(context, ref, guide), child: Text(L10n.of(context).howToUse));
}
