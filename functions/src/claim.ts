import { churchAccess, churchClosed, isChurchOpen } from './access.js';
import { fail, id, requireCaller, serverTime, type Caller, type Deps } from './common.js';
import { identitiesOf, withIdentities, type Identity } from './identities.js';
import { personName } from './limits.js';
import { dateKeyIn, timeZoneOf } from './timeZones.js';
import { callerKeys, dropPending, waitingFor, waitsFor, type ClaimDeps } from './pendingMembers.js';
import { claimedSmallGroups, smallGroupsByName } from './smallGroups.js';

/**
 * 認領與合併: a pending member (moved from self-host) becomes a real member.
 *
 * - Claim: someone signs in with the pending member's email, verified, or
 *   has linked a Google or Apple account under it, and says yes. Never
 *   automatic: a file someone else uploaded must not pull a stranger into
 *   their church.
 * - Merge: an admin joins a pending member to someone who already joined
 *   under another email (e.g. switched to Google).
 *
 * - By name: a pending member with no email, by someone already in its
 *   church under the same name (joined by invite), who says it is them.
 *
 * Either way the member gets the pending member's role (claim only),
 * groups and zones, and the 小組 their zones name (#85; a self-host 小組長
 * leading them); the rosters that pointed at the pending member point at
 * them, and the pending member and its index entry are deleted.
 */
/** Pending members waiting for the caller, in open churches. */
export async function pendingClaims(deps: ClaimDeps, caller: Caller | null) {
  const c = requireCaller(caller);
  const keys = await callerKeys(deps, c);
  const claims = [];
  // Each pending member is under one email, so under one key at most.
  for (const [cid, pid] of (await Promise.all(keys.map((k) => waitingFor(deps, k)))).flat()) {
    const [church, pending, member] = await Promise.all([
      deps.db.doc(`churches/${cid}`).get(),
      deps.db.doc(`churches/${cid}/pendingMembers/${pid}`).get(),
      deps.db.doc(`churches/${cid}/members/${c.uid}`).get(),
    ]);
    if (!isChurchOpen(church) || !pending.exists || !waitsFor(pending, keys)) continue;
    // Said yes already: the pending member goes once the rosters point at them.
    if (member.get('claimedFrom') === pid) continue;
    claims.push({ churchId: cid, churchName: church.get('name') as string, pendingId: pid, name: pending.get('name') as string, serves: await servesOf(deps, church, pending) });
  }
  // By name: a pending member with no email to claim it with, in a church the
  // caller is in under that very name, and the only one so named (else the
  // admin merges). The church let them in; the name says which one is theirs.
  for (const m of (await deps.db.collectionGroup('members').where('uid', '==', c.uid).get()).docs) {
    const cid = m.ref.parent.parent!.id;
    const name = personName(m.get('name'));
    if (!name) continue;
    const [church, named] = await Promise.all([
      deps.db.doc(`churches/${cid}`).get(),
      deps.db.collection(`churches/${cid}/pendingMembers`).where('name', '==', name).get(),
    ]);
    const unclaimed = named.docs.filter((p) => !p.get('emailHash'));
    if (!isChurchOpen(church) || unclaimed.length !== 1 || m.get('claimedFrom') === unclaimed[0].id) continue;
    claims.push({ churchId: cid, churchName: church.get('name') as string, pendingId: unclaimed[0].id, name, byName: true, serves: await servesOf(deps, church, unclaimed[0]) });
  }
  return { claims };
}

/** One line of what a pending member serves: a day on a roster, or (no day) a duty they are down for. */
type Serve = { dateKey?: string; service: string; duty: string };

/**
 * A few of [pending]'s duties, for whoever is asked to know them by: their
 * next three days on the rosters, or with none ahead the last three; with no
 * days at all, the duties of the services they are in.
 */
async function servesOf(deps: Deps, church: FirebaseFirestore.DocumentSnapshot, pending: FirebaseFirestore.DocumentSnapshot): Promise<Serve[]> {
  const cid = church.id;
  const pid = pending.id;
  const settings = await deps.db.doc(`churches/${cid}/settings/services`).get();
  const services = new Map(
    ((settings.get('services') as { id?: unknown; name?: unknown }[] | undefined) ?? [])
      .filter((s) => typeof s?.id === 'string')
      .map((s) => [s.id as string, typeof s.name === 'string' ? s.name : '']),
  );
  const today = dateKeyIn(timeZoneOf(church), deps.now());
  // A moved roster's ID starts with its day; the ones with none aren't from the move.
  const days = ((pending.get('rosterIds') as unknown[] | undefined) ?? [])
    .filter((id): id is string => typeof id === 'string' && /^\d{4}-\d{2}-\d{2}_/.test(id))
    .sort();
  const ahead = days.filter((id) => id.slice(0, 10) >= today);
  const order = ahead.length ? ahead : days.reverse();
  const serves: Serve[] = [];
  // A day may have been changed since: read a few more than shown.
  for (let i = 0; i < order.length && i < 12 && serves.length < 3; i += 6) {
    for (const r of await deps.db.getAll(...order.slice(i, i + 6).map((id) => deps.db.doc(`churches/${cid}/rosters/${id}`)))) {
      const duty = ((r.get('duties') as { role?: unknown; uids?: Record<string, unknown> }[] | undefined) ?? [])
        .find((d) => Object.values(d?.uids ?? {}).includes(pid));
      if (!r.exists || r.get('cancelledAt') !== undefined || typeof duty?.role !== 'string' || serves.length >= 3) continue;
      serves.push({ dateKey: r.id.slice(0, 10), service: services.get(r.get('type') as string) ?? '', duty: duty.role });
    }
  }
  if (serves.length) return serves;
  return ((pending.get('zones') as { serviceType?: unknown; duties?: unknown }[] | undefined) ?? [])
    .flatMap((z) => (Array.isArray(z?.duties) ? z.duties : [])
      .filter((d): d is string => typeof d === 'string')
      .map((duty) => ({ service: services.get(z.serviceType as string) ?? '', duty })))
    .slice(0, 3);
}

/** Whether [member] may take [pending] by name: it has no email, and their names are the same. */
const takesByName = (member: FirebaseFirestore.DocumentSnapshot, pending: FirebaseFirestore.DocumentSnapshot) =>
  member.exists && !pending.get('emailHash') && !!personName(member.get('name')) && personName(member.get('name')) === personName(pending.get('name'));

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

/**
 * Old permission groups as 身分 (#82): calendar-editors is folded into 行政
 * (both groups); roster-editors alone, which in self-host edited only the
 * rosters of their 牧區, makes them 負責人 of the services they are in.
 * Used when a pending member joins, and by scripts/migrate-leads.ts.
 */
export function claimedGroups(groups: unknown, zoneTypes: unknown): Identity[] {
  const held = Array.isArray(groups) ? groups.filter((g): g is string => typeof g === 'string') : [];
  const types = Array.isArray(zoneTypes) ? zoneTypes.filter((t): t is string => typeof t === 'string') : [];
  if (held.includes('calendar-editors')) return [{ kind: 'office' }];
  return held.includes('roster-editors') ? types.map((service) => ({ kind: 'lead', service })) : [];
}

function mergedMember(member: FirebaseFirestore.DocumentSnapshot, pending: FirebaseFirestore.DocumentSnapshot, byName: Map<string, string>) {
  // Their old role is not taken over, but leading a 小組 is a 身分.
  const small = claimedSmallGroups(pending.get('zones'), pending.get('role'), byName);
  return {
    ...withIdentities(member.data()!, [
      ...identitiesOf(member.data()!),
      ...claimedGroups(pending.get('groups'), pending.get('zoneTypes')),
      ...small.identities,
    ]),
    smallGroups: union(member.get('smallGroups'), small.smallGroups),
    zones: mergeZones(member.get('zones'), pending.get('zones')),
    zoneTypes: union(member.get('zoneTypes'), pending.get('zoneTypes')),
    // Merge opt-outs, never reset a current preference to a pending default.
    // Updating this field alone also preserves any other current preferences.
    'notificationPrefs.muted': union(member.get('notificationPrefs.muted'), pending.get('notificationPrefs.muted')),
  };
}

/**
 * Joins the caller to the church as the pending member with one of their
 * emails, or, one with no email, merges it into them by name ([pendingClaims]).
 */
export async function claimPending(deps: ClaimDeps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const pid = id((data as { pendingId?: unknown })?.pendingId);
  const keys = await callerKeys(deps, c);
  // Not a member yet, most likely: anyone signed in, but the church open.
  const { cid } = await churchAccess(deps, c, data, 'anyone');
  const pending = await deps.db.runTransaction(async (tx) => {
    const [church, member, pending] = await tx.getAll(
      deps.db.doc(`churches/${cid}`),
      deps.db.doc(`churches/${cid}/members/${c.uid}`),
      deps.db.doc(`churches/${cid}/pendingMembers/${pid}`),
    );
    const byName = smallGroupsByName((await tx.get(deps.db.collection(`churches/${cid}/smallGroups`))).docs);
    if (!isChurchOpen(church)) churchClosed();
    if (!pending.exists) {
      // Claimed already (a double tap, a retry): fine if it was by them.
      if (member.exists) return null;
      fail('not-found', 'notFound');
    }
    if (!waitsFor(pending, keys) && !takesByName(member, pending)) {
      if (!keys.length) fail('failed-precondition', 'unverifiedEmail');
      fail('permission-denied', 'permissionDenied');
    }
    if (member.exists) {
      // Read current preferences in the transaction: concurrent edits are kept.
      tx.update(member.ref, { ...mergedMember(member, pending, byName), claimedFrom: pid });
    } else {
      const role = pending.get('role') ?? 'member';
      const small = claimedSmallGroups(pending.get('zones'), role, byName);
      tx.create(member.ref, {
        uid: c.uid,
        name: personName(pending.get('name')) || personName(c.name),
        email: c.email ?? '',
        ...withIdentities({ role }, [
          ...identitiesOf({ role }),
          ...claimedGroups(pending.get('groups'), pending.get('zoneTypes')),
          ...small.identities,
        ]),
        smallGroups: small.smallGroups,
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
    const byName = smallGroupsByName((await tx.get(deps.db.collection(`churches/${cid}/smallGroups`))).docs);
    if (!admin.exists) fail('permission-denied', 'permissionDenied');
    if (!isChurchOpen(church)) churchClosed();
    if (admin.get('role') !== 'admin') fail('permission-denied', 'permissionDenied');
    if (!pending.exists || !member.exists) fail('not-found', 'notFound');
    tx.update(member.ref, mergedMember(member, pending, byName));
    return pending;
  });
  await repoint(deps, cid, pid, uid, (pending.get('rosterIds') as string[] | undefined) ?? []);
  await dropPending(deps, cid, pending);
  return {};
}
