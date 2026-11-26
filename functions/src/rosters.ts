import type { DocumentSnapshot } from 'firebase-admin/firestore';

import type { Deps } from './common.js';
import { isCancelled, isEvent } from './eventRosters.js';
import type { Words } from './languages.js';

/**
 * A roster day (rosters/{dateKey}_{service}, or an event's ev_{event id})
 * as the people on it see it: what it is called, its days, who holds what.
 */

interface Duty {
  role?: unknown;
  people?: unknown;
  uids?: unknown;
  /** 服事交給小組: a name in `people` that is a 小組, to its id. */
  groups?: unknown;
}

export const duties = (v: unknown) => (Array.isArray(v) ? (v as Duty[]) : []).filter((d) => typeof d?.role === 'string');
export const names = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

/** 小組 id → the uids (and ids of the 同工 without an account) in it. */
export type GroupMembers = ReadonlyMap<string, readonly string[]>;

const GROUP = '\u001f';

/**
 * A duty held as one of 小組 [id]: by its id, so renaming the 小組 changes
 * nobody's duties. Said with its name ([shownDuties]).
 */
export const groupDuty = (role: string, id: string) => `${role}${GROUP}${id}`;

/** The 小組 a duty is held as one of ([groupDuty]), by id: their names, for [shownDuties]. */
export type GroupNames = ReadonlyMap<string, string>;

/** The names of the 小組 [roles] (holders', [dutiesByUid]) are held as one of. */
export async function groupNamesIn(deps: Pick<Deps, 'db'>, cid: string, roles: string[]): Promise<GroupNames> {
  const ids = [...new Set(roles.filter((r) => r.includes(GROUP)).map((r) => r.slice(r.indexOf(GROUP) + 1)))];
  if (ids.length === 0) return new Map();
  const docs = await deps.db.getAll(...ids.map((id) => deps.db.doc(`churches/${cid}/smallGroups/${id}`)));
  return new Map(docs.filter((d) => typeof d.get('name') === 'string').map((d) => [d.id, d.get('name') as string]));
}

/**
 * [roles] (a holder's, [dutiesByUid]) as said in [w]: one held as one of a
 * 小組 with the 小組's name ([names]); just the duty, once it is gone.
 */
export const shownDuties = (w: Words, roles: string[], names: GroupNames) =>
  roles.map((r) => {
    if (!r.includes(GROUP)) return r;
    const role = r.slice(0, r.indexOf(GROUP));
    const name = names.get(r.slice(r.indexOf(GROUP) + 1));
    return name ? w.groupDuty(role, name) : role;
  });

/** A duty's `groups`, name → 小組 id, those still listed. */
function groupsOf(d: Duty): [string, string][] {
  if (!d.groups || typeof d.groups !== 'object' || Array.isArray(d.groups)) return [];
  const people = names(d.people);
  return Object.entries(d.groups as Record<string, unknown>).filter(
    (e): e is [string, string] => typeof e[1] === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(e[1]) && people.includes(e[0]),
  );
}

/** The 小組 given a duty on any of [values] (rosters' duties), by id. */
export const groupIdsOn = (...values: unknown[]) => [
  ...new Set(values.flatMap((v) => duties(v).flatMap((d) => groupsOf(d).map(([, id]) => id)))),
];

/** Who is in each of [ids] (小組) of church [cid]: members and the 同工 without an account. */
export async function groupMembersOf(deps: Pick<Deps, 'db'>, cid: string, ids: string[]): Promise<GroupMembers> {
  const out = new Map<string, string[]>();
  for (let i = 0; i < ids.length; i += 30) {
    const some = ids.slice(i, i + 30);
    const found = await Promise.all(
      ['members', 'pendingMembers'].map((c) =>
        deps.db.collection(`churches/${cid}/${c}`).where('smallGroups', 'array-contains-any', some).get(),
      ),
    );
    for (const doc of found.flatMap((q) => q.docs)) {
      const theirs = doc.get('smallGroups');
      for (const id of some) if (Array.isArray(theirs) && theirs.includes(id)) out.set(id, [...(out.get(id) ?? []), doc.id]);
    }
  }
  return out;
}

/** [groupMembersOf] the 小組 given a duty on any of [values] (rosters' duties). */
export const groupMembersOn = (deps: Pick<Deps, 'db'>, cid: string, ...values: unknown[]) =>
  groupMembersOf(deps, cid, groupIdsOn(...values));

/**
 * uid → the duties they hold on this roster, each once: a name bound to
 * them that is still listed (testdata/church_rules.json, rosterIdentity);
 * and, as one of a 小組 a duty is given to ([groups]: who is in each), the
 * duty said with the 小組 ([groupDuty]), unless they hold it by name.
 */
export function dutiesByUid(value: unknown, groups: GroupMembers = new Map()): Map<string, string[]> {
  const out = new Map<string, string[]>();
  const hold = (uid: string, role: string) => {
    const held = out.get(uid) ?? [];
    if (!held.includes(role)) out.set(uid, [...held, role]);
  };
  for (const d of duties(value)) {
    const people = names(d.people);
    if (!d.uids || typeof d.uids !== 'object' || Array.isArray(d.uids)) continue;
    for (const [name, uid] of Object.entries(d.uids as Record<string, unknown>)) {
      if (typeof uid !== 'string' || !uid || uid.includes('/') || !people.includes(name)) continue;
      hold(uid, d.role as string);
    }
  }
  for (const d of duties(value)) {
    for (const [, id] of groupsOf(d)) {
      for (const uid of groups.get(id) ?? []) {
        if (!(out.get(uid) ?? []).includes(d.role as string)) hold(uid, groupDuty(d.role as string, id));
      }
    }
  }
  return out;
}

/**
 * The services in settings/services [doc] the church has: not one deleted
 * (taken off the list), nor one turned off (停用) before 聚會 could be
 * deleted, which is as good as deleted.
 */
export function keptServices<T extends object>(doc: DocumentSnapshot): T[] {
  const list = doc.get('services');
  return Array.isArray(list) ? (list as (T & { enabled?: unknown })[]).filter((s) => s?.enabled !== false) : [];
}

/** A service's name by its id; '' for one the church no longer has (deleted). */
export type ServiceNames = (serviceId: string) => string;

/** The church's services' names, read once. */
export async function serviceNames(deps: Pick<Deps, 'db'>, cid: string): Promise<ServiceNames> {
  const settings = await deps.db.doc(`churches/${cid}/settings/services`).get();
  const list = keptServices<{ id: string; name: string }>(settings);
  const byId = new Map(list.map((s) => [s.id, s.name]));
  return (id) => byId.get(id) ?? '';
}

export interface RosterDay {
  dateKey: string;
  /** The last day it is on: an event's end, else [dateKey]. */
  lastDay: string;
  /** The service; null for an event's roster. */
  serviceId: string | null;
  /** For an event's roster (活動的服事表): the calendar event. */
  event: { id: string; title: string } | null;
  /** An event's roster cancelled with its event: not shown, not reminded. */
  cancelled: boolean;
  /** uid → their duties on it. */
  holders: Map<string, string[]>;
  /** The service's name, or the event's title. */
  name(services: ServiceNames): string;
}

/** The app's page of [day]'s roster. */
export function rosterLink(day: Pick<RosterDay, 'dateKey' | 'serviceId' | 'event'>) {
  return day.event ? `/rosters/event/${day.event.id}` : `/rosters/${day.serviceId}/${day.dateKey}`;
}

/**
 * [d] as a roster day; null when it is none (gone, or without its day or
 * service). [groups]: who is in the 小組 its duties are given to.
 */
export function rosterDay(d: DocumentSnapshot | undefined, groups: GroupMembers = new Map()): RosterDay | null {
  if (!d?.exists) return null;
  const dateKey = d.get('dateKey') as string | undefined;
  const event = isEvent(d);
  const serviceId = event ? null : ((d.get('type') as string | undefined) ?? null);
  const lastDay = event ? ((d.get('endDateKey') as string | undefined) ?? dateKey) : dateKey;
  if (!dateKey || !lastDay || (!event && !serviceId)) return null;
  const title = event ? ((d.get('title') as string | undefined) ?? '') : '';
  return {
    dateKey,
    lastDay,
    serviceId,
    event: event ? { id: d.get('eventId') as string, title } : null,
    cancelled: isCancelled(d),
    holders: dutiesByUid(d.get('duties'), groups),
    name: (services) => (event ? title : services(serviceId!)),
  };
}
