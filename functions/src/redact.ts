/** Removes things that look like emails or phone numbers. */
export function scrub(text: string): string {
  return text
    .replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '<email>')
    .replace(/\+?\d[\d -]{7,}\d/g, '<number>');
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
  for (const [key, value] of Object.entries({ code, status })) {
    if (typeof value === 'string' || typeof value === 'number') Object.assign(safe, { [key]: value });
  }
  return safe;
}
