import { Timestamp } from 'firebase-admin/firestore';

import { dateKeyUtc8, serverTime, type Deps } from './common.js';

/** A roster's `via` when the backend changed it, not someone. */
export const BY_THE_BACKEND = new Set(['calendar', 'relink', 'restore', 'timeZone', 'import']);

/**
 * Writes stats/{date} for the day before [deps.now()] (UTC+8). Uses set(),
 * so running twice for a day replaces the snapshot instead of adding to it.
 */
export async function writeDailyStats(deps: Deps) {
  const { db } = deps;
  const now = deps.now();
  const date = dateKeyUtc8(new Date(now.getTime() - 86400e3));
  // The UTC+8 day [date 00:00, +24h).
  const start = new Date(`${date}T00:00:00+08:00`);
  const end = new Date(start.getTime() + 86400e3);

  const count = async (q: FirebaseFirestore.Query) => (await q.count().get()).data().count;
  const churches = db.collection('churches');
  // The 7 days to [date]: who opened the app (users/{uid}.seenOn, the
  // UTC+8 day the app last wrote), and the churches where someone changed
  // a roster: not the backend following Google Calendar, a time zone, an
  // undo of a delete or a move from the old app ([BY_THE_BACKEND]).
  const weekStart = new Date(start.getTime() - 6 * 86400e3);
  const changed = db.collectionGroup('rosters')
    .where('updatedAt', '>=', Timestamp.fromDate(weekStart))
    .where('updatedAt', '<', Timestamp.fromDate(end))
    .select('via')
    .get()
    .then((q) => new Set(q.docs.filter((d) => !BY_THE_BACKEND.has(d.get('via'))).map((d) => d.ref.parent.parent!.id)).size);
  const [users, active, suspended, deleted, members, rosters, seen, editing] = await Promise.all([
    count(db.collection('users')),
    count(churches.where('status', '==', 'active')),
    count(churches.where('status', '==', 'suspended')),
    count(churches.where('status', '==', 'deleted')),
    count(db.collectionGroup('members')),
    count(db.collectionGroup('rosters')),
    count(db.collection('users').where('seenOn', '>=', dateKeyUtc8(weekStart)).where('seenOn', '<=', date)),
    changed,
  ]);
  const snapshot = {
    date,
    users,
    churches_active: active,
    churches_suspended: suspended,
    churches_deleted: deleted,
    members,
    rosters,
    users_active_7d: seen,
    churches_editing_7d: editing,
    computedAt: serverTime(),
  };
  await db.doc(`stats/${date}`).set(snapshot);
  return snapshot;
}
