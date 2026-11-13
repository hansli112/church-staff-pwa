import type { Deps } from './common.js';

/**
 * Someone renamed: the rosters that name them, and the staff orders that
 * rank them, both of which hold names, not IDs.
 */

/** A roster duty as stored: the names shown, and those of members (or pending members) to their IDs. */
export type DutyDoc = { people?: string[]; uids?: Record<string, string> };

/**
 * Rewrites, with [change], each duty of every roster that names [id]: the
 * days [recorded] for them (a move's), and any they were put on since.
 * Every roster of the church is read for those, once a person. [change]
 * gives back the duty itself when nothing is to change.
 */
export async function rewriteDutiesOf(deps: Deps, cid: string, id: string, recorded: string[], change: (d: DutyDoc) => DutyDoc) {
  const all = await deps.db.collection(`churches/${cid}/rosters`).get();
  const since = all.docs
    .filter((r) => ((r.get('duties') as DutyDoc[] | undefined) ?? [])
      .some((d) => Object.values(d?.uids ?? {}).includes(id)))
    .map((r) => r.id);
  const rosterIds = [...new Set([...recorded, ...since])];
  // One transaction per day, a few at a time: an editor changing the same
  // day meanwhile is never overwritten.
  const one = (rosterId: string) =>
    deps.db.runTransaction(async (tx) => {
      const ref = deps.db.doc(`churches/${cid}/rosters/${rosterId}`);
      const s = await tx.get(ref);
      const duties = s.get('duties') as DutyDoc[] | undefined;
      if (!s.exists || !Array.isArray(duties)) return;
      const next = duties.map(change);
      if (next.some((d, i) => d !== duties[i])) tx.update(ref, { duties: next });
    });
  for (let i = 0; i < rosterIds.length; i += 10) await Promise.all(rosterIds.slice(i, i + 10).map(one));
}

/**
 * [d] with [id]'s name now [name], where it was in `people` and in `uids`
 * (as Duty.renamed in the app); [d] itself when it is that already.
 */
export function renamedDuty(d: DutyDoc, id: string, name: string): DutyDoc {
  const old = new Set(Object.entries(d.uids ?? {}).filter(([n, u]) => u === id && n !== name).map(([n]) => n));
  if (old.size === 0) return d;
  return {
    ...d,
    people: [...new Set((d.people ?? []).map((p) => (old.has(p) ? name : p)))],
    uids: Object.fromEntries(Object.entries(d.uids ?? {}).map(([n, u]) => [old.has(n) ? name : n, u])),
  };
}

/**
 * [id] (a member's uid, or a pending member's ID) of church [cid], once
 * [old], is [name] now: every roster naming them says [name], the days
 * [recorded] for them too, and every staff order ranking [old] ranks
 * [name] in its place. Safe to run again.
 */
export async function renameInChurch(deps: Deps, cid: string, id: string, old: string, name: string, recorded: string[] = []) {
  await rewriteDutiesOf(deps, cid, id, recorded, (d) => renamedDuty(d, id, name));
  if (!old || old === name) return;
  const orders = await deps.db.collection(`churches/${cid}/staff_orders`).get();
  await Promise.all(
    orders.docs
      .filter((o) => Object.values((o.get('roles') as Record<string, unknown> | undefined) ?? {}).some((l) => Array.isArray(l) && l.includes(old)))
      .map((o) =>
        deps.db.runTransaction(async (tx) => {
          const s = await tx.get(o.ref);
          const roles = (s.get('roles') as Record<string, unknown> | undefined) ?? {};
          const next = Object.fromEntries(
            Object.entries(roles).map(([role, l]) => [role, Array.isArray(l) ? [...new Set(l.map((n) => (n === old ? name : n)))] : l]),
          );
          tx.update(o.ref, { roles: next });
        }),
      ),
  );
}
