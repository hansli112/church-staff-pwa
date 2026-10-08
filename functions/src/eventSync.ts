import { FieldValue, Timestamp, type QueryDocumentSnapshot } from 'firebase-admin/firestore';

import { isChurchOpen } from './access.js';
import { calendarAccess, eventRosterDays, fromEvent, type CalDeps, type CalendarEvent } from './calendar.js';
import { DAY_MS, dateKeyUtc8 } from './common.js';

/**
 * Events' rosters (活動的服事表) against the calendar, for what was done in
 * Google Calendar itself; calendarWrite already takes the roster along with
 * a change made in the app. Run a few times a day and before the evening
 * reminders. For each roster still to come, or cancelled:
 *
 * - The event changed: the roster takes its title and days, and a move is
 *   told (rosterChange.ts).
 * - The event was deleted: the roster is cancelled, as when deleted in the
 *   app. Back within 30 days (Google's trash), it is on again.
 * - A day of a recurring event got a new id (a "this and following" edit,
 *   or the whole series moved): the roster moves to it.
 * - Cancelled for over 30 days: deleted.
 *
 * Only an event read from the calendar the roster was made on counts as
 * deleted. Another calendar picked since, a grant revoked or Google out of
 * reach only leave the roster as it is until the next run.
 */

/** How long a cancelled roster is kept: for undo, and Google's trash. */
export const CANCELLED_KEEP_DAYS = 30;

export interface SyncCounts {
  checked: number;
  updated: number;
  cancelled: number;
  restored: number;
  relinked: number;
  purged: number;
}

/** The UTC+8 day of an event start as Google gives it, an all-day date or an instant. */
const dayOf = (start: string) => (/^\d{4}-\d{2}-\d{2}$/.test(start) ? start : dateKeyUtc8(new Date(start)));

/** The series id a recurring event keeps when it is split ("this and following" adds `_R<date>`). */
const seriesOf = (id: string) => id.split('_R')[0];

export async function syncEventRosters(deps: CalDeps): Promise<SyncCounts> {
  const counts: SyncCounts = { checked: 0, updated: 0, cancelled: 0, restored: 0, relinked: 0, purged: 0 };
  const today = dateKeyUtc8(deps.now());
  const [ahead, cancelled] = await Promise.all([
    deps.db.collectionGroup('rosters').where('endDateKey', '>=', today).get(),
    deps.db.collectionGroup('rosters').where('cancelledAt', '>', Timestamp.fromMillis(0)).get(),
  ]);
  const byChurch = new Map<string, Map<string, QueryDocumentSnapshot>>();
  for (const d of [...ahead.docs, ...cancelled.docs]) {
    if (d.get('kind') !== 'event') continue;
    const cid = d.ref.parent.parent!.id;
    if (!byChurch.has(cid)) byChurch.set(cid, new Map());
    byChurch.get(cid)!.set(d.id, d);
  }
  const keepFrom = deps.now().getTime() - CANCELLED_KEEP_DAYS * DAY_MS;
  for (const [cid, rosters] of byChurch) {
    try {
      await syncChurch(deps, cid, [...rosters.values()], { today, keepFrom }, counts);
    } catch (e) {
      console.error(`event roster sync ${cid}`, e);
    }
  }
  return counts;
}

async function syncChurch(
  deps: CalDeps,
  cid: string,
  rosters: QueryDocumentSnapshot[],
  at: { today: string; keepFrom: number },
  counts: SyncCounts,
) {
  const church = await deps.db.doc(`churches/${cid}`).get();
  if (!isChurchOpen(church)) return;
  const left: QueryDocumentSnapshot[] = [];
  for (const r of rosters) {
    const cancelledAt = r.get('cancelledAt') as Timestamp | undefined;
    if (cancelledAt && cancelledAt.toMillis() < at.keepFrom) {
      await r.ref.delete();
      counts.purged++;
    } else if (!cancelledAt || (r.get('endDateKey') as string) >= at.today) {
      // A cancelled one already over waits to be purged: nobody sees it.
      left.push(r);
    }
  }
  if (!left.length) return;
  const calendar = await calendarAccess(deps, cid);
  if (!calendar?.calendarId) return;
  const { token, calendarId } = calendar;
  // Whether the calendar itself can be read, asked once before an event
  // missing from it counts as deleted: one unshared from the account that
  // connected it says every event is missing.
  let readable: Promise<boolean> | undefined;
  const calendarReadable = () =>
    (readable ??= deps.google
      .events(token, calendarId, deps.now(), new Date(deps.now().getTime() + DAY_MS))
      .then(() => true)
      .catch(() => false));
  for (const r of left) {
    counts.checked++;
    try {
      const done = await syncOne(deps, token, calendarId, r, calendarReadable);
      if (done) counts[done]++;
    } catch (e) {
      console.error(`event roster sync ${cid}/${r.id}`, e);
    }
  }
}

type Outcome = 'updated' | 'cancelled' | 'restored' | 'relinked' | null;

async function syncOne(
  deps: CalDeps,
  token: string,
  calendarId: string,
  r: QueryDocumentSnapshot,
  calendarReadable: () => Promise<boolean>,
): Promise<Outcome> {
  const madeOn = r.get('calendarId') as string | undefined;
  if (madeOn && madeOn !== calendarId) return null;
  const eventId = r.get('eventId') as string;
  const isCancelled = r.get('cancelledAt') != null;
  const e = await deps.google.get(token, calendarId, eventId);
  if (e && !e.cancelled) {
    const next = { ...fromEvent(e), ...stamps(e, calendarId) };
    if (isCancelled) {
      // Back from Google's trash: on again, as quietly as it went.
      await r.ref.update({ ...next, cancelledAt: FieldValue.delete(), via: 'restore' });
      return 'restored';
    }
    const same =
      r.get('title') === next.title &&
      r.get('dateKey') === next.dateKey &&
      r.get('endDateKey') === next.endDateKey &&
      Object.entries(stamps(e, calendarId)).every(([k, v]) => r.get(k) === v);
    if (same) return null;
    // Moved in Google, by nobody here: whoever moved it in the app before
    // is told this time.
    await r.ref.update({ ...next, movedBy: FieldValue.delete() });
    return 'updated';
  }
  if (isCancelled) return null;
  if (await relink(deps, token, calendarId, r)) return 'relinked';
  // Only the calendar it was made on can say the event is gone, and only
  // while it can be read at all.
  if (madeOn !== calendarId || !(await calendarReadable())) return null;
  await r.ref.update({ cancelledAt: Timestamp.fromDate(deps.now()) });
  return 'cancelled';
}

/** What a roster records of where its event is, for later runs. */
const stamps = (e: CalendarEvent, calendarId: string) => ({
  calendarId,
  ...(e.recurringEventId ? { recurringEventId: e.recurringEventId } : {}),
  ...(e.originalStart ? { originalStart: e.originalStart } : {}),
});

/**
 * A recurring event's day gone under its id but there under another: the
 * same series (or one split off it) on the same day it was, or, when the
 * whole series moved, the nearest day of the same series within three days.
 * Moves the roster there, quietly, then copies the event, so a change of
 * day is told.
 */
async function relink(deps: CalDeps, token: string, calendarId: string, r: QueryDocumentSnapshot) {
  const series = r.get('recurringEventId') as string | undefined;
  if (!series) return false;
  const day = r.get('dateKey') as string;
  const was = dayOf((r.get('originalStart') as string | undefined) ?? day);
  const dayStart = Date.parse(`${day}T00:00:00+08:00`);
  const events = await deps.google.events(token, calendarId, new Date(dayStart - 3 * DAY_MS), new Date(dayStart + 4 * DAY_MS));
  const others = events.filter(
    (e) => e.id && e.id !== r.get('eventId') && !e.cancelled && e.recurringEventId && seriesOf(e.recurringEventId) === seriesOf(series),
  );
  const startOf = (e: CalendarEvent) => Date.parse(/^\d{4}-\d{2}-\d{2}$/.test(e.start) ? `${e.start}T00:00:00+08:00` : e.start);
  const wasAt = Date.parse(
    /^\d{4}-\d{2}-\d{2}$/.test((r.get('originalStart') as string | undefined) ?? day)
      ? `${(r.get('originalStart') as string | undefined) ?? day}T00:00:00+08:00`
      : (r.get('originalStart') as string),
  );
  const match =
    others.find((e) => dayOf(e.originalStart ?? e.start) === was || eventRosterDays(e).dateKey === day) ??
    others
      .filter((e) => e.recurringEventId === series)
      .sort((a, b) => Math.abs(startOf(a) - wasAt) - Math.abs(startOf(b) - wasAt))[0];
  if (!match?.id) return false;
  const to = r.ref.parent.doc(`ev_${match.id}`);
  // Marked first, so the trigger tells nobody of the old one going.
  await r.ref.update({ via: 'relink' });
  const moved = await deps.db.runTransaction(async (tx) => {
    const [old, there] = await Promise.all([tx.get(r.ref), tx.get(to)]);
    // Saved by the app since the mark: try again next run, never loudly.
    if (!old.exists || there.exists || old.get('via') !== 'relink') return false;
    const { cancelledAt: _gone, movedBy: _by, ...data } = old.data()!;
    tx.set(to, { ...data, eventId: match.id, via: 'relink', updatedAt: FieldValue.serverTimestamp() });
    tx.delete(r.ref);
    return true;
  });
  if (!moved) return false;
  await to.update({ ...fromEvent(match), ...stamps(match, calendarId) });
  return true;
}
