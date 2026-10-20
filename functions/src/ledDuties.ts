import { FieldValue, type DocumentSnapshot } from 'firebase-admin/firestore';
import { isDeepStrictEqual } from 'node:util';

import { churchAccess, churchClosed, isChurchOpen } from './access.js';
import { fail, type Caller, type Deps } from './common.js';

/**
 * A 事工's 負責人 (#82) arranging the duties it leads: 敬拜團's leader puts
 * people on 司琴 and 敬拜, in any service and on any event, and touches
 * nothing else on the day. The rules cannot tell one duty from another in
 * a roster's duties list, so these writes come here instead of going to
 * Firestore.
 *
 * Like the app's own roster writes, a compare-and-set: [before] is the
 * days as the app showed them, refused with conflict once any differs from
 * what is stored, so nobody's newer change is overwritten.
 */

interface Duty {
  role: string;
  people: string[];
  uids: Record<string, string>;
}

type Roster = Record<string, unknown> & { duties: Duty[] };

/** What makes a day what it is; the rest (updatedAt, via, movedBy) is bookkeeping. */
const CONTENT = ['type', 'kind', 'eventId', 'title', 'dateKey', 'endDateKey', 'calendarId', 'recurringEventId', 'originalStart', 'duties', 'events'];

/**
 * [data]'s content as the app encodes it (rosterToJson): no events or
 * duties is an empty list, and a name's uid counts only while the name is
 * listed. Days written by older versions or the backend compare equal to
 * the app's copy of them.
 */
function content(data: Record<string, unknown> | undefined) {
  if (data === undefined) return null;
  const out: Record<string, unknown> = Object.fromEntries(CONTENT.filter((k) => k in data).map((k) => [k, data[k]]));
  out.events = Array.isArray(data.events) ? data.events : [];
  out.duties = (Array.isArray(data.duties) ? data.duties : []).map((d: Record<string, unknown>) => {
    const people = Array.isArray(d?.people) ? (d.people as unknown[]) : [];
    const uids = d?.uids && typeof d.uids === 'object' ? (d.uids as Record<string, unknown>) : {};
    return {
      role: d?.role,
      people,
      uids: Object.fromEntries(Object.entries(uids).filter(([name]) => people.includes(name))),
    };
  });
  return out;
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('invalid-argument', 'unknown');
  return value as Record<string, unknown>;
}

function duty(value: unknown): Duty {
  const d = record(value);
  const people = d.people;
  const uids = record(d.uids ?? {});
  if (typeof d.role !== 'string' || !Array.isArray(people) || people.some((p) => typeof p !== 'string')
      || Object.values(uids).some((u) => typeof u !== 'string')) fail('invalid-argument', 'unknown');
  return { role: d.role, people: people as string[], uids: uids as Record<string, string> };
}

function roster(value: unknown): Roster | null {
  if (value === null) return null;
  const r = record(value);
  if (!Array.isArray(r.duties)) fail('invalid-argument', 'unknown');
  return { ...r, duties: r.duties.map(duty) };
}

/** The duties [lead] leads on [day]: a service's by service, an event's (in no service) by name. */
function ledRoles(ministries: { id: string; duties: { service: string; duty: string }[] }[], led: string[], day: Roster) {
  const type = day.kind === 'event' ? null : day.type;
  return new Set(
    ministries
      .filter((m) => led.includes(m.id))
      .flatMap((m) => m.duties)
      .filter((d) => type === null || d.service === type)
      .map((d) => d.duty),
  );
}

const DAY = /^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/;
const isText = (v: unknown, max: number) => v === undefined || (typeof v === 'string' && v.length <= max);

/**
 * A day [id] that is not made yet, as firestore.rules would take it from
 * an editor: a service's day of a service the church has, or an event's
 * roster. Fails with invalid-argument when it is neither.
 */
function newDay(id: string, day: Roster, serviceTypes: string[]) {
  const keys = Object.keys(day);
  const ok = day.kind === 'event'
    ? keys.every((k) => ['kind', 'eventId', 'title', 'dateKey', 'endDateKey', 'duties', 'events', 'calendarId', 'recurringEventId', 'originalStart'].includes(k))
      && typeof day.eventId === 'string' && id === `ev_${day.eventId}`
      && typeof day.title === 'string' && day.title.length <= 800
      && typeof day.dateKey === 'string' && DAY.test(day.dateKey)
      && typeof day.endDateKey === 'string' && DAY.test(day.endDateKey) && day.endDateKey >= day.dateKey
      && isText(day.calendarId, 1024) && isText(day.recurringEventId, 1024) && isText(day.originalStart, 64)
    : keys.every((k) => ['type', 'dateKey', 'duties', 'events'].includes(k))
      && typeof day.type === 'string' && serviceTypes.includes(day.type)
      && typeof day.dateKey === 'string' && DAY.test(day.dateKey) && id === `${day.dateKey}_${day.type}`;
  if (!ok || !(day.events === undefined || (Array.isArray(day.events) && day.events.length === 0))) {
    fail('invalid-argument', 'unknown');
  }
}

/** Whether [after] differs from [before] only in [roles]. */
function onlyIn(roles: Set<string>, before: Roster, after: Roster) {
  const { duties: b, ...restBefore } = before;
  const { duties: a, ...restAfter } = after;
  if (!isDeepStrictEqual(content(restBefore), content(restAfter))) return false;
  const others = (ds: Duty[]) => ds.filter((d) => !roles.has(d.role));
  return isDeepStrictEqual(others(b), others(a));
}

export async function editLedDuties(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'member');
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'before', 'after', 'via'].includes(k))) fail('invalid-argument', 'unknown');
  const before = record(input.before);
  const after = record(input.after);
  const ids = Object.keys(after);
  if (ids.length === 0 || ids.length > 20 || !isDeepStrictEqual(Object.keys(before).sort(), [...ids].sort())
      || ids.some((id) => !/^[A-Za-z0-9_-]{1,200}$/.test(id))) fail('invalid-argument', 'unknown');
  const via = input.via;
  if (typeof via !== 'string' || via.length > 32) fail('invalid-argument', 'unknown');

  await deps.db.runTransaction(async (tx) => {
    const refs = ids.map((id) => deps.db.doc(`churches/${cid}/rosters/${id}`));
    const [church, me, settings, services, ...days] = (await tx.getAll(
      deps.db.doc(`churches/${cid}`),
      deps.db.doc(`churches/${cid}/members/${c.uid}`),
      deps.db.doc(`churches/${cid}/settings/ministries`),
      deps.db.doc(`churches/${cid}/settings/services`),
      ...refs,
    )) as DocumentSnapshot[];
    // Checked again inside: a lead taken away meanwhile writes nothing.
    if (!me.exists) fail('permission-denied', 'permissionDenied');
    if (!isChurchOpen(church)) churchClosed();
    const led = (me.get('leadMinistries') as string[] | undefined) ?? [];
    const ministries = (settings.get('ministries') as { id: string; duties: { service: string; duty: string }[] }[] | undefined) ?? [];
    for (const [i, id] of ids.entries()) {
      const stored = days[i];
      const was = roster(before[id]);
      const next = roster(after[id]);
      if (!isDeepStrictEqual(content(stored.exists ? stored.data() : undefined), was === null ? null : content(was))) {
        fail('aborted', 'conflict');
      }
      if (next === null || stored.get('cancelledAt') !== undefined) fail('permission-denied', 'permissionDenied');
      if (was === null) {
        newDay(id, next, (services.get('ids') as string[] | undefined) ?? []);
        const roles = ledRoles(ministries, led, next);
        if (next.duties.some((d) => !roles.has(d.role))) fail('permission-denied', 'permissionDenied');
        tx.create(refs[i], { ...next, events: [], via, updatedAt: FieldValue.serverTimestamp() });
        continue;
      }
      if (!onlyIn(ledRoles(ministries, led, was), was, next)) fail('permission-denied', 'permissionDenied');
      tx.update(refs[i], { duties: next.duties, via, updatedAt: FieldValue.serverTimestamp() });
    }
  });
}
