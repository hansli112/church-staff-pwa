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
 * again overnight is no news. The webhook is not held; it is the church's.
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
  held: Map<string, string[]>;
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
    held: dutiesByUid(before?.exists ? before.get('duties') : []),
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
interface Told {
  cid: string;
  title: string;
  link: string;
  dateKey: string;
  name: string;
  event: { id: string; title: string } | null;
}

function told(church: DocumentSnapshot, day: Pick<RosterDay, 'dateKey' | 'serviceId' | 'event'>, name: string): Told {
  return {
    cid: church.id,
    title: church.get('name') as string,
    link: day.event ? `/rosters/event/${day.event.id}` : `/rosters/${day.serviceId}/${day.dateKey}`,
    dateKey: day.dateKey,
    name,
    event: day.event,
  };
}

async function tell(deps: PushDeps, t: Told, uid: string, n: News) {
  const push = (body: (w: Words) => string) =>
    notifyMembers(deps, t.cid, [uid], 'rosterChange', (w) => ({ title: t.title, body: body(w), link: t.link }));
  const day = (w: Words) => `${w.shortDate(t.dateKey)} ${t.name}`;
  let sent = 0;
  if (n.movedTo && t.event) sent += await push((w) => w.eventMoved(t.event!.title, w.dateWithWeekday(n.movedTo!)));
  if (n.added.length) sent += await push((w) => w.putOn(day(w), n.added));
  if (n.removed.length) sent += await push((w) => w.takenOff(day(w), n.removed));
  return sent;
}

/**
 * Pushes to each person put on or taken off a duty. The editor is not told
 * about their own change. An event's roster moved to another day tells
 * everyone on it. (One cancelled with its event never gets here: see
 * readRosterChange.) In quiet hours, holds them instead. Returns how many
 * devices it reached.
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
  if (c.editor) news.delete(c.editor.uid);

  const until = quietUntil(timeZoneOf(c.church), deps.now());
  if (until) {
    for (const uid of news.keys()) await hold(deps, c, uid, until);
    return 0;
  }
  const t = told(c.church, c, c.serviceName);
  let sent = 0;
  for (const [uid, n] of news) sent += await tell(deps, t, uid, n);
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
      roles: c.held.get(uid) ?? [],
      dateKey: c.movedFrom ?? c.dateKey,
      serviceId: c.serviceId,
      serviceName: c.serviceName,
      event: c.event,
      sendAt: until,
    });
  } catch (e) {
    // Already held: the first change's "before" stands.
    if ((e as { code?: number }).code !== 6) throw e;
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
    const key = `${d.get('cid')}/${d.get('rosterId')}`;
    byRoster.set(key, [...(byRoster.get(key) ?? []), d]);
  }
  let sent = 0;
  for (const [key, held] of byRoster) {
    const cid = key.split('/')[0];
    const [church, roster, services] = await Promise.all([
      deps.db.doc(`churches/${cid}`).get(),
      deps.db.doc(`churches/${key.replace('/', '/rosters/')}`).get(),
      serviceNames(deps, cid),
    ]);
    const day = rosterDay(roster);
    const first = held[0];
    const was = { dateKey: first.get('dateKey') as string, serviceId: first.get('serviceId') as string | null, event: first.get('event') as Told['event'] };
    const lastDay = day?.lastDay ?? was.dateKey;
    const news = isChurchOpen(church) && !day?.cancelled && lastDay >= dateKeyIn(timeZoneOf(church), deps.now());
    const t = day ? told(church, day, day.name(services)) : told(church, was, first.get('serviceName') as string);
    for (const h of held) {
      if (news) {
        const uid = h.get('uid') as string;
        const before = (h.get('roles') as string[] | undefined) ?? [];
        const now = day?.holders.get(uid) ?? [];
        const moved = day?.event && day.dateKey !== h.get('dateKey') ? day.dateKey : null;
        const n = { movedTo: moved, added: now.filter((r) => !before.includes(r)), removed: before.filter((r) => !now.includes(r)) };
        try {
          sent += await tell(deps, t, uid, n);
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
    push: async () => (change.via === 'import' ? 0 : pushRosterChange(deps, change)),
    webhook: () => queueRosterChange(deps, change, eventId),
  });
}
