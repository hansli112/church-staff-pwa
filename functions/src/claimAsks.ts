import { churchAccess } from './access.js';
import { mergeInto, servesOf, type Serve } from './claim.js';
import { fail, id, record, serverTime, type Caller, type Deps } from './common.js';
import { adminUids, notifyMembers, type PushDeps } from './push.js';

/**
 * 認領申請: someone who joined and is in no service yet says which of the
 * church's 同工 without an account they are, when their names differ (the
 * same name is asked of them in claim.ts, pendingClaims); an admin says
 * yes, which merges the two, or no.
 *
 * churches/{cid}/claimAsks/{uid}: `uid`, `name` (theirs), `pendingId`,
 * `pendingName`, `at`. One each; asking again replaces it. Only the
 * backend writes; the admins and the one asking read (firestore.rules).
 */

const askOf = (deps: Pick<Deps, 'db'>, cid: string, uid: string) => deps.db.doc(`churches/${cid}/claimAsks/${uid}`);

/**
 * The church's 同工 without an account, for a member to find themself
 * among: each one's name, 小組 and a few of their duties. No emails.
 */
export async function claimCandidates(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid, church } = await churchAccess(deps, caller, data, 'member');
  const [pending, groups] = await Promise.all([
    deps.db.collection(`churches/${cid}/pendingMembers`).get(),
    deps.db.collection(`churches/${cid}/smallGroups`).get(),
  ]);
  const groupName = new Map(groups.docs.map((g) => [g.id, String(g.get('name') ?? '')]));
  const candidates: { pendingId: string; name: string; smallGroups: string[]; serves: Serve[] }[] = [];
  for (const p of pending.docs) {
    const name = String(p.get('name') ?? '').trim();
    if (!name) continue;
    const named = ((p.get('zones') as { smallGroups?: unknown }[] | undefined) ?? [])
      .flatMap((z) => (Array.isArray(z?.smallGroups) ? z.smallGroups : []))
      .filter((n): n is string => typeof n === 'string');
    const byId = ((p.get('smallGroups') as unknown[] | undefined) ?? [])
      .map((g) => (typeof g === 'string' ? groupName.get(g) : undefined))
      .filter((n): n is string => !!n);
    candidates.push({ pendingId: p.id, name, smallGroups: [...new Set([...byId, ...named])], serves: await servesOf(deps, church, p) });
  }
  return { candidates };
}

/**
 * The caller says they are pending member [pendingId] (a string), or takes
 * back what they said (null). The church's admins are told, as of someone
 * joining (memberJoined).
 */
export async function askClaim(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'pendingId'].includes(k))) fail('invalid-argument', 'unknown');
  const { cid, church, member } = await churchAccess(deps, caller, data, 'member');
  const ref = askOf(deps, cid, member.id);
  if (input.pendingId === null) {
    await ref.delete();
    return {};
  }
  const pid = id(input.pendingId);
  const pending = await deps.db.doc(`churches/${cid}/pendingMembers/${pid}`).get();
  if (!pending.exists) fail('not-found', 'notFound');
  const name = String(member.get('name') ?? '');
  const pendingName = String(pending.get('name') ?? '');
  const before = await ref.get();
  await ref.set({ uid: member.id, name, pendingId: pid, pendingName, at: serverTime() });
  if (before.get('pendingId') !== pid) {
    const admins = (await adminUids(deps.db, cid)).filter((u) => u !== member.id);
    await notifyMembers(deps, cid, admins, 'memberJoined', (w) => ({
      title: church.get('name') as string,
      body: w.claimAsked(name, pendingName),
      link: '/me/members',
    }));
  }
  return {};
}

/** An admin answers [uid]'s ask: [allow] merges the pending member they named into them; either way it goes. */
export async function answerClaim(deps: Deps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'uid', 'allow'].includes(k))) fail('invalid-argument', 'unknown');
  const uid = id(input.uid);
  if (typeof input.allow !== 'boolean') fail('invalid-argument', 'unknown');
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'admin');
  const ref = askOf(deps, cid, uid);
  const ask = await ref.get();
  if (!ask.exists) fail('not-found', 'notFound');
  if (input.allow) await mergeInto(deps, cid, c.uid, id(ask.get('pendingId')), uid);
  await ref.delete();
  return {};
}

/** Pending member [pid] of church [cid] is gone (merged, claimed, deleted): asks naming it go too. */
export async function dropAsksFor(deps: Pick<Deps, 'db'>, cid: string, pid: string) {
  const asks = await deps.db.collection(`churches/${cid}/claimAsks`).where('pendingId', '==', pid).get();
  await Promise.all(asks.docs.map((a) => a.ref.delete()));
}
