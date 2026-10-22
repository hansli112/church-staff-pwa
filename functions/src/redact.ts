/** Removes things that look like emails or phone numbers, not dates. */
export function scrub(text: string): string {
  return text
    .replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '<email>')
    .replace(/(?<!\d)(?!\d{4}-\d\d-\d\d\b)\+?\d[\d -]{7,}\d/g, '<number>');
}

/**
 * [e] as it may be logged: its kind, code, status, and its message and
 * stack scrubbed. Never the error itself, which for a Google API error
 * carries the request and the answer (a token, an event's title, its
 * guests).
 */
export function loggable(e: unknown): Error {
  if (!(e instanceof Error)) return new Error(scrub(String(e)));
  const safe = new Error(scrub(e.message));
  safe.name = e.name;
  safe.stack = e.stack === undefined ? undefined : scrub(e.stack);
  const { code, status } = e as { code?: unknown; status?: unknown };
  const plain = (v: unknown) => typeof v === 'string' || typeof v === 'number';
  if (plain(code)) Object.assign(safe, { code });
  if (plain(status)) Object.assign(safe, { status });
  return safe;
}
