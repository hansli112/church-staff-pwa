// Shared setup for handler tests. Run under `firebase emulators:exec`, which
// sets FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST.
import assert from 'node:assert/strict';

import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { DocumentReference, Firestore, getFirestore, Timestamp, type DocumentSnapshot, type Transaction } from 'firebase-admin/firestore';

import type { Messaging } from 'firebase-admin/messaging';

import type { PurgeDeps } from '../src/church.js';
import type { Caller, Deps, Fetch } from '../src/common.js';
import { memoryGoogle } from '../src/memoryGoogle.js';

export const PROJECT = 'demo-martha';

if (getApps().length === 0) initializeApp({ projectId: PROJECT });

export const db = getFirestore();
export const auth = getAuth();

let clock = new Date('2026-10-01T10:00:00+08:00');
export const setNow = (d: Date) => {
  clock = d;
};
/** A push FCM was asked to send, through [fakePush]. */
export interface SentPush {
  tokens: string[];
  title: string;
  body: string;
  /** The app's link (data.link), without the notification it names. */
  link: string;
  /** The web push's, which FCM wants absolute; likewise. */
  webLink: string;
  /** The id of the notification in the 通知列表 both links name. */
  notification: string | null;
  /** The number on the app icon (aps.badge). */
  badge: number | undefined;
}

/**
 * FCM for tests: every push is recorded in [sent]. [dead] tokens are
 * refused as no longer registered; after goDown() every send throws, like
 * FCM out of reach.
 */
/** [dead] tokens fail as unregistered; [errors] fail with the code given. */
export function fakePush(dead: string[] = [], errors: Record<string, string> = {}) {
  const sent: SentPush[] = [];
  let down = false;
  const messaging: Pick<Messaging, 'sendEachForMulticast'> = {
    sendEachForMulticast: async (m) => {
      if (down) throw new Error('fcm unreachable');
      const tokens = (m as { tokens: string[] }).tokens;
      const link = m.data?.link ?? '';
      const webLink = m.webpush?.fcmOptions?.link ?? '';
      const notification = /[?&]notification=([^&]*)/.exec(link)?.[1] ?? null;
      assert.equal(/[?&]notification=([^&]*)/.exec(webLink)?.[1] ?? null, notification, 'both links name the same notification');
      sent.push({
        tokens,
        title: m.notification?.title ?? '',
        body: m.notification?.body ?? '',
        link: withoutNotification(link),
        webLink: withoutNotification(webLink),
        notification,
        badge: m.apns?.payload?.aps?.badge,
      });
      const responses = tokens.map((t) =>
        dead.includes(t)
          ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
          : errors[t]
            ? { success: false, error: { code: errors[t] } }
            : { success: true },
      );
      const successCount = responses.filter((r) => r.success).length;
      return { successCount, failureCount: tokens.length - successCount, responses } as never;
    },
  };
  return { messaging, sent, goDown: () => void (down = true) };
}

const withoutNotification = (link: string) => link.replace(/&notification=[^&]*/, '');

/** Tests make no real requests: anything not faked fails like a dead network. */
const offline: Fetch = async (url) => {
  throw new TypeError(`fetch failed: no fake for ${url}`);
};
export const deps: Deps = { db, now: () => clock, fetch: offline };

/** What a purge needs, for tests that connect no calendar: Google is never reached. */
export const purgeDeps: PurgeDeps = {
  ...deps,
  secretKey: '',
  google: memoryGoogle().google,
  config: { clientId: '', clientSecret: '', redirectUri: '', appUrl: '', tokenKey: '' },
};

/** What a fake endpoint answers. */
export interface FakeResponse {
  status?: number;
  /** A string is sent as is; anything else as JSON. */
  body?: unknown;
  headers?: Record<string, string>;
  /** Answers after this long, unless the request is aborted first. */
  delayMs?: number;
  /** Answers with a 302 to this URL. */
  redirect?: string;
}

export interface SeenRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string;
}

/**
 * A fake fetch, injected the way fakePush's messaging is: [routes] maps a URL to
 * its answer (or a function of the request). Unknown URLs fail like a dead
 * network. Every request is recorded in [requests].
 */
export function fakeFetch(routes: Record<string, FakeResponse | ((req: SeenRequest) => FakeResponse)> = {}) {
  const requests: SeenRequest[] = [];
  const fetch: Fetch = async (url, init = {}) => {
    const req: SeenRequest = {
      url,
      method: (init.method ?? 'GET').toUpperCase(),
      headers: Object.fromEntries(new Headers(init.headers).entries()),
      body: typeof init.body === 'string' ? init.body : '',
    };
    requests.push(req);
    const route = routes[url];
    if (!route) throw new TypeError(`fetch failed: ${url}`);
    const r = typeof route === 'function' ? route(req) : route;
    if (r.delayMs) await abortableDelay(r.delayMs, init.signal ?? undefined);
    if (r.redirect) {
      return new Response(null, { status: 302, headers: { location: r.redirect } });
    }
    const body = r.body === undefined ? '' : typeof r.body === 'string' ? r.body : JSON.stringify(r.body);
    return new Response(body, { status: r.status ?? 200, headers: r.headers });
  };
  return { fetch, requests };
}

function abortableDelay(ms: number, signal?: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason);
    const t = setTimeout(resolve, ms);
    signal?.addEventListener('abort', () => {
      clearTimeout(t);
      reject(signal.reason);
    });
  });
}

export function caller(uid: string, extra: Partial<Caller> = {}): Caller {
  return {
    uid,
    email: `${uid}@example.com`,
    emailVerified: true,
    name: uid,
    operator: false,
    ...extra,
  };
}

export async function clearFirestore() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) throw new Error('Run under the Firestore emulator');
  await fetch(`http://${host}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, {
    method: 'DELETE',
  });
}

/** Rejects with an HttpsError whose details.reason is [reason]. */
export async function rejectsWith(promise: Promise<unknown>, reason: string) {
  try {
    await promise;
  } catch (e) {
    const details = (e as { details?: { reason?: string } }).details;
    if (details?.reason === reason) return e;
    throw new Error(`Expected ${reason}, got ${String(e)} ${JSON.stringify(details)}`);
  }
  throw new Error(`Expected ${reason}, but it resolved`);
}

/** Seeds an active church with members (uid → role). */
export async function seedChurch(
  cid: string,
  members: Record<string, string>,
  extra: Record<string, unknown> = {},
) {
  await db.doc(`churches/${cid}`).set({
    name: cid,
    nameKey: cid.toLowerCase(),
    status: 'active',
    createdAt: Timestamp.now(),
    ...extra,
  });
  await db.doc(`churchNames/${cid.toLowerCase()}`).set({ cid });
  for (const [uid, role] of Object.entries(members)) {
    await db.doc(`churches/${cid}/members/${uid}`).set({
      uid,
      name: uid,
      email: `${uid}@example.com`,
      role,
      groups: [],
      zones: [],
      zoneTypes: [],
    });
  }
}

/** One committed write of a document: what a Firestore trigger on it is given. */
export interface SeenWrite {
  path: string;
  before: DocumentSnapshot;
  after: DocumentSnapshot;
}

/**
 * Records every write [run] makes, one commit at a time, as a trigger would
 * see it: plain writes and transactions (not batches).
 */
export async function recordWrites(run: () => Promise<unknown>): Promise<SeenWrite[]> {
  const seen: SeenWrite[] = [];
  const undo: (() => void)[] = [];
  const patch = <T extends object>(proto: T, name: keyof T & string, wrap: (orig: Function) => Function) => {
    const orig = (proto as Record<string, Function>)[name];
    (proto as Record<string, Function>)[name] = wrap(orig);
    undo.push(() => ((proto as Record<string, Function>)[name] = orig));
  };
  for (const m of ['set', 'update', 'delete', 'create'] as const) {
    patch(DocumentReference.prototype, m, (orig) => async function (this: DocumentReference, ...args: unknown[]) {
      const before = await this.get();
      const out = await orig.apply(this, args);
      seen.push({ path: this.path, before, after: await this.get() });
      return out;
    });
  }
  patch(Firestore.prototype, 'runTransaction', (orig) => async function (this: Firestore, fn: (tx: Transaction) => unknown, opts?: unknown) {
    let before = new Map<string, Promise<DocumentSnapshot>>();
    let written = new Map<string, DocumentReference>();
    const out = await orig.call(this, async (tx: Transaction) => {
      // A retry starts again.
      before = new Map();
      written = new Map();
      const proxy: Transaction = new Proxy(tx, {
        get(t, key) {
          const v = Reflect.get(t, key, t);
          if (key === 'get') {
            return async (ref: DocumentReference, ...rest: unknown[]) => {
              const snap = await v.call(t, ref, ...rest);
              if (ref instanceof DocumentReference) before.set(ref.path, Promise.resolve(snap));
              return snap;
            };
          }
          if (key === 'set' || key === 'update' || key === 'delete' || key === 'create') {
            return (ref: DocumentReference, ...rest: unknown[]) => {
              written.set(ref.path, ref);
              if (!before.has(ref.path)) before.set(ref.path, ref.get());
              v.call(t, ref, ...rest);
              return proxy;
            };
          }
          return typeof v === 'function' ? v.bind(t) : v;
        },
      });
      const result = await fn(proxy);
      // Read before the commit.
      await Promise.all(before.values());
      return result;
    }, opts);
    for (const [path, ref] of written) seen.push({ path, before: await before.get(path)!, after: await ref.get() });
    return out;
  });
  try {
    await run();
  } finally {
    for (const u of undo.reverse()) u();
  }
  return seen;
}
