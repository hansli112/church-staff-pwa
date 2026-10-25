import { Timestamp, type DocumentSnapshot } from 'firebase-admin/firestore';

import { churchAccess, churchId, isChurchOpen } from './access.js';
import { DAY_MS, fail, id, requireCaller, type Caller, type Deps } from './common.js';
import { newStaff } from './invites.js';
import { personName, TEXT_LIMITS, withinTextLimit } from './limits.js';
import { adminUids, notifyMembers, type PushDeps } from './push.js';

/**
 * 申請加入 (#88): someone who has a church's URL but no invite asks to
 * join, and an admin lets them in or not. A request lives at
 * churches/{cid}/joinRequests/{uid}, written only here; admins read the
 * church's (firestore.rules). The person who asked learns how it stands
 * from the church preview (church.ts), not by reading it.
 *
 * A church takes requests unless its admin turned them off
 * (`joinRequestsClosed` on the church doc).
 *
 * Its admins hear of one person's requests at most once a day, so asking,
 * taking it back and asking again does not ring them each time: when they
 * last did is at churches/{cid}/joinRequestPushes/{uid}, which only this
 * reads and writes.
 */

/** A request nobody answered is gone after this many days. */
export const JOIN_REQUEST_DAYS = 30;

/** How the caller's request to a church stands, for the church preview. */
export type RequestState = 'pending' | 'rejected' | null;

const requestPath = (cid: string, uid: string) => `churches/${cid}/joinRequests/${uid}`;
const pushedPath = (cid: string, uid: string) => `churches/${cid}/joinRequestPushes/${uid}`;

/** Whether [church] takes requests: open, and its admin has not turned them off. */
export const takesJoinRequests = (church: DocumentSnapshot) =>
  isChurchOpen(church) && church.get('joinRequestsClosed') !== true;

/**
 * How a request asked [ageDays] days ago stands, turned down or not
 * (testdata/church_rules.json, joinRequestState): after
 * [JOIN_REQUEST_DAYS] days it is as if there were none.
 */
export function standing(ageDays: number, rejected: boolean): RequestState {
  if (ageDays >= JOIN_REQUEST_DAYS) return null;
  return rejected ? 'rejected' : 'pending';
}

/** How request [doc] stands now. */
function stateOf(deps: Deps, doc: DocumentSnapshot): RequestState {
  const at = doc.get('createdAt') as Timestamp | undefined;
  if (!doc.exists || at === undefined) return null;
  return standing((deps.now().getTime() - at.toMillis()) / DAY_MS, doc.get('rejectedAt') !== undefined);
}

/** How [uid]'s request to church [cid] stands. */
export async function requestState(deps: Deps, cid: string, uid: string): Promise<RequestState> {
  return stateOf(deps, await deps.db.doc(requestPath(cid, uid)).get());
}

/**
 * Asks to join church `data.churchId`, with an optional `data.note` for
 * whoever lets them in, and tells its admins unless they were told of this
 * person within a day. Asking again while a request stands changes
 * nothing; after a no, it is a new request. Already a member: nothing to
 * ask.
 */
export async function requestToJoin(deps: PushDeps & Deps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const cid = churchId((data as { churchId?: unknown })?.churchId);
  const raw = (data as { note?: unknown })?.note ?? '';
  if (typeof raw !== 'string') fail('invalid-argument', 'unknown');
  const note = raw.trim();
  if (!withinTextLimit(note, TEXT_LIMITS.joinNote)) fail('invalid-argument', 'unknown');
  if (!c.emailVerified) fail('failed-precondition', 'unverifiedEmail');
  const { db } = deps;
  const [church, member, request, profile] = await db.getAll(
    db.doc(`churches/${cid}`),
    db.doc(`churches/${cid}/members/${c.uid}`),
    db.doc(requestPath(cid, c.uid)),
    db.doc(`users/${c.uid}`),
  );
  if (!isChurchOpen(church)) fail('not-found', 'notFound');
  if (member.exists) return {};
  if (!takesJoinRequests(church)) fail('failed-precondition', 'unknown', 'requestsClosed');
  if (stateOf(deps, request) === 'pending') return {};
  const name = personName(profile.get('name')) || personName(c.name);
  await request.ref.set({
    uid: c.uid,
    name,
    email: c.email ?? '',
    ...(note ? { note } : {}),
    createdAt: Timestamp.fromDate(deps.now()),
  });
  // Taken in a transaction: two asks at once ring once.
  const pushedRef = db.doc(pushedPath(cid, c.uid));
  const due = await db.runTransaction(async (tx) => {
    const last = (await tx.get(pushedRef)).get('at') as Timestamp | undefined;
    if (last && deps.now().getTime() - last.toMillis() < DAY_MS) return false;
    tx.set(pushedRef, { uid: c.uid, at: Timestamp.fromDate(deps.now()) });
    return true;
  });
  if (!due) return {};
  await notifyMembers(deps, cid, await adminUids(db, cid), 'joinRequest', (w) => ({
    title: church.get('name') as string,
    body: w.joinRequested(name || null, note),
    link: '/me/members',
  }));
  return {};
}

/** Takes back the caller's request to church `data.churchId`, if there is one. */
export async function withdrawJoinRequest(deps: Deps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const cid = churchId((data as { churchId?: unknown })?.churchId);
  await deps.db.doc(requestPath(cid, c.uid)).delete();
  return {};
}

/**
 * An admin answers `data.uid`'s request to church `data.churchId`: with
 * `data.allow`, they join as an invite would have them (no 身分, no 牧區)
 * and are told; otherwise the request is marked as turned down, which
 * they see on the church URL. A request no longer standing, or one to a
 * church that stopped taking them, cannot be let in.
 */
export async function answerJoinRequest(deps: PushDeps & Deps, caller: Caller | null, data: unknown) {
  const input = (data ?? {}) as { uid?: unknown; allow?: unknown };
  const uid = id(input.uid);
  const { cid, church } = await churchAccess(deps, caller, data, 'admin');
  const { db } = deps;
  const requestRef = db.doc(requestPath(cid, uid));
  const memberRef = db.doc(`churches/${cid}/members/${uid}`);
  if (input.allow !== true) {
    // Only the request they turned down: not one taken back, nor asked anew, meanwhile.
    await db.runTransaction(async (tx) => {
      if (stateOf(deps, await tx.get(requestRef)) === 'pending') tx.update(requestRef, { rejectedAt: Timestamp.fromDate(deps.now()) });
    });
    return {};
  }
  if (!takesJoinRequests(church)) fail('failed-precondition', 'unknown', 'requestsClosed');
  const joined = await db.runTransaction(async (tx) => {
    const [request, member] = await tx.getAll(requestRef, memberRef);
    if (member.exists) {
      tx.delete(requestRef);
      return false;
    }
    if (stateOf(deps, request) !== 'pending') fail('not-found', 'unknown', 'requestGone');
    tx.create(memberRef, newStaff(uid, personName(request.get('name')), request.get('email') ?? ''));
    tx.delete(requestRef);
    return true;
  });
  if (joined) {
    await notifyMembers(deps, cid, [uid], 'joinRequest', (w) => ({
      title: church.get('name') as string,
      body: w.joinAllowed,
      link: '/home',
    }));
  }
  return {};
}

/**
 * Deletes every request [JOIN_REQUEST_DAYS] days old or older, answered or
 * not, and when admins were told of someone over a day ago. Returns how
 * many requests.
 */
export async function forgetOldJoinRequests(deps: Deps) {
  const now = deps.now().getTime();
  const [old, pushed] = await Promise.all([
    deps.db.collectionGroup('joinRequests').where('createdAt', '<=', Timestamp.fromMillis(now - JOIN_REQUEST_DAYS * DAY_MS)).get(),
    deps.db.collectionGroup('joinRequestPushes').where('at', '<=', Timestamp.fromMillis(now - DAY_MS)).get(),
  ]);
  await Promise.all([...old.docs, ...pushed.docs].map((d) => d.ref.delete()));
  return old.size;
}

/** Deletes every request [uid] made, and when admins were told: their account is going. */
export async function forgetJoinRequestsOf(deps: Deps, uid: string) {
  const [mine, pushed] = await Promise.all(
    ['joinRequests', 'joinRequestPushes'].map((g) => deps.db.collectionGroup(g).where('uid', '==', uid).get()),
  );
  await Promise.all([...mine.docs, ...pushed.docs].map((d) => d.ref.delete()));
}
