import { isDeepStrictEqual } from 'node:util';

import { churchAccess, churchClosed, isChurchOpen } from './access.js';
import { weekdayOf } from './attendance.js';
import { fail, id, record, serverTime, type Caller, type Deps } from './common.js';
import { LIMITS } from './limits.js';

interface Service {
  id: string;
  name: string;
  /** The first of [weekdays] when it has them, as older apps read it. */
  weekday: number;
  /** The days it meets, in order, when more than one; absent for one day. */
  weekdays?: number[];
  /** On its one day every other week (2) from [startsOn], a day it meets; absent for every week. */
  every?: 2;
  startsOn?: string;
  /** On its one day, those weeks of each month (1–4, in order); absent for every week. */
  monthWeeks?: number[];
  enabled: boolean;
  duties: string[];
  events: { name: string; color: number }[];
  /** The duties that take several people; absent until an admin sets one. */
  manyDuties?: string[];
}

interface DutyRename { from: string; to: string }

function exactKeys(value: Record<string, unknown>, keys: string[]) {
  if (Object.keys(value).length !== keys.length || keys.some((k) => !Object.hasOwn(value, k))) fail('invalid-argument', 'unknown');
}

function label(value: unknown): string {
  if (typeof value !== 'string' || !value.trim()) fail('invalid-argument', 'unknown');
  return value;
}

function service(value: unknown): Service {
  const s = record(value);
  exactKeys(s, [
    'id', 'name', 'weekday', 'enabled', 'duties', 'events',
    ...['weekdays', 'every', 'startsOn', 'monthWeeks', 'manyDuties'].filter((k) => Object.hasOwn(s, k)),
  ]);
  const serviceId = id(s.id);
  const name = label(s.name);
  if (!Number.isInteger(s.weekday) || (s.weekday as number) < 1 || (s.weekday as number) > 7 || typeof s.enabled !== 'boolean') {
    fail('invalid-argument', 'unknown');
  }
  let weekdays: number[] | undefined;
  if (Object.hasOwn(s, 'weekdays')) {
    // Two or more, in order, the first its weekday.
    if (!Array.isArray(s.weekdays) || s.weekdays.length < 2 || s.weekdays[0] !== s.weekday
        || s.weekdays.some((d, i) => !Number.isInteger(d) || d < 1 || d > 7 || (i > 0 && d <= (s.weekdays as number[])[i - 1]))) {
      fail('invalid-argument', 'unknown');
    }
    weekdays = s.weekdays as number[];
  }
  if (!validServiceTime(weekdays ?? [s.weekday as number], s.every, s.startsOn, s.monthWeeks)
      || (Object.hasOwn(s, 'every') && s.every !== 2)) fail('invalid-argument', 'unknown');
  const time = {
    ...(s.every === 2 && { every: 2 as const, startsOn: s.startsOn as string }),
    ...(Object.hasOwn(s, 'monthWeeks') && { monthWeeks: s.monthWeeks as number[] }),
  };
  if (!Array.isArray(s.duties) || !Array.isArray(s.events)) fail('invalid-argument', 'unknown');
  const duties = s.duties.map(label);
  const events = s.events.map((value) => {
    const e = record(value);
    exactKeys(e, ['name', 'color']);
    if (!Number.isInteger(e.color)) fail('invalid-argument', 'unknown');
    return { name: label(e.name), color: e.color as number };
  });
  let manyDuties: string[] | undefined;
  if (Object.hasOwn(s, 'manyDuties')) {
    if (!Array.isArray(s.manyDuties)) fail('invalid-argument', 'unknown');
    manyDuties = s.manyDuties.map(label);
  }
  if (!validServiceShape(duties, events, manyDuties)) fail('invalid-argument', 'unknown');
  return {
    id: serviceId, name, weekday: s.weekday as number, ...(weekdays && { weekdays }), ...time,
    enabled: s.enabled, duties, events, ...(manyDuties && { manyDuties }),
  };
}

function rename(value: unknown, before: Service, after: Service): DutyRename | undefined {
  if (value === undefined) return undefined;
  const r = record(value);
  exactKeys(r, ['from', 'to']);
  const from = label(r.from);
  const to = label(r.to);
  if (!validDutyRename(before.duties, after.duties, from, to)) fail('invalid-argument', 'unknown');
  // 可以排好幾位 goes with the duty under its new name.
  if (!isDeepStrictEqual(after.manyDuties, before.manyDuties?.map((d) => d === from ? to : d))) fail('invalid-argument', 'unknown');
  return { from, to };
}

/**
 * Whether a service with [duties], [events] and [manyDuties] (多人服事;
 * none: never set) may be saved: no duty or 特別活動 name twice, each
 * 特別活動 in one of the six colors, 多人服事 only of its duties, each once
 * (testdata/church_rules.json, serviceShape).
 */
export function validServiceShape(duties: string[], events: { name: string; color: number }[], manyDuties?: string[]) {
  const names = events.map((e) => e.name);
  return new Set(duties).size === duties.length && new Set(names).size === names.length
    && events.every((e) => e.color >= 0 && e.color <= 5)
    && (manyDuties === undefined || (new Set(manyDuties).size === manyDuties.length && manyDuties.every((d) => duties.includes(d))));
}

/**
 * Whether a service's 聚會時間 may be saved: every week on its [weekdays];
 * or on one weekday, every other week ([every] 2) from [startsOn], a day
 * on it, or on [monthWeeks] (1–4, in order) of each month
 * (testdata/church_rules.json, serviceTime).
 */
export function validServiceTime(weekdays: number[], every: unknown, startsOn: unknown, monthWeeks: unknown) {
  const often = every ?? 1;
  if (often !== 1 && often !== 2) return false;
  if ((often === 2) !== (startsOn !== undefined)) return false;
  if (startsOn !== undefined
      && (typeof startsOn !== 'string' || !DAY.test(startsOn) || new Date(`${startsOn}T00:00:00Z`).toISOString().slice(0, 10) !== startsOn
        || weekdays.length !== 1 || weekdayOf(startsOn) !== weekdays[0])) {
    return false;
  }
  if (monthWeeks === undefined) return true;
  return Array.isArray(monthWeeks) && monthWeeks.length > 0 && weekdays.length === 1 && often === 1
    && monthWeeks.every((w, i) => Number.isInteger(w) && w >= 1 && w <= LIMITS.monthWeeks && (i === 0 || w > monthWeeks[i - 1]));
}

const DAY = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

/**
 * Whether [after] is [before] with duty [from] renamed [to] in place and
 * nothing else changed (testdata/church_rules.json, dutyRename).
 */
export function validDutyRename(before: string[], after: string[], from: string, to: string) {
  return from !== to && before.includes(from) && !before.includes(to)
    && isDeepStrictEqual(after, before.map((d) => d === from ? to : d));
}

/** Edits one configured service; saved roster wording is never rewritten here. */
export async function editService(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'admin');
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'before', 'after', 'dutyRename'].includes(k))) fail('invalid-argument', 'unknown');
  const before = service(input.before);
  const after = service(input.after);
  if (before.id !== after.id) fail('invalid-argument', 'unknown');
  const dutyRename = rename(input.dutyRename, before, after);
  await deps.db.runTransaction(async (tx) => {
    const ref = deps.db.doc(`churches/${cid}/settings/services`);
    const [church, admin, settings] = await tx.getAll(
      deps.db.doc(`churches/${cid}`), deps.db.doc(`churches/${cid}/members/${c.uid}`), ref,
    );
    // Serialize authorization with all writes, not just the initial callable check.
    if (!admin.exists) fail('permission-denied', 'permissionDenied');
    if (!isChurchOpen(church)) churchClosed();
    if (admin.get('role') !== 'admin') fail('permission-denied', 'permissionDenied');
    const services = settings.get('services') as Service[] | undefined;
    const ids = settings.get('ids') as string[] | undefined;
    if (!Array.isArray(services) || services.length < 1 || services.length > LIMITS.services
        || !Array.isArray(ids) || ids.length > 100) fail('failed-precondition', 'unknown', 'invalidServiceSettings');
    if (!isDeepStrictEqual(services.find((s) => s.id === before.id), before)) fail('aborted', 'conflict');
    if (dutyRename) {
      const [members, pending, order, ministries] = await Promise.all([
        tx.get(deps.db.collection(`churches/${cid}/members`)),
        tx.get(deps.db.collection(`churches/${cid}/pendingMembers`)),
        tx.get(deps.db.doc(`churches/${cid}/staff_orders/${before.id}`)),
        tx.get(deps.db.doc(`churches/${cid}/settings/ministries`)),
      ]);
      const roles = order.get('roles') as Record<string, string[]> | undefined;
      if (roles && Object.hasOwn(roles, dutyRename.to)) fail('aborted', 'conflict');
      // Count settings and staff order too. A refused transaction commits none
      // of its queued updates; never split one rename into partial batches.
      let writeCount = 1 + (roles && Object.hasOwn(roles, dutyRename.from) ? 1 : 0);
      for (const member of [...members.docs, ...pending.docs]) {
        const zones = (member.get('zones') ?? []) as { serviceType: string; duties: string[] }[];
        let changed = false;
        const next = zones.map((z) => {
          if (z.serviceType !== before.id || !z.duties.includes(dutyRename.from)) return z;
          changed = true;
          return { ...z, duties: [...new Set(z.duties.map((d) => d === dutyRename.from ? dutyRename.to : d))] };
        });
        if (changed) {
          if (++writeCount > 500) fail('resource-exhausted', 'quotaExceeded', 'tooManyChanges');
          tx.update(member.ref, { zones: next });
        }
      }
      // The 事工 that link the duty (#82) keep leading it under its new name.
      const linked = ministries.get('ministries') as { duties?: { service: string; duty: string }[] }[] | undefined;
      const renamed = (d: { service: string; duty: string }) => d.service === before.id && d.duty === dutyRename.from;
      if (Array.isArray(linked) && linked.some((m) => (m.duties ?? []).some(renamed))) {
        if (++writeCount > 500) fail('resource-exhausted', 'quotaExceeded', 'tooManyChanges');
        tx.update(ministries.ref, {
          ministries: linked.map((m) => ({
            ...m,
            ...(m.duties && { duties: m.duties.map((d) => (renamed(d) ? { ...d, duty: dutyRename.to } : d)) }),
          })),
        });
      }
      if (roles && Object.hasOwn(roles, dutyRename.from)) {
        const next = { ...roles, [dutyRename.to]: roles[dutyRename.from] };
        delete next[dutyRename.from];
        tx.update(order.ref, { roles: next });
      }
    }
    const next = services.map((s) => s.id === before.id ? after : s);
    tx.update(ref, {
      services: next,
      // An older app's write of the list would lose `weekdays`: firestore.rules turns it away.
      severalDays: next.some((s) => Array.isArray(s.weekdays)),
      // So is a service's every other week or some weeks of each month.
      repeats: next.some((s) => s.every === 2 || Array.isArray(s.monthWeeks)),
      updatedAt: serverTime(),
    });
  });
  return {};
}
