import type { DocumentSnapshot } from 'firebase-admin/firestore';

import type { Deps } from './common.js';
import { isCancelled, isEvent } from './eventRosters.js';

/**
 * A roster day (rosters/{dateKey}_{service}, or an event's ev_{event id})
 * as the people on it see it: what it is called, its days, who holds what.
 */

interface Duty {
  role?: unknown;
  people?: unknown;
  uids?: unknown;
}

export const duties = (v: unknown) => (Array.isArray(v) ? (v as Duty[]) : []).filter((d) => typeof d?.role === 'string');
export const names = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

/**
 * uid → the duties they hold on this roster, each once: a name bound to
 * them that is still listed (testdata/church_rules.json, rosterIdentity).
 */
export function dutiesByUid(value: unknown): Map<string, string[]> {
  const out = new Map<string, string[]>();
  for (const d of duties(value)) {
    const people = names(d.people);
    if (!d.uids || typeof d.uids !== 'object' || Array.isArray(d.uids)) continue;
    for (const [name, uid] of Object.entries(d.uids as Record<string, unknown>)) {
      if (typeof uid !== 'string' || !uid || uid.includes('/') || !people.includes(name)) continue;
      const held = out.get(uid) ?? [];
      if (!held.includes(d.role as string)) out.set(uid, [...held, d.role as string]);
    }
  }
  return out;
}

/** A service's name by its id; '' for one the church no longer has. */
export type ServiceNames = (serviceId: string) => string;

/** The church's services' names, read once. */
export async function serviceNames(deps: Pick<Deps, 'db'>, cid: string): Promise<ServiceNames> {
  const settings = await deps.db.doc(`churches/${cid}/settings/services`).get();
  const list = (settings.get('services') as { id: string; name: string }[] | undefined) ?? [];
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

/** [d] as a roster day; null when it is none (gone, or without its day or service). */
export function rosterDay(d: DocumentSnapshot | undefined): RosterDay | null {
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
    holders: dutiesByUid(d.get('duties')),
    name: (services) => (event ? title : services(serviceId!)),
  };
}
