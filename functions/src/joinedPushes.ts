import { FieldValue, Timestamp, type DocumentReference, type DocumentSnapshot } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

import { isChurchOpen } from './access.js';
import type { Deps } from './common.js';
import { adminUids, notifyMembers, type PushDeps } from './push.js';
import { loggable } from './redact.js';
import { quietUntil } from './rosterChange.js';
import { timeZoneOf } from './timeZones.js';

/**
 * Admins hear that someone joined by invite: the first at once, then at
 * most one push an hour, saying how many came since; none from 22:00 to
 * 7:00 on the church's clock. A link posted in a group can bring a dozen
 * in an evening.
 *
 * What waits is at joinedPushes/{cid}, which only the backend reads and
 * writes: `lastAt` (the last push), `first` (the first name since) and
 * `count` (how many since), `sendAt` (when they are told, or null). Sent
 * every 15 minutes (index.ts).
 */
export const JOINED_PUSH_GAP_MS = 60 * 60 * 1000;

/**
 * A run counts as due what falls due within this: its clock read comes
 * before the last push's was written, a few seconds into its own run.
 */
const RUN_SLACK_MS = 60 * 1000;

type JoinedDeps = PushDeps & Pick<Deps, 'now'>;

const pathOf = (cid: string) => `joinedPushes/${cid}`;

async function tellAdmins(deps: JoinedDeps, church: DocumentSnapshot, first: string, count: number) {
  return notifyMembers(deps, church.id, await adminUids(deps.db, church.id), 'memberJoined', (w) => ({
    title: church.get('name') as string,
    body: w.memberJoined(first || null, count),
    link: '/me/members',
  }));
}

/**
 * [name] just joined church [church] by invite: its admins are told now,
 * or it waits with whoever else joins until they are. Returns how many
 * devices it reached.
 */
export async function tellJoined(deps: JoinedDeps, church: DocumentSnapshot, name: string) {
  const now = deps.now();
  const quiet = quietUntil(timeZoneOf(church), now);
  const ref = deps.db.doc(pathOf(church.id));
  const tellNow = await deps.db.runTransaction(async (tx) => {
    const state = await tx.get(ref);
    const last = (state.get('lastAt') as Timestamp | undefined)?.toMillis();
    const count = (state.get('count') as number | undefined) ?? 0;
    if (!quiet && count === 0 && (last === undefined || now.getTime() - last >= JOINED_PUSH_GAP_MS)) {
      tx.set(ref, { cid: church.id, lastAt: Timestamp.fromDate(now), count: 0, sendAt: null }, { merge: true });
      return true;
    }
    const after = Math.max(quiet?.getTime() ?? 0, (last ?? 0) + JOINED_PUSH_GAP_MS);
    tx.set(
      ref,
      {
        cid: church.id,
        ...(count === 0 ? { first: name } : {}),
        count: count + 1,
        sendAt: (state.get('sendAt') as Timestamp | null | undefined) ?? Timestamp.fromMillis(after),
      },
      { merge: true },
    );
    return false;
  });
  return tellNow ? tellAdmins(deps, church, name, 1) : 0;
}

/**
 * Tells the admins of each church whose joins have waited long enough,
 * as one push. Returns how many devices it reached.
 */
export async function sendJoinedPushes(deps: JoinedDeps) {
  const due = Timestamp.fromMillis(deps.now().getTime() + RUN_SLACK_MS);
  const waiting = await deps.db.collection('joinedPushes').where('sendAt', '<=', due).get();
  let sent = 0;
  for (const d of waiting.docs) {
    try {
      sent += await sendWaiting(deps, d.ref, d.get('cid') as string, due);
    } catch (e) {
      // One church failing holds up none of the others.
      logger.error('Joined push failed', { cid: d.get('cid'), error: loggable(e).message });
    }
  }
  return sent;
}

async function sendWaiting(deps: JoinedDeps, ref: DocumentReference, cid: string, due: Timestamp) {
  const church = await deps.db.doc(`churches/${cid}`).get();
  if (!isChurchOpen(church)) {
    await ref.delete();
    return 0;
  }
  const quiet = quietUntil(timeZoneOf(church), deps.now());
  // Taken first, so a run that overlaps this one tells nothing twice.
  const taken = await deps.db.runTransaction(async (tx) => {
    const state = await tx.get(ref);
    const sendAt = state.get('sendAt') as Timestamp | null | undefined;
    if (!sendAt || sendAt.toMillis() > due.toMillis()) return null;
    if (quiet) {
      tx.update(ref, { sendAt: Timestamp.fromDate(quiet) });
      return null;
    }
    tx.update(ref, { lastAt: Timestamp.fromDate(deps.now()), count: 0, first: FieldValue.delete(), sendAt: null });
    return { first: state.get('first') as string, count: state.get('count') as number };
  });
  return taken ? tellAdmins(deps, church, taken.first, taken.count) : 0;
}

/** Forgets church [cid]'s waiting joins: the church is purged. */
export async function forgetJoinedPushes(deps: Pick<Deps, 'db'>, cid: string) {
  await deps.db.doc(pathOf(cid)).delete();
}
