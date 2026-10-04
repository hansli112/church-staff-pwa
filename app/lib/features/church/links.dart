import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design/components.dart';
import '../../env.dart';

/// The church URL: fixed from the day the church is created. Opening it
/// picks that church; adding it to the home screen gives the church's name
/// and icon (the church page function, functions/src/churchPage.ts).
String churchUrl(String churchId) => '${Env.current.webOrigin}/c/$churchId';

/// The link an invite opens: under the church URL, so adding the invite
/// page to the home screen already gives the church's icon.
String inviteLink(String churchId, String code) => '${churchUrl(churchId)}/join/$code';

/// [url] without the scheme, for showing in a row.
String displayUrl(String url) => url.replaceFirst(RegExp('^https?://'), '');

/// Opens the system share sheet with [text]; copies it when sharing is not
/// available, and says so with [copied].
Future<void> shareText(BuildContext context, String text, {required String copied}) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showToast(context, copied);
  }
}

Future<void> copyText(BuildContext context, String text, {required String copied}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, copied);
}
