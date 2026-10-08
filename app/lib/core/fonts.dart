import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's strings, shipped as an asset so their characters are known
/// before any page is drawn.
const uiStringsAsset = 'lib/l10n/app_zh.arb';

/// How long the page's loading screen waits for fonts at most, once the
/// app is ready to show a page.
const fontsWaitLimit = Duration(seconds: 3);

/// Two characters from each of the files Google Fonts splits Noto Sans TC's
/// most used characters into: the last 20 of its about 100 files hold some
/// 4,300 characters, nearly every name and word a church types. Laying these
/// out fetches all 20 (about 740 KB, 15 of them needed for the app's own
/// text anyway), so names show at once too, not only the app's text. Only
/// for browsers in Traditional Chinese (zh-TW): elsewhere the engine picks
/// other fonts for the same characters.
/// Picked from fonts.googleapis.com/css2?family=Noto+Sans+TC, whose files
/// go from the least used characters to the most; the engine's copy of the
/// list numbers these 20 files 100 to 119. Check them again on a Flutter
/// upgrade: a new copy may split them differently.
const commonCharacters = '玖誦砌蠶渦蔻瀚舜濤蔚滷蒜瑩菸毅芒槽芽疊蘿淚蒂洞舖棄苗武耳減聖泰詳瀏該比著服聯心正';

/// Every string of an .arb file, run together, without its notes (`@`
/// keys).
String arbText(String json) => [
  for (final MapEntry(:key, :value) in (jsonDecode(json) as Map<String, dynamic>).entries)
    if (!key.startsWith('@') && value is String) value,
].join();

/// On the web the engine draws Chinese with fonts it downloads when a text
/// first needs them, so the first page shows boxes until they arrive. This
/// lays out every character of the app's own text at once, before any page,
/// so those downloads start alongside the app's; once they are in, the most
/// used characters ([commonCharacters]), for the names the pages show. The
/// loading screen waits for the app's own only, not for those.
///
/// Completes when the engine next says its fonts changed ([systemFonts]),
/// which it does once a round of downloads is done, failed ones included.
/// [layOut] lays a text out, which is what asks the engine for its fonts.
Future<void> warmUpFonts({
  required AssetBundle bundle,
  required Listenable systemFonts,
  void Function(String text) layOut = _layOut,
}) {
  final done = Completer<void>();
  void finish() {
    if (done.isCompleted) return;
    done.complete();
    // Not while it is calling its listeners: it cannot take that.
    scheduleMicrotask(() {
      systemFonts.removeListener(finish);
      layOut(commonCharacters);
    });
  }

  systemFonts.addListener(finish);
  unawaited(() async {
    try {
      layOut(arbText(await bundle.loadString(uiStringsAsset)));
    } catch (_) {
      // Without them, the first page asks for the fonts it needs.
    }
  }());
  return done.future;
}

void _layOut(String text) => (ui.ParagraphBuilder(ui.ParagraphStyle())..addText(text)).build();
