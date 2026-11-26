import { voidStaleSwaps } from './swaps.js';
import { Timestamp, type DocumentSnapshot } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

import { churchAccess, isChurchOpen } from './access.js';
import { fail, record, runEach, type Caller, type Deps } from './common.js';
import { isQuiet, movedBy } from './eventRosters.js';
import type { Words } from './languages.js';
import { familiesOf, notifyAbout } from './family.js';
import type { PushDeps } from './push.js';
import {
  duties,
  dutiesByUid,
  groupMembersOn,
  groupNamesIn,
  names,
  rosterDay,
  rosterLink,
  serviceNames,
  shownDuties,
  type GroupMembers,
  type RosterDay,
} from './rosters.js';
import { queue } from './webhook.js';
import { dateKeyIn, earliestDay, instantOf, nextDay, timeZoneOf, wallClock } from './timeZones.js';
import { loggable } from './redact.js';
import { plannedAfter, tellsOf, viaOf, type Via } from './rosterNews.js';

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
 *
 * 安排服事 (#90): a change made there (`via: 'plan'`) is not told at once
 * either. It waits at `plannedPushes/{cid}_{rosterId}_{uid}` until someone
 * presses 通知同工 for the service ([notifyPlanned]), and then each person
 * hears in one push what changed for them on all its days.
 */

export interface DutyDiff {
  /** uid → duties they were put on (people with an account). */
  added: Map<string, string[]>;
  /** uid → duties they were taken off. */
  removed: Map<string, string[]>;
  /** Per duty, the names put on and taken off: everyone, account or not. */
  duties: { duty: string; added: string[]; removed: string[] }[];
}

/**
 * Who was put on or taken off which duty between two versions of a day;
 * [groups], who is in the 小組 a duty is given to.
 */
export function diffDuties(before: unknown, after: unknown, groups: GroupMembers = new Map()): DutyDiff {
  const a = dutiesByUid(before, groups);
  const b = dutiesByUid(after, groups);
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
  /** Where the write came from (rosterNews.ts). For a deleted day, how it
   * was last written. */
  via: Via;
  /** Who made the change (a member); null for the backend itself. */
  editor: { uid: string; name: string | null } | null;
  /** The day was just marked 沒有聚會: those taken off hear that instead. */
  noService: boolean;
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
  const dutiesBefore = before?.exists ? before.get('duties') : [];
  const dutiesAfter = after?.exists ? after.get('duties') : [];
  // 服事交給小組: everyone in the 小組 holds the duty.
  const groups = await groupMembersOn(deps, cid, dutiesBefore, dutiesAfter);
  const diff = diffDuties(dutiesBefore, dutiesAfter, groups);
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
    holders: dutiesByUid(dutiesAfter, groups),
    previously: dutiesByUid(dutiesBefore, groups),
    // A deleted day keeps the way it was last written: taking back an
    // import removes days no push announced, so none announces their going.
    via: viaOf(doc?.get('via')),
    editor: editedBy ? { uid: editedBy, name: (editor?.get('name') as string | undefined) || null } : null,
    noService: after?.get('noService') === true && before?.get('noService') !== true,
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
  /** Taken off as the day has no meeting (沒有聚會). */
  noService?: boolean;
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
    link: rosterLink(day),
    dateKey: day.dateKey,
    name,
    event: day.event,
  };
}

/**
 * Tells [uid] their [news] of [day]; of one without an account, their
 * 家人 (family.ts), but [except], who made the change.
 */
async function tell(deps: PushDeps, day: PushDay, uid: string, news: News, except?: string) {
  const family = (await familiesOf(deps, day.cid, [uid])).get(uid) ?? null;
  const push = (body: (w: Words, who: string | null) => string) =>
    notifyAbout(deps, day.cid, uid, 'rosterChange', (w, who) => ({ title: day.title, body: body(w, who), link: day.link }), except, family);
  const label = (w: Words) => `${w.shortDate(day.dateKey)} ${day.name}`;
  const names = await groupNamesIn(deps, day.cid, [...news.added, ...news.removed]);
  let sent = 0;
  if (news.movedTo && day.event) {
    const { title } = day.event;
    sent += await push((w) => w.eventMoved(title, w.dateWithWeekday(news.movedTo!)));
  }
  if (news.added.length) {
    const added = (w: Words) => shownDuties(w, news.added, names);
    sent += await push((w, who) => (who ? w.familyPutOn(who, label(w), added(w)) : w.putOn(label(w), added(w))));
  }
  if (news.removed.length && news.noService) {
    sent += await push((w) => w.noService(label(w)));
  } else if (news.removed.length) {
    const removed = (w: Words) => shownDuties(w, news.removed, names);
    sent += await push((w, who) => (who ? w.familyTakenOff(who, label(w), removed(w)) : w.takenOff(label(w), removed(w))));
  }
  return sent;
}

// Firestore's (gRPC's) code for a create() whose document exists.
const ALREADY_EXISTS = 6;

/**
 * The pushes waiting for [c]'s roster, by uid: held over quiet hours
 * (`heldPushes`), or for 通知同工 (`plannedPushes`).
 */
async function waitingFor(deps: PushDeps, collection: 'heldPushes' | 'plannedPushes', c: RosterChange) {
  const q = await deps.db
    .collection(collection)
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

/**
 * Keeps planned push [p] as what still waits once [c] reaches [uid]: [told]
 * when it does some other way (rosterNews.ts plannedAfter). Gone once they
 * have on the day what they had before, so the button greys with nothing
 * to tell.
 */
async function settlePlanned(p: DocumentSnapshot, c: RosterChange, uid: string, told: boolean) {
  const roles = plannedAfter(
    (p.get('roles') as string[] | undefined) ?? [],
    c.previously.get(uid) ?? [],
    c.holders.get(uid) ?? [],
    told,
  );
  return roles === null ? p.ref.delete() : p.ref.update({ roles });
}

/** An import (or its undo) announces nothing: held and planned pushes take it as given. */
async function absorbImport(deps: PushDeps, c: RosterChange) {
  for (const [uid, h] of await waitingFor(deps, 'heldPushes', c)) await absorb(h, c, uid);
  for (const [uid, p] of await waitingFor(deps, 'plannedPushes', c)) await settlePlanned(p, c, uid, true);
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
  for (const [uid, roles] of c.removed) {
    of(uid).removed = roles;
    of(uid).noService = c.noService;
  }

  // Told now, or the editor's own: what 通知同工 tells later leaves it out.
  for (const [uid, p] of await waitingFor(deps, 'plannedPushes', c)) {
    if (news.has(uid) || uid === c.editor?.uid) await settlePlanned(p, c, uid, true);
  }
  const held = await waitingFor(deps, 'heldPushes', c);
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
      sent += await tell(deps, day, uid, n, c.editor?.uid);
      continue;
    }
    sent += await tell(deps, day, uid, newsSince(h, c.holders.get(uid) ?? [], c.dateKey, c.event !== null), c.editor?.uid);
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
    const day = rosterDay(roster, await groupMembersOn(deps, cid, roster.get('duties')));
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
          logger.error('Held roster push failed', { cid, uid, error: loggable(e).message });
        }
      }
      await h.ref.delete();
    }
  }
  return sent;
}

/**
 * A change made in 安排服事: told to nobody yet. Each person put on or
 * taken off, but the editor, keeps what they had on the day before the
 * first such change, for 通知同工. A push held over quiet hours tells only
 * of what came before it.
 */
async function planRosterChange(deps: PushDeps, c: RosterChange) {
  const uids = new Set([...c.added.keys(), ...c.removed.keys()]);
  // One of the 同工 without an account yet has no member to tell, but
  // maybe a family.
  if (uids.size) {
    const them = await deps.db.getAll(...[...uids].map((uid) => deps.db.doc(`churches/${c.church.id}/members/${uid}`)));
    const without = them.filter((m) => !m.exists).map((m) => m.id);
    const families = without.length ? await familiesOf(deps, c.church.id, without) : new Map();
    for (const id of without) if (!families.has(id)) uids.delete(id);
  }
  for (const [uid, h] of await waitingFor(deps, 'heldPushes', c)) if (uids.has(uid)) await absorb(h, c, uid);
  const planned = await waitingFor(deps, 'plannedPushes', c);
  if (c.editor) {
    uids.delete(c.editor.uid);
    const own = planned.get(c.editor.uid);
    if (own) await settlePlanned(own, c, c.editor.uid, true);
  }
  for (const uid of uids) {
    // Already waiting: on and off again leaves nothing to tell.
    const p = planned.get(uid);
    if (p) {
      await settlePlanned(p, c, uid, false);
      continue;
    }
    const roles = plannedAfter(null, c.previously.get(uid) ?? [], c.holders.get(uid) ?? [], false);
    if (roles === null) continue;
    try {
      await deps.db.doc(`plannedPushes/${c.church.id}_${c.rosterId}_${uid}`).create({
        cid: c.church.id,
        rosterId: c.rosterId,
        uid,
        roles,
        dateKey: c.dateKey,
        serviceId: c.serviceId,
        serviceName: c.serviceName,
        // Set by 通知同工 in quiet hours: when it goes out.
        sendAt: null,
      });
    } catch (e) {
      if ((e as { code?: number }).code !== ALREADY_EXISTS) throw e;
    }
  }
  return 0;
}

/**
 * Tells everyone in [entries] (plannedPushes of [church]) what changed for
 * them since, one push each for all their days: those still ahead, as the
 * days are now. Of one without an account, their 家人 hear, but [by], who
 * pressed 通知同工 (or the entries' `by`, pressed in quiet hours). Deletes
 * the entries. Returns how many people it told.
 */
async function sendPlanned(deps: PushDeps & Pick<Deps, 'now'>, church: DocumentSnapshot, entries: DocumentSnapshot[], by?: string) {
  const cid = church.id;
  const today = dateKeyIn(timeZoneOf(church), deps.now());
  const services = await serviceNames(deps, cid);
  const rosters = new Map<string, DocumentSnapshot>();
  for (const id of new Set(entries.map((e) => e.get('rosterId') as string))) {
    rosters.set(id, await deps.db.doc(`churches/${cid}/rosters/${id}`).get());
  }
  const groups = await groupMembersOn(deps, cid, ...[...rosters.values()].map((r) => r.get('duties')));
  const byUid = new Map<string, DocumentSnapshot[]>();
  for (const e of entries) byUid.set(e.get('uid') as string, [...(byUid.get(e.get('uid') as string) ?? []), e]);
  let told = 0;
  for (const [uid, mine] of byUid) {
    const on: [string, string[]][] = [];
    const off: [string, string[]][] = [];
    let service = '';
    let first: { serviceId: string | null; dateKey: string; event: PushDay['event'] } | null = null;
    for (const e of mine) {
      const day = rosterDay(rosters.get(e.get('rosterId') as string), groups);
      const dateKey = day?.dateKey ?? (e.get('dateKey') as string);
      if (day?.cancelled || (day?.lastDay ?? dateKey) < today) continue;
      const news = newsSince(e, day?.holders.get(uid) ?? [], dateKey, false);
      if (news.added.length) on.push([dateKey, news.added]);
      if (news.removed.length) off.push([dateKey, news.removed]);
      if (!news.added.length && !news.removed.length) continue;
      service ||= day ? day.name(services) : (e.get('serviceName') as string);
      if (!first || dateKey < first.dateKey) {
        first = { serviceId: day?.serviceId ?? (e.get('serviceId') as string | null), dateKey, event: day?.event ?? null };
      }
    }
    if (first) {
      const about = pushDay(church, first, service);
      const names = await groupNamesIn(deps, cid, [...on, ...off].flatMap(([, duties]) => duties));
      const lines = (w: Words, list: [string, string[]][]) =>
        list.sort(([a], [b]) => a.localeCompare(b)).map(([k, duties]) => w.dutyLine(w.shortDate(k), shownDuties(w, duties, names)));
      try {
        await notifyAbout(deps, cid, uid, 'rosterChange', (w, who) => ({
          title: about.title,
          body: who ? w.familyPlanned(who, service, lines(w, on), lines(w, off)) : w.planned(service, lines(w, on), lines(w, off)),
          link: about.link,
        }), by ?? (mine.map((e) => e.get('by') as string | undefined).find(Boolean)));
        told++;
      } catch (e) {
        logger.error('Planned roster push failed', { cid, uid, error: loggable(e).message });
      }
    }
    for (const e of mine) await e.ref.delete();
  }
  return told;
}

/** How long 通知同工 waits for days just saved to be read ([readThrough]). */
const READ_WAIT_MS = 20_000;

/**
 * Waits until the trigger has read each of [ids], days 安排服事's 完成 has
 * just saved (`via: 'plan'`) and then tells of at once: what waits for
 * 通知同工 is what the trigger leaves (`plannedSeen`, [markRead]). Gives
 * up after [READ_WAIT_MS]: what is read later waits for the next time.
 */
async function readThrough(deps: Pick<Deps, 'db'>, cid: string, ids: string[]) {
  const until = Date.now() + READ_WAIT_MS;
  let unread = ids;
  while (unread.length) {
    const [rosters, seen] = await Promise.all([
      deps.db.getAll(...unread.map((id) => deps.db.doc(`churches/${cid}/rosters/${id}`))),
      deps.db.getAll(...unread.map((id) => deps.db.doc(`plannedSeen/${cid}_${id}`))),
    ]);
    // Only those still to read are read again.
    unread = unread.filter(
      (_, i) => rosters[i].exists && viaOf(rosters[i].get('via')) === 'plan' && !readSince(seen[i].get('updatedAt'), rosters[i].get('updatedAt')),
    );
    if (!unread.length || Date.now() > until) return;
    await new Promise((r) => setTimeout(r, 300));
  }
}

/** Whether a day read as written at [seen] is read as of [written]: then, or later. */
const readSince = (seen: unknown, written: unknown) =>
  written == null || (seen instanceof Timestamp && written instanceof Timestamp && seen.toMillis() >= written.toMillis());

/**
 * Notes that the trigger has read [after], a day saved in 安排服事, for
 * [readThrough]: never back to an earlier write, as triggers come in any
 * order.
 */
async function markRead(deps: Deps, cid: string, after: DocumentSnapshot | undefined) {
  if (!after?.exists || viaOf(after.get('via')) !== 'plan') return;
  const written = after.get('updatedAt') ?? null;
  const ref = deps.db.doc(`plannedSeen/${cid}_${after.id}`);
  await deps.db.runTransaction(async (tx) => {
    const seen = await tx.get(ref);
    if (seen.exists && readSince(seen.get('updatedAt'), written)) return;
    tx.set(ref, { cid, updatedAt: written, at: deps.now() });
  });
}

/**
 * 通知同工 in 安排服事 (#90), by anyone who arranges service
 * `data.serviceId`: everyone whose days of it changed there since the last
 * time hears, one push each. In quiet hours they wait until 7:00
 * ([sendPlannedPushes]). Returns how many people, and whether later.
 */
export async function notifyPlanned(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  const serviceId = input.serviceId;
  const rosterIds = input.rosterIds ?? [];
  if (typeof serviceId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(serviceId)
      || !Array.isArray(rosterIds) || rosterIds.length > 500
      || rosterIds.some((id) => typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,100}$/.test(id))
      || Object.keys(input).some((k) => !['churchId', 'serviceId', 'rosterIds'].includes(k))) fail('invalid-argument', 'unknown');
  const { cid, church, caller: c } = await churchAccess(deps, caller, data, { arranges: serviceId });
  await readThrough(deps, cid, rosterIds as string[]);
  const q = await deps.db
    .collection('plannedPushes')
    .where('cid', '==', cid)
    .where('serviceId', '==', serviceId)
    .where('sendAt', '==', null)
    .get();
  const until = quietUntil(timeZoneOf(church), deps.now());
  if (until) {
    for (const d of q.docs) await d.ref.update({ sendAt: until, by: c.uid });
    return { people: new Set(q.docs.map((d) => d.get('uid'))).size, later: true };
  }
  return { people: await sendPlanned(deps, church, q.docs, c.uid), later: false };
}

/**
 * Sends what 通知同工 left for after quiet hours, once due, and forgets
 * what waits for days past everywhere, unpressed. Runs every hour
 * (index.ts).
 */
export async function sendPlannedPushes(deps: PushDeps & Pick<Deps, 'now'>) {
  const past = await deps.db.collection('plannedPushes').where('dateKey', '<', earliestDay(deps.now())).get();
  for (const p of past.docs) await p.ref.delete();
  // What 通知同工 waited on, long read.
  const read = await deps.db.collection('plannedSeen').where('at', '<', new Date(deps.now().getTime() - 86_400_000)).get();
  for (const r of read.docs) await r.ref.delete();
  const due = await deps.db.collection('plannedPushes').where('sendAt', '<=', deps.now()).get();
  const byChurch = new Map<string, DocumentSnapshot[]>();
  for (const d of due.docs) byChurch.set(d.get('cid') as string, [...(byChurch.get(d.get('cid') as string) ?? []), d]);
  let told = 0;
  for (const [cid, entries] of byChurch) {
    const church = await deps.db.doc(`churches/${cid}`).get();
    if (isChurchOpen(church)) {
      told += await sendPlanned(deps, church, entries);
    } else {
      for (const e of entries) await e.ref.delete();
    }
  }
  return told;
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
  return tellRosterWritten(deps, cid, before, after, editedBy, eventId);
}

async function tellRosterWritten(
  deps: Deps & PushDeps,
  cid: string,
  before: DocumentSnapshot | undefined,
  after: DocumentSnapshot | undefined,
  editedBy: string | undefined,
  eventId: string,
) {
  const change = await readRosterChange(deps, cid, before, after, editedBy);
  if (!change) {
    await markRead(deps, cid, after);
    return null;
  }
  const { push, webhook } = await runEach(`roster change ${cid}/${change.event ? `ev_${change.event.id}` : `${change.dateKey}_${change.serviceId}`}`, {
    push: async () => {
      switch (tellsOf(change.via)) {
        case 'webhook':
          return absorbImport(deps, change);
        case 'planned': {
          const n = await planRosterChange(deps, change);
          // Read once what waits for 通知同工 is kept: one that failed is
          // not, and 通知同工 waits for it.
          await markRead(deps, cid, after);
          return n;
        }
        case 'now':
          return pushRosterChange(deps, change);
        case 'nobody':
          // Only the backend writes these, and only on an event's roster,
          // which readRosterChange read as quiet already (eventRosters.ts).
          return 0;
      }
    },
    webhook: () => queueRosterChange(deps, change, eventId),
    // 找人代／交換 (#92) the roster no longer bears.
    swaps: () => voidStaleSwaps(deps, cid, (after ?? before)!.id),
  });
  return { push, webhook };
}
