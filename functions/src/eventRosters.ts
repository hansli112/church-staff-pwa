import { FieldValue, Timestamp, type DocumentSnapshot } from 'firebase-admin/firestore';

import type { CalendarEvent } from './calendar.js';
import { DAY_MS, type Deps } from './common.js';
import { cutText, TEXT_LIMITS } from './limits.js';
import { tellsOf, viaOf } from './rosterNews.js';
import { dateKeyIn, type ChurchTimeZone } from './timeZones.js';

/**
 * 活動的服事表 (rosters/ev_<event id>): every way one changes after it is
 * made, and so whether its trigger tells anyone (rosterChange.ts asks
 * [isQuiet] and [movedBy]). A change made here says how in `via`:
 *
 * - `calendar`: took its event's title and days, from the app or Google. A
 *   move is told; one made in the app names who moved it (`movedBy`).
 * - `restore`: put back by undoing its event's delete, or out of Google's
 *   trash. Told nothing: nobody was told it went.
 * - `relink`: moved to its event's new id (a recurring day split off).
 *   Neither the old one going nor the new one is told.
 * - `timeZone`: its days on the clock of the church's new time zone.
 *   Nothing moved, so nothing is told.
 *
 * Cancelled (`cancelledAt`, its event deleted) it is told nothing at all,
 * neither the cancelling nor anything after, until it is put back.
 * Edits of its duties come from the app (`app`, or `import`), as any
 * roster's.
 */

/**
 * A change of an event: in the app (`edited`, `deleted`, `restored`, made
 * again by undoing its delete, under a new id), or as the sync finds it in
 * Google.
 */
export type EventChange = 'edited' | 'deleted' | 'restored' | 'seenInGoogle' | 'goneFromGoogle';

/**
 * What an event's roster does when its event has [change], by whether it
 * is there and cancelled (testdata/event_rosters.json, which the app runs
 * too): a cancelled one follows no edit, and only it moves onto the event
 * a delete undone makes again, or reopens when its event is back in Google.
 */
export function eventRosterFate(change: EventChange, roster: 'none' | 'on' | 'cancelled') {
  if (roster === 'none') return 'nothing';
  const on = roster === 'on';
  switch (change) {
    case 'edited':
      return on ? 'follows' : 'nothing';
    case 'deleted':
      return 'cancelled';
    case 'restored':
      return on ? 'nothing' : 'movesOnto';
    case 'seenInGoogle':
      return on ? 'follows' : 'reopens';
    case 'goneFromGoogle':
      return on ? 'cancelled' : 'nothing';
  }
}

/** [d] as [eventRosterFate] takes it. */
const stateOf = (d: DocumentSnapshot | undefined) => (!isEvent(d) ? 'none' : isCancelled(d) ? 'cancelled' : 'on');

/** Whether [d] is an event's roster (活動的服事表). */
export const isEvent = (d: DocumentSnapshot | undefined) => d?.exists === true && d.get('kind') === 'event';

/** Whether [d] is an event's roster cancelled with its event. */
export const isCancelled = (d: DocumentSnapshot | undefined) => isEvent(d) && d!.get('cancelledAt') != null;

/** Whether the write of an event's roster from [before] to [after] tells nobody. */
export function isQuiet(before: DocumentSnapshot | undefined, after: DocumentSnapshot | undefined) {
  const doc = after?.exists ? after : before;
  if (!isEvent(doc)) return false;
  return isCancelled(before) || isCancelled(after) || tellsOf(viaOf(doc!.get('via'))) === 'nobody';
}

/** Who moved [after] in the app, when the backend wrote the move. */
export const movedBy = (after: DocumentSnapshot | undefined) =>
  after?.exists ? ((after.get('movedBy') as string | undefined) ?? undefined) : undefined;

/** The days an event's roster is on (`dateKey`s): the church's, an all-day end exclusive. */
export function eventRosterDays(e: { start: string; end?: string; allDay?: boolean }, timeZone: ChurchTimeZone) {
  const ymd = /^\d{4}-\d{2}-\d{2}$/;
  if (e.allDay === true || ymd.test(e.start)) {
    const last = inclusiveEnd(e.end);
    return { dateKey: e.start, endDateKey: last && last > e.start ? last : e.start };
  }
  const start = Date.parse(e.start);
  const end = e.end === undefined ? NaN : Date.parse(e.end);
  const dateKey = dateKeyIn(timeZone, new Date(start));
  return { dateKey, endDateKey: end > start ? dateKeyIn(timeZone, new Date(end - 1)) : dateKey };
}

/** Google's exclusive all-day end date → the last day covered. */
export function inclusiveEnd(end: string | undefined): string | null {
  if (typeof end !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(end)) return null;
  return new Date(Date.parse(`${end}T00:00:00Z`) - DAY_MS).toISOString().slice(0, 10);
}

const ref = (deps: Deps, churchId: string, eventId: string) => deps.db.doc(`churches/${churchId}/rosters/ev_${eventId}`);

/** What an event's roster copies from [e]. `via` clears a quiet one, so a later move is told. */
const fromEvent = (e: CalendarEvent, timeZone: ChurchTimeZone) => ({
  title: cutText(e.title, TEXT_LIMITS.eventTitle),
  ...eventRosterDays(e, timeZone),
  // Whose the event is (#84), which lets that group's 負責人 arrange it;
  // none for the church's, as the app writes it.
  ...(e.group ? { group: e.group } : {}),
  via: 'calendar',
  updatedAt: FieldValue.serverTimestamp(),
});

/** [fromEvent] as an update: an event now the church's drops its group. */
const updateFromEvent = (e: CalendarEvent, timeZone: ChurchTimeZone) => ({
  ...fromEvent(e, timeZone),
  ...(e.group ? {} : { group: FieldValue.delete() }),
});

/** What a roster records of where its event is in [calendarId], for later syncs. */
const stamps = (e: CalendarEvent, calendarId: string) => ({
  calendarId,
  ...(e.recurringEventId ? { recurringEventId: e.recurringEventId } : {}),
  ...(e.originalStart ? { originalStart: e.originalStart } : {}),
});

const same = (r: DocumentSnapshot, next: { title: string; dateKey: string; endDateKey: string }, e: CalendarEvent) =>
  r.get('title') === next.title && r.get('dateKey') === next.dateKey && r.get('endDateKey') === next.endDateKey
  && (r.get('group') ?? '') === (e.group ?? '');

// Changes made in the app (calendarWrite), after Google has them.

/**
 * Event [e] edited in the app by [by]: its roster, if still on, takes its
 * title and days. A move is told, to everyone but [by].
 */
export async function followEdit(deps: Deps, churchId: string, timeZone: ChurchTimeZone, e: CalendarEvent, by: string) {
  if (!e.id) return;
  const at = ref(deps, churchId, e.id);
  await deps.db.runTransaction(async (tx) => {
    const r = await tx.get(at);
    if (eventRosterFate('edited', stateOf(r)) !== 'follows') return;
    const next = updateFromEvent(e, timeZone);
    if (!same(r, next, e)) tx.update(at, { ...next, movedBy: by });
  });
}

/** Event [eventId] deleted in the app: its roster is cancelled, not shown, not reminded, kept for undo. */
export async function cancelWithEvent(deps: Deps, churchId: string, eventId: string) {
  const at = ref(deps, churchId, eventId);
  await deps.db.runTransaction(async (tx) => {
    if (eventRosterFate('deleted', stateOf(await tx.get(at))) === 'cancelled') {
      tx.update(at, { cancelledAt: Timestamp.fromDate(deps.now()) });
    }
  });
}

/** A delete undone, the event made again as [e]: the cancelled roster of [fromId] moves onto it, quietly. */
export async function restoreOnto(deps: Deps, churchId: string, timeZone: ChurchTimeZone, fromId: string, e: CalendarEvent) {
  if (!/^[A-Za-z0-9_-]{1,1024}$/.test(fromId) || !e.id || fromId === e.id) return;
  const from = ref(deps, churchId, fromId);
  const to = ref(deps, churchId, e.id);
  await deps.db.runTransaction(async (tx) => {
    const r = await tx.get(from);
    if (eventRosterFate('restored', stateOf(r)) !== 'movesOnto') return;
    const keep = (k: string) => (r.get(k) === undefined ? {} : { [k]: r.get(k) });
    tx.set(to, {
      kind: 'event',
      eventId: e.id,
      duties: r.get('duties') ?? [],
      events: [],
      ...keep('calendarId'),
      ...keep('recurringEventId'),
      ...keep('originalStart'),
      ...fromEvent(e, timeZone),
      via: 'restore',
    });
    tx.delete(from);
  });
}

// Changes made in Google Calendar itself (eventSync.ts).

/**
 * Roster [r] against its event [e] as Google has it in [calendarId]: a
 * cancelled one is on again, quietly (back from Google's trash); one on
 * takes a new title or days, and whoever moved it in the app before is
 * told this time.
 */
export async function followGoogle(r: DocumentSnapshot, e: CalendarEvent, calendarId: string, timeZone: ChurchTimeZone) {
  const next = { ...updateFromEvent(e, timeZone), ...stamps(e, calendarId) };
  if (eventRosterFate('seenInGoogle', stateOf(r)) === 'reopens') {
    await r.ref.update({ ...next, cancelledAt: FieldValue.delete(), via: 'restore' });
    return 'restored' as const;
  }
  if (same(r, next, e) && Object.entries(stamps(e, calendarId)).every(([k, v]) => r.get(k) === v)) return null;
  await r.ref.update({ ...next, movedBy: FieldValue.delete() });
  return 'updated' as const;
}

/** Roster [r]'s event gone from Google: cancelled, as when deleted in the app. */
export async function cancelGone(deps: Deps, r: DocumentSnapshot) {
  await r.ref.update({ cancelledAt: Timestamp.fromDate(deps.now()) });
}

/**
 * Moves roster [r] onto [match], the same day of its recurring event under
 * a new id: quietly, then takes [match]'s title and days, so a change of
 * day is told. False, leaving it for the next sync, when the app saved it
 * meanwhile or [match] already has one.
 */
export async function relinkTo(deps: Deps, r: DocumentSnapshot, match: CalendarEvent & { id: string }, calendarId: string, timeZone: ChurchTimeZone) {
  const to = r.ref.parent.doc(`ev_${match.id}`);
  // Marked first, so the old one's going is quiet.
  await r.ref.update({ via: 'relink' });
  const moved = await deps.db.runTransaction(async (tx) => {
    const [old, there] = await Promise.all([tx.get(r.ref), tx.get(to)]);
    if (!old.exists || there.exists || old.get('via') !== 'relink') return false;
    const { cancelledAt: _gone, movedBy: _by, ...data } = old.data()!;
    tx.set(to, { ...data, eventId: match.id, via: 'relink', updatedAt: FieldValue.serverTimestamp() });
    tx.delete(r.ref);
    return true;
  });
  if (!moved) return false;
  await to.update({ ...updateFromEvent(match, timeZone), ...stamps(match, calendarId) });
  return true;
}

/** The church's time zone changed: roster [r] takes [e]'s days on the new clock, quietly. False when they are the same. */
export async function takeTimeZone(r: DocumentSnapshot, e: CalendarEvent, timeZone: ChurchTimeZone) {
  const days = eventRosterDays(e, timeZone);
  if (r.get('dateKey') === days.dateKey && r.get('endDateKey') === days.endDateKey) return false;
  await r.ref.update({ ...days, via: 'timeZone', movedBy: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
  return true;
}
