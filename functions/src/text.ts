// Church-name comparison. Mirrors app/lib/domain/text.dart; keep the two in
// step, since the app uses its copy to warn early and this one decides.

/** Full-width ASCII to half-width, ideographic space to space, lower case. */
export function foldWidthAndCase(input: string): string {
  let out = '';
  for (const ch of input) {
    const code = ch.codePointAt(0)!;
    if (code >= 0xff01 && code <= 0xff5e) out += String.fromCodePoint(code - 0xfee0);
    else if (code === 0x3000) out += ' ';
    else out += ch;
  }
  return out.toLowerCase();
}

/** "台北 靈糧堂", "台北靈糧堂" and "ＴＡＩＰＥＩ靈糧堂" vs "taipei靈糧堂" match. */
export function nameKey(name: string): string {
  return foldWidthAndCase(name).replace(/\s+/gu, '');
}

export function matchesSearch(name: string, query: string): boolean {
  const q = nameKey(query);
  return q === '' || nameKey(name).includes(q);
}
