import type { DocumentSnapshot } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

import { isChurchOpen } from './access.js';
import { runEach, type Deps } from './common.js';
import { isQuiet, movedBy } from './eventRosters.js';
import type { Words } from './languages.js';
import { notifyMembers, type PushDeps } from './push.js';
import { duties, dutiesByUid, names, rosterDay, serviceNames, type RosterDay } from './rosters.js';
import { queue } from './webhook.js';
import { dateKeyIn, earliestDay, instantOf, nextDay, timeZoneOf, wallClock } from './timeZones.js';

/**
 * 服事表異動: one write of a roster day, read once into a [RosterChange],
 * then told to everyone who should hear about it: a push to the people put
 * on or taken off a duty, and the church's webhook (roster notices are
 * batched, see webhook.ts). The two go out independently: one failing never
 * stops the other.
 *
 * Quiet hours: a push due from 22:00 to 7:00 on the church's clock waits
 * until 7:00 (`heldPushes/{cid}_{rosterId}_{uid}`), and then tells what
 * changed for that person since the first held change: put on and taken off
 * again overnight is no news, nor are their own edits or an import. The
 * webhook is not held; it is the church's.
 */

export interface DutyDiff {
  /** uid → duties they were put on (people with an account). */
  added: Map<string, string[]>;
  /** uid → duties they were taken off. */
  removed: Map<string, string[]>;
  /** Per duty, the names put on and taken off: everyone, account or not. */
  duties: { duty: string; added: string[]; removed: string[] }[];
}

/** Who was put on or taken off which duty between two versions of a day. */
export function diffDuties(before: unknown, after: unknown): DutyDiff {
  const a = dutiesByUid(before);
  const b = dutiesByUid(after);
  const added = new Map<string, string[]>();
  const removed = new Map<string, string[]>();
  for (const [uid, roles] of b) {
    const was = new Set(a.get(uid) ?? []);
    const extra = roles.filter((r) => !was.has(r));
    if (extra.length) added.set(uid, extra);
  }
  for (const [uid, roles] of a) {
    const now = new Set(b.get(uid) ?? []);
    const gone = roles.filter((r) => !now.has(r));
    if (gone.length) removed.set(uid, gone);
  }
  const people = (v: unknown) => new Map(duties(v).map((d) => [d.role as string, names(d.people)]));
  const was = people(before);
  const now = people(after);
  const byDuty = [...new Set([...now.keys(), ...was.keys()])]
    .map((duty) => {
      const p = was.get(duty) ?? [];
      const q = now.get(duty) ?? [];
      return { duty, added: q.filter((x) => !p.includes(x)), removed: p.filter((x) => !q.includes(x)) };
    })
    .filter((d) => d.added.length || d.removed.length);
  return { added, removed, duties: byDuty };
}

/** One roster day's change, as everyone who hears about it sees it. */
export interface RosterChange extends DutyDiff {
  church: DocumentSnapshot;
  rosterId: string;
  dateKey: string;
  /** The service; null for an event's roster. */
  serviceId: string | null;
  /** The service's name, or the event's title. */
  serviceName: string;
  /** For an event's roster (活動的服事表): the calendar event. */
  event: { id: string; title: string } | null;
  /** An event's roster moved to another day: the day it was on. */
  movedFrom: string | null;
  /** uid → their duties on the roster as it is now. */
  holders: Map<string, string[]>;
  /** uid → their duties on it before this change. */
  previously: Map<string, string[]>;
  /** `app`, or `import` when the day came in with a whole import (or was
   * put back by undoing one). For a deleted day, how it was last written. */
  via: string;
  /** Who made the change (a member); null for the backend itself. */
  editor: { uid: string; name: string | null } | null;
}

/**
 * The change one roster write makes, or null when there is nothing to tell:
 * not a roster, a past day (the church's; an event's last day), a church that is
 * not open, or nobody put on or taken off anything. An event's roster also
 * tells of a move to another day, and some of its writes tell nothing
 * (eventRosters.ts).
 */
export async function readRosterChange(
  deps: Deps,
  cid: string,
  before: DocumentSnapshot | undefined,
  after: DocumentSnapshot | undefined,
  editedBy: string | undefined,
): Promise<RosterChange | null> {
  const doc = after?.exists ? after : before;
  const day = rosterDay(doc);
  // Past everywhere, before reading the church for its own today.
  if (!day || day.lastDay < earliestDay(deps.now()) || isQuiet(before, after)) return null;
  const diff = diffDuties(before?.exists ? before.get('duties') : [], after?.exists ? after.get('duties') : []);
  const was = rosterDay(before)?.dateKey;
  const movedFrom = day.event && after?.exists && was && was !== day.dateKey ? was : null;
  if (!diff.added.size && !diff.removed.size && !diff.duties.length && !movedFrom) return null;
  // A move calendarWrite made has no signed-in writer: it names who moved it.
  if (!editedBy && movedFrom) editedBy = movedBy(after);
  const [church, services, editor] = await Promise.all([
    deps.db.doc(`churches/${cid}`).get(),
    serviceNames(deps, cid),
    editedBy ? deps.db.doc(`churches/${cid}/members/${editedBy}`).get() : null,
  ]);
  if (!isChurchOpen(church) || day.lastDay < dateKeyIn(timeZoneOf(church), deps.now())) return null;
  return {
    ...diff,
    church,
    rosterId: doc!.id,
    dateKey: day.dateKey,
    serviceId: day.serviceId,
    serviceName: day.name(services),
    event: day.event,
    movedFrom,
    holders: dutiesByUid(after?.exists ? after.get('duties') : []),
    previously: dutiesByUid(before?.exists ? before.get('duties') : []),
    // A deleted day keeps the way it was last written: taking back an
    // import removes days no push announced, so none announces their going.
    via: (doc?.get('via') as string | undefined) ?? 'app',
    editor: editedBy ? { uid: editedBy, name: (editor?.get('name') as string | undefined) || null } : null,
  };
}

/** The church's quiet hours, on its clock: from [QUIET_FROM]:00 to [QUIET_UNTIL]:00. */
export const QUIET_FROM = 22;
export const QUIET_UNTIL = 7;

/** When quiet hours on [timeZone]'s clock end, if [now] is in them; else null. */
export function quietUntil(timeZone: string, now: Date): Date | null {
  const wall = wallClock(timeZone, now.getTime());
  const hour = wall.getUTCHours();
  if (hour >= QUIET_UNTIL && hour < QUIET_FROM) return null;
  const today = wall.toISOString().slice(0, 10);
  const day = hour < QUIET_UNTIL ? today : nextDay(today);
  return new Date(instantOf(timeZone, `${day}T${String(QUIET_UNTIL).padStart(2, '0')}:00`));
}

/** What one person hears about one roster day, a push each. */
interface News {
  /** An event's roster moved to this day. */
  movedTo: string | null;
  added: string[];
  removed: string[];
}

/** The roster day a push is about: its church, its link, how it reads. */
interface PushDay {
  cid: string;
  title: string;
  link: string;
  dateKey: string;
  name: string;
  event: { id: string; title: string } | null;
}

function pushDay(church: DocumentSnapshot, day: Pick<RosterDay, 'dateKey' | 'serviceId' | 'event'>, name: string): PushDay {
  return {
    cid: church.id,
    title: church.get('name') as string,
    link: day.event ? `/rosters/event/${day.event.id}` : `/rosters/${day.serviceId}/${day.dateKey}`,
    dateKey: day.dateKey,
    name,
    event: day.event,
  };
}

async function tell(deps: PushDeps, day: PushDay, uid: string, news: News) {
  const push = (body: (w: Words) => string) =>
    notifyMembers(deps, day.cid, [uid], 'rosterChange', (w) => ({ title: day.title, body: body(w), link: day.link }));
  const label = (w: Words) => `${w.shortDate(day.dateKey)} ${day.name}`;
  let sent = 0;
  if (news.movedTo && day.event) {
    const { title } = day.event;
    sent += await push((w) => w.eventMoved(title, w.dateWithWeekday(news.movedTo!)));
  }
  if (news.added.length) sent += await push((w) => w.putOn(label(w), news.added));
  if (news.removed.length) sent += await push((w) => w.takenOff(label(w), news.removed));
  return sent;
}

// Firestore's (gRPC's) code for a create() whose document exists.
const ALREADY_EXISTS = 6;

/** The pushes held over quiet hours for [c]'s roster, by uid. */
async function heldFor(deps: PushDeps, c: RosterChange) {
  const q = await deps.db
    .collection('heldPushes')
    .where('cid', '==', c.church.id)
    .where('rosterId', '==', c.rosterId)
    .get();
  return new Map(q.docs.map((d) => [d.get('uid') as string, d]));
}

/** [uid]'s news since push [h] was held: from what they had then to [now], on [dateKey]. */
function newsSince(h: DocumentSnapshot, now: string[], dateKey: string, event: boolean): News {
  const before = (h.get('roles') as string[] | undefined) ?? [];
  return {
    movedTo: event && dateKey !== h.get('dateKey') ? dateKey : null,
    added: now.filter((r) => !before.includes(r)),
    removed: before.filter((r) => !now.includes(r)),
  };
}

/**
 * Takes [uid]'s part of [c] into held push [h] as if it had always been so:
 * a change they are not to hear about (their own, or an import's).
 */
async function absorb(h: DocumentSnapshot, c: RosterChange, uid: string) {
  const roles = (h.get('roles') as string[] | undefined) ?? [];
  const off = c.removed.get(uid) ?? [];
  const on = c.added.get(uid) ?? [];
  await h.ref.update({ roles: [...roles.filter((r) => !off.includes(r)), ...on.filter((r) => !roles.includes(r))] });
}

/** An import (or its undo) announces nothing: held pushes take it as given. */
async function absorbImport(deps: PushDeps, c: RosterChange) {
  for (const [uid, h] of await heldFor(deps, c)) await absorb(h, c, uid);
  return 0;
}

/**
 * Pushes to each person put on or taken off a duty. The editor is not told
 * about their own change. An event's roster moved to another day tells
 * everyone on it. (One cancelled with its event never gets here: see
 * readRosterChange.) In quiet hours, holds them instead; after, someone
 * with a push still held hears the night's news and this one as one.
 * Returns how many devices it reached.
 */
export async function pushRosterChange(deps: PushDeps & Pick<Deps, 'now'>, c: RosterChange) {
  const news = new Map<string, News>();
  const of = (uid: string) => {
    if (!news.has(uid)) news.set(uid, { movedTo: null, added: [], removed: [] });
    return news.get(uid)!;
  };
  if (c.event && c.movedFrom) for (const uid of c.holders.keys()) of(uid).movedTo = c.dateKey;
  for (const [uid, roles] of c.added) of(uid).added = roles;
  for (const [uid, roles] of c.removed) of(uid).removed = roles;

  const held = await heldFor(deps, c);
  if (c.editor) {
    news.delete(c.editor.uid);
    const own = held.get(c.editor.uid);
    if (own) await absorb(own, c, c.editor.uid);
  }
  const until = quietUntil(timeZoneOf(c.church), deps.now());
  if (until) {
    for (const uid of news.keys()) if (!held.has(uid)) await hold(deps, c, uid, until);
    return 0;
  }
  const day = pushDay(c.church, c, c.serviceName);
  let sent = 0;
  for (const [uid, n] of news) {
    const h = held.get(uid);
    if (!h) {
      sent += await tell(deps, day, uid, n);
      continue;
    }
    sent += await tell(deps, day, uid, newsSince(h, c.holders.get(uid) ?? [], c.dateKey, c.event !== null));
    await h.ref.delete();
  }
  return sent;
}

/**
 * Keeps [uid]'s news of [c] for [until]: what they had on the day before
 * the first change held, so later ones that night add up.
 */
async function hold(deps: PushDeps, c: RosterChange, uid: string, until: Date) {
  const ref = deps.db.doc(`heldPushes/${c.church.id}_${c.rosterId}_${uid}`);
  try {
    await ref.create({
      cid: c.church.id,
      rosterId: c.rosterId,
      uid,
      roles: c.previously.get(uid) ?? [],
      dateKey: c.movedFrom ?? c.dateKey,
      serviceId: c.serviceId,
      serviceName: c.serviceName,
      event: c.event,
      sendAt: until,
    });
  } catch (e) {
    // Already held: the first change's "before" stands.
    if ((e as { code?: number }).code !== ALREADY_EXISTS) throw e;
  }
}

/**
 * Sends the pushes held over quiet hours that are due, each the difference
 * between what the person had on the day then and has now. A day that has
 * passed, a cancelled event, or a church no longer open tells nothing.
 * Runs every hour (index.ts). Returns how many devices it reached.
 */
export async function sendHeldPushes(deps: PushDeps & Pick<Deps, 'now'>) {
  const due = await deps.db.collection('heldPushes').where('sendAt', '<=', deps.now()).get();
  const byRoster = new Map<string, typeof due.docs>();
  for (const d of due.docs) {
    const key = `${d.get('cid')}_${d.get('rosterId')}`;
    byRoster.set(key, [...(byRoster.get(key) ?? []), d]);
  }
  let sent = 0;
  for (const held of byRoster.values()) {
    const first = held[0];
    const cid = first.get('cid') as string;
    const [church, roster, services] = await Promise.all([
      deps.db.doc(`churches/${cid}`).get(),
      deps.db.doc(`churches/${cid}/rosters/${first.get('rosterId') as string}`).get(),
      serviceNames(deps, cid),
    ]);
    // A deleted day reads as it was when first held.
    const day = rosterDay(roster);
    const was = {
      dateKey: first.get('dateKey') as string,
      serviceId: first.get('serviceId') as string | null,
      event: first.get('event') as PushDay['event'],
    };
    const lastDay = day?.lastDay ?? was.dateKey;
    const isNews = isChurchOpen(church) && !day?.cancelled && lastDay >= dateKeyIn(timeZoneOf(church), deps.now());
    const about = day ? pushDay(church, day, day.name(services)) : pushDay(church, was, first.get('serviceName') as string);
    for (const h of held) {
      if (isNews) {
        const uid = h.get('uid') as string;
        try {
          sent += await tell(deps, about, uid, newsSince(h, day?.holders.get(uid) ?? [], about.dateKey, about.event !== null));
        } catch (e) {
          logger.error('Held roster push failed', { cid, uid, error: String(e) });
        }
      }
      await h.ref.delete();
    }
  }
  return sent;
}

/** Queues the change for the church's webhook, keyed by [id]; false when not queued. */
export async function queueRosterChange(deps: Deps, c: RosterChange, id: string) {
  if (!c.duties.length) return false;
  return queue(deps, c.church, id, {
    date: c.dateKey,
    serviceId: c.serviceId,
    serviceName: c.serviceName,
    eventId: c.event?.id ?? null,
    title: c.event?.title ?? null,
    duties: c.duties,
    actorUid: c.editor?.uid ?? null,
    actorName: c.editor?.name ?? null,
    via: c.via,
  });
}

/**
 * The onRosterWritten trigger: reads the change once and tells the push
 * and the webhook side by side. [eventId] keys the webhook's outbox entry,
 * so a retried event queues nothing twice. Throws, after both have run,
 * when either failed.
 *
 * Imports: a whole import is news once, not once per day. It sends no
 * push (that would be one per person per day) and goes to the webhook,
 * where the batch says `imported`.
 */
export async function onRosterWritten(
  deps: Deps & PushDeps,
  cid: string,
  before: DocumentSnapshot | undefined,
  after: DocumentSnapshot | undefined,
  editedBy: string | undefined,
  eventId: string,
) {
  const change = await readRosterChange(deps, cid, before, after, editedBy);
  if (!change) return null;
  return runEach(`roster change ${cid}/${change.event ? `ev_${change.event.id}` : `${change.dateKey}_${change.serviceId}`}`, {
    push: async () => (change.via === 'import' ? absorbImport(deps, change) : pushRosterChange(deps, change)),
    webhook: () => queueRosterChange(deps, change, eventId),
  });
}
