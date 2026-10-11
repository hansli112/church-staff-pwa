import { createHash } from 'node:crypto';

import { FieldValue } from 'firebase-admin/firestore';

import { churchAccess, churchClosed, isChurchOpen } from './access.js';
import { fail, id, requireCaller, serverTime, type Caller, type Deps } from './common.js';
import { personName } from './limits.js';

/**
 * 認領與合併: a pending member (moved from self-host) becomes a real member.
 *
 * - Claim: someone signs in with the pending member's email, verified, and
 *   says yes. Never automatic: a file someone else uploaded must not pull a
 *   stranger into their church.
 * - Merge: an admin joins a pending member to someone who already joined
 *   under another email (e.g. switched to Google).
 *
 * Either way the member gets the pending member's role (claim only),
 * groups and zones, the rosters that pointed at the pending member point at
 * them, and the pending member and its index entry are deleted.
 */
/** The email as the pending index (pendingIndex/{hash}) keys it. */
export const emailHash = (email: string) => createHash('sha256').update(email.trim().toLowerCase()).digest('hex');

/** The verified email's hash, or null: an unverified email finds nothing. */
function callerHash(c: Caller) {
  return c.emailVerified && c.email ? emailHash(c.email) : null;
}

/** Pending members waiting for the caller, in open churches. */
export async function pendingClaims(deps: Deps, caller: Caller | null) {
  const c = requireCaller(caller);
  const hash = callerHash(c);
  if (!hash) return { claims: [] };
  const index = await deps.db.doc(`pendingIndex/${hash}`).get();
  const entries = Object.entries((index.get('churches') as Record<string, string> | undefined) ?? {});
  const claims = [];
  for (const [cid, pid] of entries) {
    const [church, pending] = await Promise.all([
      deps.db.doc(`churches/${cid}`).get(),
      deps.db.doc(`churches/${cid}/pendingMembers/${pid}`).get(),
    ]);
    if (!isChurchOpen(church) || !pending.exists || pending.get('emailHash') !== hash) continue;
    claims.push({ churchId: cid, churchName: church.get('name') as string, pendingId: pid, name: pending.get('name') as string });
  }
  return { claims };
}

/**
 * Points every roster that names [pid] at [uid] instead. Only the days the
 * move recorded for [pid] are read.
 */
async function repoint(deps: Deps, cid: string, pid: string, uid: string, rosterIds: string[]) {
  // One transaction per day, a few at a time: an editor changing the same
  // day meanwhile is never overwritten.
  const one = (id: string) =>
    deps.db.runTransaction(async (tx) => {
      const ref = deps.db.doc(`churches/${cid}/rosters/${id}`);
      const s = await tx.get(ref);
      const duties = s.get('duties') as { uids?: Record<string, string> }[] | undefined;
      if (!s.exists || !Array.isArray(duties)) return;
      let changed = false;
      const next = duties.map((d) => ({
        ...d,
        uids: Object.fromEntries(
          Object.entries(d.uids ?? {}).map(([name, u]) => {
            if (u !== pid) return [name, u];
            changed = true;
            return [name, uid];
          }),
        ),
      }));
      if (changed) tx.update(ref, { duties: next });
    });
  for (let i = 0; i < rosterIds.length; i += 10) await Promise.all(rosterIds.slice(i, i + 10).map(one));
}

/** Deletes the pending member and its index entry. */
async function dropPending(deps: Deps, cid: string, pending: FirebaseFirestore.DocumentSnapshot) {
  const hash = pending.get('emailHash') as string | null;
  await pending.ref.delete();
  if (hash) await deps.db.doc(`pendingIndex/${hash}`).set({ churches: { [cid]: FieldValue.delete() } }, { merge: true });
}

/** Drops the index entries of church [cid]'s pending members: the church is purged. */
export async function forgetPendingClaims(deps: Deps, cid: string) {
  const pending = await deps.db.collection(`churches/${cid}/pendingMembers`).get();
  for (const p of pending.docs) {
    const hash = p.get('emailHash') as string | null;
    if (hash) await deps.db.doc(`pendingIndex/${hash}`).set({ churches: { [cid]: FieldValue.delete() } }, { merge: true });
  }
}

/**
 * After any pending member is deleted (an admin dropping it, too, which the
 * app does directly): its index entry goes, if it still points at it.
 */
export async function onPendingMemberDeleted(deps: Deps, cid: string, pending: FirebaseFirestore.DocumentSnapshot) {
  const hash = pending.get('emailHash') as string | null;
  if (!hash) return false;
  const ref = deps.db.doc(`pendingIndex/${hash}`);
  return deps.db.runTransaction(async (tx) => {
    if ((await tx.get(ref)).get(`churches.${cid}`) !== pending.id) return false;
    tx.set(ref, { churches: { [cid]: FieldValue.delete() } }, { merge: true });
    return true;
  });
}

const union = (a: unknown, b: unknown) => [
  ...new Set([...(Array.isArray(a) ? a : []), ...(Array.isArray(b) ? b : [])]),
];

/** [a]'s zones with [b]'s duties and small-group data added, by service. */
function mergeZones(a: unknown, b: unknown) {
  const out = new Map<string, { serviceType: string; duties: unknown[]; smallGroups: unknown[] }>();
  for (const z of [...(Array.isArray(a) ? a : []), ...(Array.isArray(b) ? b : [])] as { serviceType?: string; duties?: unknown; smallGroups?: unknown }[]) {
    if (typeof z?.serviceType !== 'string') continue;
    const previous = out.get(z.serviceType);
    out.set(z.serviceType, {
      serviceType: z.serviceType,
      duties: union(previous?.duties, z.duties),
      smallGroups: union(previous?.smallGroups, z.smallGroups),
    });
  }
  return [...out.values()];
}

function mergedMember(member: FirebaseFirestore.DocumentSnapshot, pending: FirebaseFirestore.DocumentSnapshot) {
  return {
    groups: union(member.get('groups'), pending.get('groups')),
    zones: mergeZones(member.get('zones'), pending.get('zones')),
    zoneTypes: union(member.get('zoneTypes'), pending.get('zoneTypes')),
    // Merge opt-outs, never reset a current preference to a pending default.
    // Updating this field alone also preserves any other current preferences.
    'notificationPrefs.muted': union(member.get('notificationPrefs.muted'), pending.get('notificationPrefs.muted')),
  };
}

/** Joins the caller to the church as the pending member with their email. */
export async function claimPending(deps: Deps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const pid = id((data as { pendingId?: unknown })?.pendingId);
  const hash = callerHash(c);
  if (!hash) fail('failed-precondition', 'unverifiedEmail');
  // Not a member yet, most likely: anyone signed in, but the church open.
  const { cid } = await churchAccess(deps, c, data, 'anyone');
  const pending = await deps.db.runTransaction(async (tx) => {
    const [church, member, pending] = await tx.getAll(
      deps.db.doc(`churches/${cid}`),
      deps.db.doc(`churches/${cid}/members/${c.uid}`),
      deps.db.doc(`churches/${cid}/pendingMembers/${pid}`),
    );
    if (!isChurchOpen(church)) churchClosed();
    if (!pending.exists) {
      // Claimed already (a double tap, a retry): fine if it was by them.
      if (member.exists) return null;
      fail('not-found', 'notFound');
    }
    if (pending.get('emailHash') !== hash) fail('permission-denied', 'permissionDenied');
    if (member.exists) {
      // Read current preferences in the transaction: concurrent edits are kept.
      tx.update(member.ref, mergedMember(member, pending));
    } else {
      tx.create(member.ref, {
        uid: c.uid,
        name: personName(pending.get('name')) || personName(c.name),
        email: c.email ?? '',
        role: pending.get('role') ?? 'member',
        groups: pending.get('groups') ?? [],
        zones: pending.get('zones') ?? [],
        zoneTypes: pending.get('zoneTypes') ?? [],
        notificationPrefs: pending.get('notificationPrefs') ?? { muted: [] },
        joinedAt: serverTime(),
        claimedFrom: pid,
      });
    }
    return pending;
  });
  if (!pending) return { churchId: cid };
  await repoint(deps, cid, pid, c.uid, (pending.get('rosterIds') as string[] | undefined) ?? []);
  await dropPending(deps, cid, pending);
  return { churchId: cid };
}

/**
 * Merges pending member [pendingId] into member [uid] of the same church
 * (admins): for someone who joined with a different email.
 */
export async function mergePending(deps: Deps, caller: Caller | null, data: unknown) {
  const input = (data ?? {}) as { pendingId?: unknown; uid?: unknown };
  const pid = id(input.pendingId);
  const uid = id(input.uid);
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'admin');
  // Both looked up under this church only, so nothing crosses churches.
  const pending = await deps.db.runTransaction(async (tx) => {
    const [church, admin, pending, member] = await tx.getAll(
      deps.db.doc(`churches/${cid}`),
      deps.db.doc(`churches/${cid}/members/${c.uid}`),
      deps.db.doc(`churches/${cid}/pendingMembers/${pid}`),
      deps.db.doc(`churches/${cid}/members/${uid}`),
    );
    if (!admin.exists) fail('permission-denied', 'permissionDenied');
    if (!isChurchOpen(church)) churchClosed();
    if (admin.get('role') !== 'admin') fail('permission-denied', 'permissionDenied');
    if (!pending.exists || !member.exists) fail('not-found', 'notFound');
    tx.update(member.ref, mergedMember(member, pending));
    return pending;
  });
  await repoint(deps, cid, pid, uid, (pending.get('rosterIds') as string[] | undefined) ?? []);
  await dropPending(deps, cid, pending);
  return {};
}
