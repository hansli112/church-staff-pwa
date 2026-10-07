import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../env.dart';
import '../../l10n/app_localizations.dart';

/// The church URL: fixed from the day the church is created. Opening it
/// picks that church; adding it to the home screen gives the church's name
/// and icon (the church page function, functions/src/churchPage.ts).
String churchUrl(String churchId) => '${Env.current.webOrigin}/c/$churchId';

/// The link an invite opens: under the church URL, so adding the invite
/// page to the home screen already gives the church's icon.
String inviteLink(String churchId, String code) => '${churchUrl(churchId)}/join/$code';

/// The invite code in a location made by [inviteLink] (path only, like a
/// login page's `from`), upper-cased; null for anything else.
String? inviteCodeIn(String location) =>
    RegExp(r'^/c/[^/?]+/join/([A-Za-z0-9]+)').firstMatch(location)?.group(1)?.toUpperCase();

/// [url] without the scheme, for showing in a row.
String displayUrl(String url) => url.replaceFirst(RegExp('^https?://'), '');

/// Opens the system share sheet with [text]; copies it when sharing is not
/// available (most desktop browsers), and says so with [copied].
Future<void> shareText(BuildContext context, String text, {required String copied}) async {
  try {
    // Without the share sheet the plugin would open a mail app instead.
    await SharePlus.instance.share(ShareParams(text: text, mailToFallbackEnabled: false));
  } catch (_) {
    if (context.mounted) await copyText(context, text, copied: copied);
  }
}

/// Copies [text] and says so with [copied]. When the browser refuses the
/// clipboard, shows the text so it can be selected and copied by hand.
Future<void> copyText(BuildContext context, String text, {required String copied}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (_) {
    if (context.mounted) await _copyByHand(context, text);
    return;
  }
  if (context.mounted) showToast(context, copied);
}

Future<void> _copyByHand(BuildContext context, String text) {
  return showAppSheet<void>(
    context,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(L10n.of(context).copyByHand, style: AppText.headline),
          const SizedBox(height: Space.m),
          SelectableText(text, style: AppText.body),
        ],
      ),
    ),
  );
}
