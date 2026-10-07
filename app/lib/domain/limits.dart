/// Length limits. The Cloud Functions keep the same numbers in
/// functions/src/limits.ts and firestore.rules guards some of them;
/// functions/test/limits.test.ts reads all three and fails when they
/// disagree. Keep every value a plain number so it can.
library;

import 'package:characters/characters.dart';

import 'text.dart';

/// Text limits, in characters as a person counts them (grapheme clusters,
/// [characterCount]): "🙏" and "👨‍👩‍👧" are one each. The text fields, the
/// MemoryBackend and the Functions count this way.
abstract final class TextLimits {
  /// 教會名稱.
  static const churchName = 60;

  /// 主畫面名稱. Past `Church.homeNameSafeLength` some phones cut it off.
  static const homeName = 8;

  /// 教會連結 title and body.
  static const linkTitle = 30;
  static const linkBody = 120;

  /// A cost on the funding page (平台營運者).
  static const costName = 40;

  /// The name on the profile.
  static const profileName = 40;
}

/// Limits whose unit is the same everywhere: URLs and secrets in UTF-16
/// code units, services as a count.
abstract final class Limits {
  /// The church link's URL and content source, the webhook URL.
  static const url = 500;

  /// A webhook secret the admin types: printable ASCII.
  static const webhookSecretMin = 16;
  static const webhookSecretMax = 200;

  /// Service types per church.
  static const services = 20;
}

/// firestore.rules counts UTF-16 code units, not characters, so for a
/// [TextLimits] value it allows that many times as many: an abuse guard,
/// not the limit. A character longer than this (a family emoji, a flag with
/// tags) can reach the guard before the limit.
const rulesSizeFactor = 4;

/// Whether the backend takes [text] for a field limited to [max]
/// characters: at most [max] characters and at most [max] ×
/// [rulesSizeFactor] UTF-16 code units.
bool withinTextLimit(String text, int max) => text.length <= max * rulesSizeFactor && characterCount(text) <= max;

/// [text] trimmed and cut to [max] characters, for text the app takes from
/// elsewhere (the name a Google account gives).
String cutText(String text, int max) => text.trim().characters.take(max).toString().trim();
