import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { isChurchOpen } from './access.js';
import { dateKeyUtc8, runEach, type Deps } from './common.js';
import { notifyMembers, type PushDeps } from './push.js';
import { queue } from './webhook.js';

/**
 * 服事表異動: one write of a roster day, read once into a [RosterChange],
 * then told to everyone who should hear about it: a push to the people put
 * on or taken off a duty, and the church's webhook (roster notices are
 * batched, see webhook.ts). The two go out independently: one failing never
 * stops the other.
 */

interface Duty {
  role?: unknown;
  people?: unknown;
  uids?: unknown;
}

const duties = (v: unknown) => (Array.isArray(v) ? (v as Duty[]) : []).filter((d) => typeof d?.role === 'string');
const names = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

/** uid → the duties they hold on this roster (people with an account still listed). */
export function dutiesByUid(value: unknown): Map<string, string[]> {
  const out = new Map<string, string[]>();
  for (const d of duties(value)) {
    const people = names(d.people);
    for (const [name, uid] of Object.entries((d.uids as Record<string, unknown> | undefined) ?? {})) {
      if (typeof uid !== 'string' || !people.includes(name)) continue;
      out.set(uid, [...(out.get(uid) ?? []), d.role as string]);
    }
  }
  return out;
}

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
  /** `app`, or `import` when the day came in with a whole import (or was
   * put back by undoing one). For a deleted day, how it was last written. */
  via: string;
  /** Who made the change (a member); null for the backend itself. */
  editor: { uid: string; name: string | null } | null;
}

/** Whether [d] is an event's roster (活動的服事表). */
export const isEvent = (d: DocumentSnapshot | undefined) => d?.exists === true && d.get('kind') === 'event';
const isCancelled = (d: DocumentSnapshot | undefined) => d?.exists === true && d.get('cancelledAt') != null;

/**
 * The change one roster write makes, or null when there is nothing to tell:
 * not a roster, a past day (UTC+8; an event's last day), a church that is
 * not open, or nobody put on or taken off anything. An event's roster also
 * tells of a move to another day. A cancelled event's roster, and one put
 * back by undoing its event's delete (via `restore`), tell nothing.
 */
export async function readRosterChange(
  deps: Deps,
  cid: string,
  before: DocumentSnapshot | undefined,
  after: DocumentSnapshot | undefined,
  editedBy: string | undefined,
): Promise<RosterChange | null> {
  const doc = after?.exists ? after : before;
  const dateKey = doc?.get('dateKey') as string | undefined;
  const event = isEvent(doc);
  const serviceId = event ? null : (doc?.get('type') as string | undefined);
  const lastDay = event ? ((doc?.get('endDateKey') as string | undefined) ?? dateKey) : dateKey;
  if (!dateKey || !lastDay || (!event && !serviceId) || lastDay < dateKeyUtc8(deps.now())) return null;
  if (event && (isCancelled(before) || isCancelled(after) || doc?.get('via') === 'restore')) return null;
  const diff = diffDuties(before?.exists ? before.get('duties') : [], after?.exists ? after.get('duties') : []);
  const movedFrom =
    event && before?.exists && after?.exists && before.get('dateKey') !== dateKey ? (before.get('dateKey') as string) : null;
  if (!diff.added.size && !diff.removed.size && !diff.duties.length && !movedFrom) return null;
  // A move calendarWrite made has no signed-in writer: it names who moved it.
  if (!editedBy && movedFrom) editedBy = (after?.get('movedBy') as string | undefined) ?? undefined;
  const [church, services, editor] = await Promise.all([
    deps.db.doc(`churches/${cid}`).get(),
    deps.db.doc(`churches/${cid}/settings/services`).get(),
    editedBy ? deps.db.doc(`churches/${cid}/members/${editedBy}`).get() : null,
  ]);
  if (!isChurchOpen(church)) return null;
  const list = (services.get('services') as { id: string; name: string }[] | undefined) ?? [];
  const title = event ? ((doc?.get('title') as string | undefined) ?? '') : '';
  return {
    ...diff,
    church,
    dateKey,
    serviceId: serviceId ?? null,
    serviceName: event ? title : (list.find((s) => s.id === serviceId)?.name ?? ''),
    event: event ? { id: doc!.get('eventId') as string, title } : null,
    movedFrom,
    holders: dutiesByUid(after?.exists ? after.get('duties') : []),
    // A deleted day keeps the way it was last written: taking back an
    // import removes days no push announced, so none announces their going.
    via: (doc?.get('via') as string | undefined) ?? 'app',
    editor: editedBy ? { uid: editedBy, name: (editor?.get('name') as string | undefined) || null } : null,
  };
}

/** `M/D` of a `YYYY-MM-DD` day, as pushes say it. */
export function shortDate(dateKey: string) {
  const [, m, d] = dateKey.split('-').map(Number);
  return `${m}/${d}`;
}

const WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六'];

/** `M/D（週X）` of a `YYYY-MM-DD` day. */
export function dateWithWeekday(dateKey: string) {
  const [y, m, d] = dateKey.split('-').map(Number);
  return `${shortDate(dateKey)}（週${WEEKDAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()]}）`;
}

/**
 * Pushes to each person put on or taken off a duty. The editor is not told
 * about their own change. An event's roster moved to another day tells
 * everyone on it. (One cancelled with its event never gets here: see
 * readRosterChange.) Returns how many devices it reached.
 */
export async function pushRosterChange(deps: PushDeps, c: RosterChange) {
  const cid = c.church.id;
  const title = c.church.get('name') as string;
  const link = c.event ? `/rosters/event/${c.event.id}` : `/rosters/${c.serviceId}/${c.dateKey}`;
  const day = `${shortDate(c.dateKey)} ${c.serviceName}`;
  let sent = 0;
  if (c.event && c.movedFrom) {
    const body = `${c.event.title}改到 ${dateWithWeekday(c.dateKey)}`;
    for (const uid of c.holders.keys()) {
      if (uid === c.editor?.uid) continue;
      sent += await notifyMembers(deps, cid, [uid], 'rosterChange', { title, body, link });
    }
  }
  for (const [uid, roles] of c.added) {
    if (uid === c.editor?.uid) continue;
    sent += await notifyMembers(deps, cid, [uid], 'rosterChange', { title, body: `你被排進 ${day}：${roles.join('、')}`, link });
  }
  for (const [uid, roles] of c.removed) {
    if (uid === c.editor?.uid) continue;
    sent += await notifyMembers(deps, cid, [uid], 'rosterChange', { title, body: `${day} 的${roles.join('、')}已改由別人負責`, link });
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
