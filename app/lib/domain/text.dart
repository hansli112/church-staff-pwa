/// Text comparison rules shared by church-name checks and people search.
///
/// The Cloud Function that enforces unique church names applies the same
/// rule (functions/src/text.ts); keep the two in step.
library;

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
  return out.toString().toLowerCase();
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
