import { createHmac, randomBytes, randomUUID } from 'node:crypto';

import { Timestamp } from 'firebase-admin/firestore';

import { decrypt, encrypt } from './calendar.js';
import { churchAccess } from './access.js';
import { fail, type Caller, type Deps } from './common.js';
import { LIMITS } from './limits.js';

/**
 * 外部通知 (webhooks): a church's admin gives an https URL and a secret;
 * the backend POSTs a JSON notice there when the calendar or the rosters
 * change, e.g. for n8n to forward to a LINE group.
 *
 * - churches/{cid}/settings/webhook: what admins see (URL, which events,
 *   the last delivery). Backend writes only; admins read.
 * - webhookSecrets/{cid}: the secret, AES-256-GCM sealed like the calendar
 *   token. No client reads or writes it; it is shown once when generated.
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

const TIMEOUT_MS = 5000;

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
  await deps.db.doc(`webhookSecrets/${cid}`).set({ secret: encrypt(secret, deps.secretKey), updatedAt: Timestamp.fromDate(deps.now()) });
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
  const settings = deps.db.doc(`churches/${cid}/settings/webhook`);
  const current = await settings.get();
  const typed = givenSecret(input.secret);
  const hasSecret = (await deps.db.doc(`webhookSecrets/${cid}`).get()).exists;
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
  if (!(await deps.db.doc(`churches/${cid}/settings/webhook`).get()).exists) fail('failed-precondition', 'unknown');
  const typed = givenSecret((data as { secret?: unknown }).secret);
  const secret = typed ?? newSecret();
  await storeSecret(deps, cid, secret);
  return { secret: typed ? null : secret };
}

/** Sends a ping now and returns how it went (admins). */
export async function webhookTest(deps: WebhookDeps, caller: Caller | null, data: unknown) {
  const { cid, church } = await churchAccess(deps, caller, data, 'admin');
  const result = await deliver(deps, cid, 'ping', { source: 'martha', churchId: cid, churchName: church.get('name') });
  if (!result) fail('failed-precondition', 'unknown');
  return result;
}

/** Deletes the webhook settings and secret: turned off, or the church purged. */
export async function forgetWebhook(deps: Deps, cid: string) {
  await deps.db.doc(`churches/${cid}/settings/webhook`).delete();
  await deps.db.doc(`webhookSecrets/${cid}`).delete();
}

/**
 * Sends [event] with [payload] as the body to the church's webhook, if it
 * is open, has a URL and has [event]'s group turned on (ping always).
 * Records the outcome as the last delivery. Returns null when nothing was
 * sent. Never throws.
 */
export async function deliver(
  deps: WebhookDeps,
  cid: string,
  event: WebhookEvent,
  payload: Record<string, unknown>,
): Promise<Delivery | null> {
  try {
    const [church, settings, sealed] = await Promise.all([
      deps.db.doc(`churches/${cid}`).get(),
      deps.db.doc(`churches/${cid}/settings/webhook`).get(),
      deps.db.doc(`webhookSecrets/${cid}`).get(),
    ]);
    if (church.get('status') !== 'active' || !settings.exists || !sealed.exists) return null;
    const url = settings.get('url') as string | undefined;
    const group = groupOf(event);
    if (!url || (group && settings.get(`events.${group}`) !== true)) return null;

    const body = JSON.stringify(payload);
    const timestamp = String(Math.floor(deps.now().getTime() / 1000));
    const secret = decrypt(sealed.get('secret') as string, deps.secretKey);
    let result: Delivery;
    try {
      const res = await deps.fetch(url, {
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
  } catch (e) {
    console.error(`webhook ${event} for ${cid} failed`, e);
    return null;
  }
}
