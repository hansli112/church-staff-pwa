/// Text comparison rules shared by church-name checks and people search,
/// and how characters are counted.
///
/// The Cloud Functions apply the same rules (functions/src/text.ts) and
/// decide; both test suites run every row of testdata/text_rules.json, so
/// keep the two in step through that table.
library;

import 'package:characters/characters.dart';

/// How many characters [text] has as a person counts them (grapheme
/// clusters): "🙏", "🇹🇼" and "é" written as e + accent are one each. The
/// unit of every `TextLimits` value.
int characterCount(String text) => text.characters.length;

/// A capital sigma that ends a word, where JavaScript's toLowerCase gives
/// the final form ς (Unicode's Final_Sigma condition).
final _finalSigma = RegExp(r'(?<=\p{Cased}\p{Case_Ignorable}*)Σ(?!\p{Case_Ignorable}*\p{Cased})', unicode: true);

/// Lower case exactly as the server's JavaScript does it. The Dart VM leaves
/// out two special mappings JavaScript applies: İ to i + combining dot
/// and a word-final Σ to ς.
String _lowerCase(String input) => input.replaceAll('İ', 'i̇').replaceAll(_finalSigma, 'ς').toLowerCase();

/// Full-width ASCII (U+FF01–FF5E) to half-width, the ideographic space to a
/// plain space, then lower case.
String foldWidthAndCase(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      out.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000) {
      out.writeCharCode(0x20);
    } else {
      out.writeCharCode(rune);
    }
  }
  return _lowerCase(out.toString());
}

final _whitespace = RegExp(r'\s+');

/// The key two church names are compared by: "台北 靈糧堂" and "台北靈糧堂"
/// are the same church.
String nameKey(String name) => foldWidthAndCase(name).replaceAll(_whitespace, '');

/// Whether [name] contains [query], ignoring spaces, width and case.
bool matchesSearch(String name, String query) {
  final q = nameKey(query);
  if (q.isEmpty) return true;
  return nameKey(name).contains(q);
}

/// How closely two people's names agree, for whoever is picking someone by
/// name: the same name (as [nameKey] has it), one inside the other (「小明」
/// and 「王小明」, "Hans" and "Hans Lee"), or neither. One character is too
/// little to go by. Only the app ranks by it; the server never decides by it.
enum NameMatch { exact, partial, none }

NameMatch nameMatch(String a, String b) {
  final x = nameKey(a);
  final y = nameKey(b);
  if (x.isEmpty || y.isEmpty) return NameMatch.none;
  if (x == y) return NameMatch.exact;
  final (short, long) = x.length <= y.length ? (x, y) : (y, x);
  return characterCount(short) >= 2 && long.contains(short) ? NameMatch.partial : NameMatch.none;
}
