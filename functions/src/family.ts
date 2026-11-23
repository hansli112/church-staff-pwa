import type { DocumentReference, DocumentSnapshot, Transaction } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { fail, id, record, strings, type Caller, type Deps } from './common.js';
import { notifyMembers, type NotificationKind, type PushDeps, type PushMessage } from './push.js';
import type { Words } from './languages.js';

/**
 * 家人: churches/{cid}/households/{id}, people of one church who see each
 * other's serving, and hear about those of them without an account (小孩
 * without a phone).
 *
 * - `people`: uids and pending member IDs (沒有帳號的同工) in it;
 * - `noAccount`: those of [people] without an account;
 * - `invited`: uids asked to join and not answered yet; `invitedBy`: who
 *   asked each;
 * - `names`: everyone's name in it, as the church has it, for those who
 *   cannot read the member list.
 *
 * Someone without an account is added at once; someone with one is asked
 * (a push, and a row on their 首頁), and once they accept, the family they
 * had joins this one. Only the backend writes; those in it or asked read
 * (firestore.rules).
 */

interface Household {
  people: string[];
  noAccount: string[];
  invited: string[];
  invitedBy: Record<string, string>;
  names: Record<string, string>;
}

const households = (deps: Pick<Deps, 'db'>, cid: string) => deps.db.collection(`churches/${cid}/households`);

function read(doc: DocumentSnapshot): Household {
  return {
    people: strings(doc.get('people')),
    noAccount: strings(doc.get('noAccount')),
    invited: strings(doc.get('invited')),
    invitedBy: { ...((doc.get('invitedBy') as Record<string, string> | undefined) ?? {}) },
    names: { ...((doc.get('names') as Record<string, string> | undefined) ?? {}) },
  };
}

/** [h] without [who]: out of it, or no longer asked. */
function without(h: Household, who: string): Household {
  // Asks [who] made go with them: nobody would be named as asking.
  const gone = new Set([who, ...h.invited.filter((p) => h.invitedBy[p] === who)]);
  const names = Object.fromEntries(Object.entries(h.names).filter(([p]) => p !== who && (!gone.has(p) || h.people.includes(p))));
  const invitedBy = Object.fromEntries(Object.entries(h.invitedBy).filter(([p]) => !gone.has(p)));
  return {
    people: h.people.filter((p) => p !== who),
    noAccount: h.noAccount.filter((p) => p !== who),
    invited: h.invited.filter((p) => !gone.has(p)),
    invitedBy,
    names,
  };
}

/** Whether [h] is a family still: someone with an account in it, and someone besides. */
const lasts = (h: Household) =>
  h.people.some((p) => !h.noAccount.includes(p)) && h.people.length + h.invited.length > 1;

/** Writes [h] at [ref] in [tx], or deletes it when it is no family any more. */
function put(tx: Transaction, ref: DocumentReference, h: Household) {
  if (lasts(h)) tx.set(ref, h);
  else tx.delete(ref);
}

/** The households [who] is in. */
const ofPerson = (tx: Transaction, deps: Pick<Deps, 'db'>, cid: string, who: string) =>
  tx.get(households(deps, cid).where('people', 'array-contains', who));

const nameOf = (d: DocumentSnapshot) => String(d.get('name') ?? '').trim();

/**
 * 加入家人: the caller adds `data.id`, anyone else in the church, to their
 * family, making one if they have none. One without an account is in at
 * once; one with an account is asked, with a push.
 */
export async function addFamily(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'id'].includes(k))) fail('invalid-argument', 'unknown');
  const who = id(input.id);
  const { cid, caller: c, church, member: me } = await churchAccess(deps, caller, data, 'member');
  if (who === c.uid) fail('invalid-argument', 'unknown');
  const root = deps.db.doc(`churches/${cid}`);
  const asked = await deps.db.runTransaction(async (tx) => {
    const [member, pending] = await tx.getAll(root.collection('members').doc(who), root.collection('pendingMembers').doc(who));
    if (!member.exists && !pending.exists) fail('not-found', 'notFound');
    const mine = await ofPerson(tx, deps, cid, c.uid);
    if (mine.docs.some((d) => [...read(d).people, ...read(d).invited].includes(who))) return false;
    const ref = mine.docs[0]?.ref ?? households(deps, cid).doc();
    const h: Household = mine.docs[0]
      ? read(mine.docs[0])
      : { people: [c.uid], noAccount: [], invited: [], invitedBy: {}, names: { [c.uid]: nameOf(me) } };
    if (member.exists) {
      h.invited.push(who);
      h.invitedBy[who] = c.uid;
      h.names[who] = nameOf(member);
    } else {
      h.people.push(who);
      h.noAccount.push(who);
      h.names[who] = nameOf(pending);
    }
    tx.set(ref, h);
    return member.exists;
  });
  if (asked) {
    const name = nameOf(me);
    await notifyMembers(deps, cid, [who], 'swap', (w) => ({ title: church.get('name') as string, body: w.familyAsked(name), link: '/home' }));
  }
  return {};
}

/**
 * The caller answers being asked into household `data.householdId`:
 * `data.yes` joins it, and the family they had joins it too; no leaves it.
 */
export async function answerFamily(deps: Deps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'householdId', 'yes'].includes(k)) || typeof input.yes !== 'boolean') {
    fail('invalid-argument', 'unknown');
  }
  const hid = id(input.householdId);
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'member');
  await deps.db.runTransaction(async (tx) => {
    const ref = households(deps, cid).doc(hid);
    const doc = await tx.get(ref);
    if (!doc.exists || !read(doc).invited.includes(c.uid)) fail('not-found', 'notFound');
    const mine = (await ofPerson(tx, deps, cid, c.uid)).docs.filter((d) => d.id !== hid);
    const h = read(doc);
    if (!input.yes) return put(tx, ref, without(h, c.uid));
    const joined: Household = { ...without(h, c.uid), names: h.names };
    joined.people.push(c.uid);
    for (const other of mine) {
      const o = read(other);
      for (const p of o.people) if (!joined.people.includes(p)) joined.people.push(p);
      for (const p of o.noAccount) if (!joined.noAccount.includes(p)) joined.noAccount.push(p);
      for (const p of o.invited) {
        if (joined.people.includes(p) || joined.invited.includes(p)) continue;
        joined.invited.push(p);
        joined.invitedBy[p] = o.invitedBy[p];
      }
      joined.names = { ...o.names, ...joined.names };
      tx.delete(other.ref);
    }
    joined.invited = joined.invited.filter((p) => !joined.people.includes(p));
    for (const p of Object.keys(joined.invitedBy)) if (!joined.invited.includes(p)) delete joined.invitedBy[p];
    tx.set(ref, joined);
  });
  return {};
}

/**
 * 移出 (or 收回, for one asked): `data.id` out of the caller's family. The
 * caller themself leaves it. What is left of one is no family.
 */
export async function removeFamily(deps: Deps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'id'].includes(k))) fail('invalid-argument', 'unknown');
  const who = id(input.id);
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'member');
  await deps.db.runTransaction(async (tx) => {
    for (const d of (await ofPerson(tx, deps, cid, c.uid)).docs) put(tx, d.ref, without(read(d), who));
  });
  return {};
}

/** Everyone in the church but the caller, to add as family: names, and whether each has an account. No emails. */
export async function familyCandidates(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'member');
  const [members, pending] = await Promise.all([
    deps.db.collection(`churches/${cid}/members`).get(),
    deps.db.collection(`churches/${cid}/pendingMembers`).get(),
  ]);
  const people = [
    ...members.docs.filter((m) => m.id !== c.uid).map((m) => ({ id: m.id, name: nameOf(m), account: true })),
    ...pending.docs.map((p) => ({ id: p.id, name: nameOf(p), account: false })),
  ].filter((p) => p.name);
  return { people };
}

/** For each household [who] is in, one transaction's change [change] of it. */
async function eachHousehold(deps: Pick<Deps, 'db'>, cid: string, who: string, change: (h: Household) => Household) {
  const q = await households(deps, cid).where('people', 'array-contains', who).get();
  const asked = await households(deps, cid).where('invited', 'array-contains', who).get();
  for (const ref of new Set([...q.docs, ...asked.docs].map((d) => d.ref.path))) {
    await deps.db.runTransaction(async (tx) => {
      const doc = await tx.get(deps.db.doc(ref));
      if (doc.exists) put(tx, doc.ref, change(read(doc)));
    });
  }
}

/** [who] left the church, or was deleted: out of every family. */
export const leaveFamilies = (deps: Pick<Deps, 'db'>, cid: string, who: string) =>
  eachHousehold(deps, cid, who, (h) => without(h, who));

/** Pending member [pid] is member [uid] now, called [name]: their families keep them, with an account. */
export const repointFamily = (deps: Pick<Deps, 'db'>, cid: string, pid: string, uid: string, name: string) =>
  eachHousehold(deps, cid, pid, (h) => {
    const next = without(h, pid);
    if (!next.people.includes(uid)) next.people.push(uid);
    // Asked already, they are in now.
    next.invited = next.invited.filter((p) => p !== uid);
    delete next.invitedBy[uid];
    next.names[uid] = name || h.names[pid] || '';
    return next;
  });

/** [who] is called [name] now, in their families too. */
export const renameInFamilies = (deps: Pick<Deps, 'db'>, cid: string, who: string, name: string) =>
  eachHousehold(deps, cid, who, (h) => ({ ...h, names: { ...h.names, [who]: name } }));

/**
 * The family of each of [ids] without an account: their name, and the uids
 * of those with an account in their households, who hear about them.
 */
export async function familiesOf(deps: Pick<Deps, 'db'>, cid: string, ids: string[]) {
  const out = new Map<string, { name: string; to: string[] }>();
  for (let i = 0; i < ids.length; i += 30) {
    const q = await households(deps, cid).where('noAccount', 'array-contains-any', ids.slice(i, i + 30)).get();
    for (const d of q.docs) {
      const h = read(d);
      for (const kid of h.noAccount) {
        if (!ids.includes(kid)) continue;
        const was = out.get(kid);
        const to = h.people.filter((p) => !h.noAccount.includes(p));
        out.set(kid, { name: was?.name || h.names[kid] || '', to: [...new Set([...(was?.to ?? []), ...to])] });
      }
    }
  }
  return out;
}

/**
 * Tells [about] (a uid, or a pending member's ID) [message]: themself, if
 * they have an account, else their families, by their name ([message]'s
 * second argument; null for themself). [except] hears nothing (who made
 * the change). Returns how many devices it reached.
 */
export async function notifyAbout(
  deps: PushDeps,
  cid: string,
  about: string,
  kind: NotificationKind,
  message: (w: Words, name: string | null) => PushMessage,
  except?: string,
  /** [about]'s family, when the caller looked it up already ([familiesOf]); none is looked up. */
  known?: { name: string; to: string[] } | null,
) {
  let sent = 0;
  if (about !== except) sent += await notifyMembers(deps, cid, [about], kind, (w) => message(w, null));
  const family = known === undefined ? (await familiesOf(deps, cid, [about])).get(about) : known;
  if (family) {
    const to = family.to.filter((u) => u !== except);
    sent += await notifyMembers(deps, cid, to, kind, (w) => message(w, family.name));
  }
  return sent;
}
