import { Timestamp, type DocumentSnapshot } from 'firebase-admin/firestore';

import { churchAccess, churchId, isChurchOpen } from './access.js';
import { DAY_MS, fail, requireCaller, serverTime, type Caller, type Deps } from './common.js';
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
 */

/** A request nobody answered is gone after this many days. */
export const JOIN_REQUEST_DAYS = 30;

/** How the caller's request to a church stands, for the church preview. */
export type RequestState = 'pending' | 'rejected' | null;

const requestPath = (cid: string, uid: string) => `churches/${cid}/joinRequests/${uid}`;

/** Whether [church] takes requests: open, and its admin has not turned them off. */
export const takesRequests = (church: DocumentSnapshot) =>
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
 * whoever lets them in, and tells its admins. Asking again while a request
 * stands changes nothing; after a no, it is a new request. Already a
 * member: nothing to ask.
 */
export async function requestToJoin(deps: PushDeps & Deps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const cid = churchId((data as { churchId?: unknown })?.churchId);
  const raw = (data as { note?: unknown })?.note ?? '';
  if (typeof raw !== 'string' || !withinTextLimit(raw.trim(), TEXT_LIMITS.joinNote)) fail('invalid-argument', 'unknown');
  const note = raw.trim();
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
  if (!takesRequests(church)) fail('failed-precondition', 'unknown', 'requestsClosed');
  if (stateOf(deps, request) === 'pending') return {};
  const name = personName(profile.get('name')) || personName(c.name);
  await request.ref.set({
    uid: c.uid,
    name,
    email: c.email ?? '',
    ...(note ? { note } : {}),
    createdAt: Timestamp.fromDate(deps.now()),
  });
  await notifyMembers(deps, cid, await adminUids(db, cid), 'joinRequest', (w) => ({
    title: church.get('name') as string,
    body: w.joinRequested(name || null),
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
  if (typeof input.uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(input.uid)) fail('invalid-argument', 'unknown');
  const uid = input.uid;
  const { cid, church } = await churchAccess(deps, caller, data, 'admin');
  const { db } = deps;
  const requestRef = db.doc(requestPath(cid, uid));
  const memberRef = db.doc(`churches/${cid}/members/${uid}`);
  if (input.allow !== true) {
    const request = await requestRef.get();
    if (request.exists) await requestRef.update({ rejectedAt: Timestamp.fromDate(deps.now()) });
    return {};
  }
  if (!takesRequests(church)) fail('failed-precondition', 'unknown', 'requestsClosed');
  const joined = await db.runTransaction(async (tx) => {
    const [request, member] = await tx.getAll(requestRef, memberRef);
    if (member.exists) {
      tx.delete(requestRef);
      return false;
    }
    if (stateOf(deps, request) !== 'pending') fail('not-found', 'unknown', 'requestGone');
    tx.create(memberRef, {
      uid,
      name: personName(request.get('name')),
      email: request.get('email') ?? '',
      role: 'staff',
      groups: [],
      zones: [],
      zoneTypes: [],
      joinedAt: serverTime(),
    });
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

/** Deletes every request [JOIN_REQUEST_DAYS] days old or older, answered or not. */
export async function forgetOldJoinRequests(deps: Deps) {
  const cutoff = Timestamp.fromMillis(deps.now().getTime() - JOIN_REQUEST_DAYS * DAY_MS);
  const old = await deps.db.collectionGroup('joinRequests').where('createdAt', '<=', cutoff).get();
  await Promise.all(old.docs.map((d) => d.ref.delete()));
  return old.size;
}

/** Deletes every request [uid] made: their account is going. */
export async function forgetJoinRequestsOf(deps: Deps, uid: string) {
  const mine = await deps.db.collectionGroup('joinRequests').where('uid', '==', uid).get();
  await Promise.all(mine.docs.map((d) => d.ref.delete()));
}
