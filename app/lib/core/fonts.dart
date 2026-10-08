import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's strings, shipped as an asset so their characters are known
/// before any page is drawn.
const uiStringsAsset = 'lib/l10n/app_zh.arb';

/// How long the page's loading screen waits for fonts at most.
const fontsWaitLimit = Duration(seconds: 3);

/// Every string of the app, run together: its .arb [json] without the
/// notes (`@` keys).
String uiText(String json) => [
  for (final MapEntry(:key, :value) in (jsonDecode(json) as Map<String, dynamic>).entries)
    if (!key.startsWith('@') && value is String) value,
].join();

/// On the web the engine draws Chinese with fonts it downloads when a text
/// first needs them, so the first page shows boxes until they arrive. This
/// lays out every character of the app's own text at once, before any page,
/// so those downloads start alongside the app's.
///
/// Completes when the engine next says its fonts changed ([systemFonts]),
/// which it does once a round of downloads is done, failed ones included;
/// or after [fontsWaitLimit].
Future<void> warmUpFonts({required AssetBundle bundle, required Listenable systemFonts}) {
  final done = Completer<void>();
  void finish() {
    systemFonts.removeListener(finish);
    if (!done.isCompleted) done.complete();
  }

  systemFonts.addListener(finish);
  Timer(fontsWaitLimit, finish);
  bundle.loadString(uiStringsAsset).then((json) {
    (ui.ParagraphBuilder(ui.ParagraphStyle())..addText(uiText(json))).build();
  }, onError: (_) {});
  return done.future;
}
