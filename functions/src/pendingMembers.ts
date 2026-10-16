import { createHash } from 'node:crypto';

import type { Auth } from 'firebase-admin/auth';
import { FieldValue, type BulkWriter, type DocumentSnapshot } from 'firebase-admin/firestore';

import type { Caller, Deps } from './common.js';

/**
 * 待認領的同工: churches/{cid}/pendingMembers/{old uid}, each moved from
 * self-host (move.ts), waiting for whoever signs in with its email
 * (claim.ts). They are found by pendingIndex/{sha256(email)}, which holds
 * `churches.{cid}` = the pending member's ID, and never the email itself;
 * backend only. The index is kept here, in step with the pending members.
 */

/** The email as the index keys it. */
const emailHash = (email: string) => createHash('sha256').update(email.trim().toLowerCase()).digest('hex');

const indexOf = (deps: Pick<Deps, 'db'>, hash: string) => deps.db.doc(`pendingIndex/${hash}`);

async function unindex(deps: Pick<Deps, 'db'>, cid: string, hash: unknown) {
  if (typeof hash === 'string' && hash) await indexOf(deps, hash).set({ churches: { [cid]: FieldValue.delete() } }, { merge: true });
}

/** The caller's verified email as the index keys it, or null: an unverified email finds nothing. */
export const callerKey = (c: Caller) => (c.emailVerified && c.email ? emailHash(c.email) : null);

/** What claiming needs besides the database: the account's linked sign-ins. */
export type ClaimDeps = Deps & { auth: Pick<Auth, 'getUser'> };

/** Providers whose email counts as verified: they vouch for it. */
const vouching = new Set(['google.com', 'apple.com']);

/**
 * Every email the caller can claim with, as the index keys them: the
 * verified [callerKey], and those of the Google and Apple accounts linked
 * to theirs, whatever the account's own email.
 */
export async function callerKeys(deps: Pick<ClaimDeps, 'auth'>, c: Caller) {
  const own = callerKey(c);
  const user = await deps.auth.getUser(c.uid).catch(() => null);
  const linked = (user?.providerData ?? []).filter((p) => vouching.has(p.providerId) && p.email).map((p) => emailHash(p.email!));
  return [...new Set([...(own ? [own] : []), ...linked])];
}

/** Whether [pending] waits for the caller with one of [keys] (see [callerKeys]). */
export const waitsFor = (pending: DocumentSnapshot, keys: string[]) => keys.includes(pending.get('emailHash') as string);

export interface NewPending {
  uid: string;
  email: string | null;
  /** Everything else the pending member keeps (name, role, zones…). */
  data: Record<string, unknown>;
}

/** Adds [p] to church [cid], and to the index, with [w] (a move's writer). Its writes' results. */
export function addPending(deps: Pick<Deps, 'db'>, w: BulkWriter, cid: string, p: NewPending) {
  const hash = p.email ? emailHash(p.email) : null;
  return [
    w.set(deps.db.doc(`churches/${cid}/pendingMembers/${p.uid}`), { ...p.data, email: p.email, emailHash: hash }),
    ...(hash ? [w.set(indexOf(deps, hash), { churches: { [cid]: p.uid } }, { merge: true })] : []),
  ];
}

/** Where pending members wait for the caller with [key]: church ID → pending member ID. Not checked against them. */
export async function waitingFor(deps: Pick<Deps, 'db'>, key: string) {
  const index = await indexOf(deps, key).get();
  return Object.entries((index.get('churches') as Record<string, string> | undefined) ?? {});
}

/** Deletes [pending] (claimed, or merged) and its index entry. */
export async function dropPending(deps: Pick<Deps, 'db'>, cid: string, pending: DocumentSnapshot) {
  await pending.ref.delete();
  await unindex(deps, cid, pending.get('emailHash'));
}

/** Church [cid] is purged, or its move undone: its pending members leave the index. */
export async function forgetPending(deps: Pick<Deps, 'db'>, cid: string) {
  const pending = await deps.db.collection(`churches/${cid}/pendingMembers`).get();
  for (const p of pending.docs) await unindex(deps, cid, p.get('emailHash'));
}

/**
 * After any pending member is deleted (an admin dropping it, too, which the
 * app does directly): its index entry goes, if it still points at it.
 */
export async function onPendingMemberDeleted(deps: Pick<Deps, 'db'>, cid: string, pending: DocumentSnapshot) {
  const hash = pending.get('emailHash') as string | null;
  if (!hash) return false;
  const ref = indexOf(deps, hash);
  return deps.db.runTransaction(async (tx) => {
    if ((await tx.get(ref)).get(`churches.${cid}`) !== pending.id) return false;
    tx.set(ref, { churches: { [cid]: FieldValue.delete() } }, { merge: true });
    return true;
  });
}
