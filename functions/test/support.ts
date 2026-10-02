// Shared setup for handler tests. Run under `firebase emulators:exec`, which
// sets FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST.
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

import type { Caller, Deps } from '../src/common.js';

export const PROJECT = 'demo-martha';

if (getApps().length === 0) initializeApp({ projectId: PROJECT });

export const db = getFirestore();
export const auth = getAuth();

let clock = new Date('2026-10-01T10:00:00+08:00');
export const setNow = (d: Date) => {
  clock = d;
};
export const deps: Deps = { db, now: () => clock };

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
