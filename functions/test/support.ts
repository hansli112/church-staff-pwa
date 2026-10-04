// Shared setup for handler tests. Run under `firebase emulators:exec`, which
// sets FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST.
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

import type { Caller, Deps, Fetch } from '../src/common.js';

export const PROJECT = 'demo-martha';

if (getApps().length === 0) initializeApp({ projectId: PROJECT });

export const db = getFirestore();
export const auth = getAuth();

let clock = new Date('2026-10-01T10:00:00+08:00');
export const setNow = (d: Date) => {
  clock = d;
};
/** Tests make no real requests: anything not faked fails like a dead network. */
const offline: Fetch = async (url) => {
  throw new TypeError(`fetch failed: no fake for ${url}`);
};
export const deps: Deps = { db, now: () => clock, fetch: offline };

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
 * A fake fetch, injected the way fakeMessaging is: [routes] maps a URL to
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
