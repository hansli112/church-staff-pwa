import { Timestamp, type Firestore, type Query } from 'firebase-admin/firestore';

import { DAY_MS, type Deps } from './common.js';

/** How long a notification stays in its person's 通知列表 (#89). */
export const NOTIFICATION_DAYS = 30;

/**
 * users/{uid}/notifications: every push sent to [uid] (`cid`, `kind`,
 * `title`, `body`, `link`, `at`), also those of kinds they muted. Only they
 * read it; only the backend writes it.
 */
export const notificationsOf = (db: Firestore, uid: string) => db.collection(`users/${uid}/notifications`);

/**
 * How many of [items] are unread: sent after their church's list was last
 * seen ([seen], by church, in ms; never seen: all of it). Matches
 * unreadNotifications in app/lib/domain/models.dart
 * (testdata/church_rules.json).
 */
export function unreadCount(items: { cid: string; at: number }[], seen: Record<string, number>) {
  return items.filter((n) => n.at > (seen[n.cid] ?? -Infinity)).length;
}

/** users/{uid}.notificationsSeenAt, {cid: the newest notification seen there}, in ms. */
function seenOf(raw: unknown): Record<string, number> {
  if (typeof raw !== 'object' || raw === null) return {};
  return Object.fromEntries(
    Object.entries(raw).flatMap(([cid, at]) => (at instanceof Timestamp ? [[cid, at.toMillis()]] : [])),
  );
}

/** What is unread in all of [uid]'s churches together: the number on the app icon. */
export async function unreadOf(db: Firestore, uid: string, seenAt: unknown) {
  const q = await notificationsOf(db, uid).select('cid', 'at').get();
  const items = q.docs.flatMap((d) => {
    const at = d.get('at') as unknown;
    return at instanceof Timestamp ? [{ cid: d.get('cid') as string, at: at.toMillis() }] : [];
  });
  return unreadCount(items, seenOf(seenAt));
}

/** Deletes every notification [NOTIFICATION_DAYS] days old or older. Returns how many. Daily (index.ts). */
export function forgetOldNotifications(deps: Deps) {
  return deleteAll(
    deps.db,
    deps.db
      .collectionGroup('notifications')
      .where('at', '<=', Timestamp.fromMillis(deps.now().getTime() - NOTIFICATION_DAYS * DAY_MS)),
  );
}

/** Deletes [uid]'s notifications from church [cid]: they are no longer in it. Returns how many. */
export function forgetNotificationsFrom(db: Firestore, uid: string, cid: string) {
  return deleteAll(db, notificationsOf(db, uid).where('cid', '==', cid));
}

async function deleteAll(db: Firestore, query: Query) {
  const q = await query.get();
  const writer = db.bulkWriter();
  for (const d of q.docs) void writer.delete(d.ref);
  await writer.close();
  return q.size;
}
