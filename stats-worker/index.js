// One row per installer event. Only these fields, each checked against a
// fixed shape, are stored: never names, emails, project IDs or IP addresses.
const EVENTS = new Set(['opened', 'started', 'stopped', 'completed']);
const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const STEP = /^[a-z][a-z-]{0,39}$/;
const CODE = /^[A-Z][A-Z0-9_]{0,59}$/;
const REVISION = /^[0-9a-f]{40}$/;

const optional = (value, shape) => (value === undefined || value === null ? null : shape.test(value) ? value : undefined);

export function parseEvent(body) {
  if (!body || typeof body !== 'object' || !EVENTS.has(body.event) || !ID.test(body.session ?? '')) return null;
  const fields = { runId: optional(body.runId, ID), step: optional(body.step, STEP), code: optional(body.code, CODE), revision: optional(body.revision, REVISION) };
  if (Object.values(fields).includes(undefined)) return null;
  return { event: body.event, session: body.session, ...fields };
}

export default {
  async fetch(request, env) {
    if (request.method !== 'POST' || new URL(request.url).pathname !== '/event') return new Response(null, { status: 404 });
    const text = await request.text();
    let event = null;
    try { if (text.length <= 1024) event = parseEvent(JSON.parse(text)); } catch { /* Rejected below. */ }
    if (!event) return new Response(null, { status: 400 });
    await env.DB.prepare('INSERT INTO events (at, event, session, run_id, step, code, revision) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .bind(new Date().toISOString(), event.event, event.session, event.runId, event.step, event.code, event.revision).run();
    return new Response(null, { status: 204 });
  },
};
