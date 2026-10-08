import { createHmac, randomBytes, randomUUID } from 'node:crypto';

import { Timestamp, type DocumentSnapshot, type QueryDocumentSnapshot } from 'firebase-admin/firestore';

import { churchAccess, isChurchOpen } from './access.js';
import { CHURCH_TIME_ZONE, fail, type Caller, type Deps } from './common.js';
import { LIMITS } from './limits.js';
import { seal, unseal } from './sealing.js';

/**
 * 外部通知 (webhooks): a church's admin gives an https URL and a secret;
 * the backend POSTs a JSON notice there when the calendar or the rosters
 * change, e.g. for n8n to forward to a LINE group.
 *
 * Callers only say what happened in which church ([notify], [queue]); this
 * module decides whether it goes out (the church is open, has a URL and
 * has that event's group on), wraps it in the envelope every notice
 * shares, signs it and records how it went.
 *
 * - churches/{cid}/settings/webhook: what admins see (URL, which events,
 *   the last delivery). Backend writes only; admins read.
 * - webhookSecrets/{cid}: the secret, sealed (sealing.ts) with the key the
 *   wiring gives as `secretKey`. No client reads or writes it; it is shown
 *   once when generated.
 * - webhookOutbox/{cid}/rosterChanges/{id}: roster changes not sent yet.
 *   Backend only.
 *
 * Each notice is signed: X-Martha-Signature is `sha256=` and the hex
 * HMAC-SHA256 of `<X-Martha-Timestamp>.<body>`, so a receiver can check it
 * came from here and is not a replay. One attempt, 5 seconds, no redirects,
 * no retries; a failure is recorded and never fails what the user did.
 */
export type WebhookDeps = Deps & { secretKey: string };

/** Events and the switch that turns each on. */
export type WebhookEvent = 'ping' | 'calendar.created' | 'calendar.updated' | 'calendar.deleted' | 'roster.changed';
export type EventGroup = 'calendar' | 'roster';
export const groupOf = (event: WebhookEvent): EventGroup | null =>
  event === 'ping' ? null : event.startsWith('calendar.') ? 'calendar' : 'roster';

/** Roster changes are batched: at most this many are listed in one notice. */
export const MAX_LISTED = 200;

const TIMEOUT_MS = 5000;

const settingsRef = (deps: Deps, cid: string) => deps.db.doc(`churches/${cid}/settings/webhook`);
const secretRef = (deps: Deps, cid: string) => deps.db.doc(`webhookSecrets/${cid}`);
const outboxRef = (deps: Deps, cid: string) => deps.db.doc(`webhookOutbox/${cid}`);

export interface Delivery {
  ok: boolean;
  status: number | null;
  error: 'timeout' | 'network' | 'http' | null;
}

export const signature = (secret: string, timestamp: string, body: string) =>
  `sha256=${createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex')}`;

const newSecret = () => `whsec_${randomBytes(24).toString('base64url')}`;

const isHttps = (url: string) => {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && !!u.hostname;
  } catch {
    return false;
  }
};

/** A secret the admin typed: 16–200 printable characters. */
function givenSecret(v: unknown): string | null {
  if (v === undefined || v === null || v === '') return null;
  if (typeof v !== 'string' || v.length < LIMITS.webhookSecretMin || v.length > LIMITS.webhookSecretMax || !/^[\x21-\x7e]+$/.test(v)) {
    fail('invalid-argument', 'unknown', 'secret');
  }
  return v;
}

async function storeSecret(deps: WebhookDeps, cid: string, secret: string) {
  await secretRef(deps, cid).set({ secret: seal(secret, deps.secretKey), updatedAt: Timestamp.fromDate(deps.now()) });
}

/**
 * Sets the URL and which events are on (admins). The first time, the
 * secret is the one given or a new one, returned once. A null URL turns
 * webhooks off and forgets the secret.
 */
export async function webhookSave(deps: WebhookDeps, caller: Caller | null, data: unknown) {
  const { cid } = await churchAccess(deps, caller, data, 'admin');
  const input = data as { url?: unknown; events?: { calendar?: unknown; roster?: unknown }; secret?: unknown };
  if (input.url === null) {
    await forgetWebhook(deps, cid);
    return { secret: null };
  }
  if (typeof input.url !== 'string' || input.url.length > LIMITS.url || !isHttps(input.url.trim())) {
    fail('invalid-argument', 'unknown', 'notHttps');
  }
  const settings = settingsRef(deps, cid);
  const current = await settings.get();
  const typed = givenSecret(input.secret);
  const hasSecret = (await secretRef(deps, cid).get()).exists;
  let generated: string | null = null;
  if (typed) await storeSecret(deps, cid, typed);
  else if (!hasSecret) {
    generated = newSecret();
    await storeSecret(deps, cid, generated);
  }
  await settings.set({
    url: input.url.trim(),
    events: { calendar: input.events?.calendar === true, roster: input.events?.roster === true },
    lastDelivery: current.get('lastDelivery') ?? null,
    updatedAt: Timestamp.fromDate(deps.now()),
  });
  return { secret: generated };
}

/** Replaces the secret with the one given or a new one, returned once. */
export async function webhookRotateSecret(deps: WebhookDeps, caller: Caller | null, data: unknown) {
  const { cid } = await churchAccess(deps, caller, data, 'admin');
  if (!(await settingsRef(deps, cid).get()).exists) fail('failed-precondition', 'unknown');
  const typed = givenSecret((data as { secret?: unknown }).secret);
  const secret = typed ?? newSecret();
  await storeSecret(deps, cid, secret);
  return { secret: typed ? null : secret };
}

/** Sends a ping now and returns how it went (admins). */
export async function webhookTest(deps: WebhookDeps, caller: Caller | null, data: unknown) {
  const { church } = await churchAccess(deps, caller, data, 'admin');
  const result = await notify(deps, church, 'ping', {});
  if (!result) fail('failed-precondition', 'unknown');
  return result;
}

/**
 * Deletes the settings, the secret and anything still queued: webhooks
 * turned off, or the church purged.
 */
export async function forgetWebhook(deps: Deps, cid: string) {
  await settingsRef(deps, cid).delete();
  await secretRef(deps, cid).delete();
  await deps.db.recursiveDelete(outboxRef(deps, cid));
}

/**
 * The church's webhook settings when [event] would go out now: the church
 * is open, has a URL and has [event]'s group turned on (ping always).
 */
async function wanted(deps: Deps, church: DocumentSnapshot, event: WebhookEvent) {
  if (!isChurchOpen(church)) return null;
  const settings = await settingsRef(deps, church.id).get();
  const group = groupOf(event);
  if (!settings.get('url') || (group && settings.get(`events.${group}`) !== true)) return null;
  return settings;
}

/** A church: its ID, or its doc when the caller has read it already. */
export type ChurchRef = string | DocumentSnapshot;

const churchDoc = async (deps: Deps, church: ChurchRef) =>
  typeof church === 'string' ? deps.db.doc(`churches/${church}`).get() : church;

/**
 * Tells [church]'s webhook that [event] happened, with [details] (the
 * fields that event documents). Returns how it went, or null when nothing
 * was sent (see [wanted]). Never throws.
 */
export async function notify(
  deps: WebhookDeps,
  church: ChurchRef,
  event: WebhookEvent,
  details: Record<string, unknown>,
): Promise<Delivery | null> {
  try {
    return await deliver(deps, await churchDoc(deps, church), event, details);
  } catch (e) {
    console.error(`webhook ${event} for ${typeof church === 'string' ? church : church.id} failed`, e);
    return null;
  }
}

/**
 * Every notice's body: what happened (`action`, the part of the event
 * after the dot; a ping has none), which church, its time zone, then
 * [details].
 */
export function envelope(church: DocumentSnapshot, event: WebhookEvent, details: Record<string, unknown>) {
  const action = event.includes('.') ? event.slice(event.indexOf('.') + 1) : undefined;
  return {
    ...(action ? { action } : {}),
    source: 'martha',
    churchId: church.id,
    churchName: (church.get('name') as string | undefined) ?? '',
    timeZone: CHURCH_TIME_ZONE,
    ...details,
  };
}

/** Signs and sends one notice, and records the outcome as the last delivery. */
async function deliver(
  deps: WebhookDeps,
  church: DocumentSnapshot,
  event: WebhookEvent,
  details: Record<string, unknown>,
): Promise<Delivery | null> {
  const [settings, sealed] = await Promise.all([wanted(deps, church, event), secretRef(deps, church.id).get()]);
  if (!settings || !sealed.exists) return null;
  const body = JSON.stringify(envelope(church, event, details));
  const timestamp = String(Math.floor(deps.now().getTime() / 1000));
  const secret = unseal(sealed.get('secret') as string, deps.secretKey);
  let result: Delivery;
  try {
    const res = await deps.fetch(settings.get('url') as string, {
      method: 'POST',
      redirect: 'manual',
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: {
        'content-type': 'application/json',
        'user-agent': 'martha-webhook',
        'x-martha-event': event,
        'x-martha-delivery': randomUUID(),
        'x-martha-timestamp': timestamp,
        'x-martha-signature': signature(secret, timestamp, body),
      },
      body,
    });
    // Redirects are not followed: a 3xx is a failure like any non-2xx.
    result = res.status >= 200 && res.status < 300 ? { ok: true, status: res.status, error: null } : { ok: false, status: res.status, error: 'http' };
    await res.body?.cancel().catch(() => {});
  } catch (e) {
    const name = (e as { name?: string }).name;
    result = { ok: false, status: null, error: name === 'TimeoutError' || name === 'AbortError' ? 'timeout' : 'network' };
  }
  await settings.ref.update({ lastDelivery: { ...result, event, at: Timestamp.fromDate(deps.now()) } });
  return result;
}

/** One roster change as `roster.changed` lists it. */
export interface QueuedRosterChange {
  date: string;
  serviceId: string;
  serviceName: string;
  duties: { duty: string; added: string[]; removed: string[] }[];
  actorUid: string | null;
  actorName: string | null;
  /** `app`, or `import` for a whole import. */
  via: string;
}

/**
 * `roster.changed` is batched: [queue] adds one change to [church]'s
 * outbox, if the church would get roster notices now, and every 5 minutes
 * [sendQueued] sends each church's outbox as one notice and empties it.
 * A whole import is one notice.
 *
 * One document per change, keyed by [id] (the trigger's event id), so a
 * burst of writes never contends on a single document and a retried
 * trigger adds nothing twice. Returns whether it was queued.
 */
export async function queue(deps: Deps, church: ChurchRef, id: string, change: QueuedRosterChange) {
  const doc = await churchDoc(deps, church);
  if (!(await wanted(deps, doc, 'roster.changed'))) return false;
  await outboxRef(deps, doc.id).collection('rosterChanges').doc(id).set({ ...change, at: Timestamp.fromDate(deps.now()) });
  return true;
}

/**
 * Every 5 minutes: one `roster.changed` notice per church with queued
 * changes, oldest first, then those changes are deleted. A closed church's
 * or a switched-off outbox is emptied without sending.
 */
export async function sendQueued(deps: WebhookDeps) {
  const queued = await deps.db.collectionGroup('rosterChanges').get();
  const byChurch = new Map<string, QueryDocumentSnapshot[]>();
  for (const d of queued.docs) {
    const cid = d.ref.parent.parent?.id;
    if (cid && d.ref.parent.parent?.parent.id === 'webhookOutbox') byChurch.set(cid, [...(byChurch.get(cid) ?? []), d]);
  }
  let sent = 0;
  for (const [cid, docs] of byChurch) {
    const changes = docs
      .map((d) => d.data())
      .sort((a, b) => (a.at as Timestamp).toMillis() - (b.at as Timestamp).toMillis())
      .map((c): QueuedRosterChange => ({
        date: c.date,
        serviceId: c.serviceId,
        serviceName: c.serviceName,
        duties: c.duties,
        actorUid: c.actorUid,
        actorName: c.actorName,
        via: c.via,
      }));
    const result = await notify(deps, cid, 'roster.changed', {
      count: changes.length,
      imported: changes.some((c) => c.via === 'import'),
      changes: changes.slice(0, MAX_LISTED),
      more: Math.max(0, changes.length - MAX_LISTED),
    });
    if (result) sent++;
    const w = deps.db.bulkWriter();
    for (const d of docs) void w.delete(d.ref);
    await w.close();
  }
  return sent;
}
