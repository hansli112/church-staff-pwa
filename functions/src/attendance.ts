import { FieldValue, type DocumentSnapshot } from 'firebase-admin/firestore';

import { churchAccess, isChurchOpen } from './access.js';
import { fail, record, type Caller, type Deps } from './common.js';
import { LIMITS, TEXT_LIMITS, withinTextLimit } from './limits.js';
import { groupOf, powersOf, type ChurchGroup } from './powers.js';
import { notifyMembers, type PushDeps } from './push.js';
import { dateKeyIn, timeZoneOf, timeZonesAt } from './timeZones.js';

/**
 * 回報人數 (#85): a church that turned it on (`attendanceSince` on the
 * church doc, the day it did) asks the leads of each group how many came
 * to its meetings. A group is a service (`service:<id>`) or a 小組
 * (`small:<id>`); its 人數 are churches/{cid}/attendance/{key}/days/{dateKey}
 * (`count` and `note`, or `none` for 這次沒聚會), and its pauses
 * (`pauses`, each `{from, until}`, kept once over so the weeks they
 * covered never turn 未填) are on attendance/{key} itself. The app writes
 * them; firestore.rules keeps who may, as powers.ts writesAttendance.
 */

/** The hour the leads are asked, on each church's clock. */
export const ATTENDANCE_HOUR = 21;

/**
 * When a group meets. A service: on its [weekday], when that day has a
 * roster ([roster], whether it has). A 小組: on [weekday], every [every]
 * weeks (1 or 2) from [startsOn], a day it met.
 */
export interface Meets {
  weekday?: number;
  roster?: boolean;
  every?: number;
  startsOn?: string;
}

/** A pause: no meeting asked for from [from] until, not including, [until]. */
export interface Pause {
  from: string;
  until: string;
}

/** The church's 回報人數: on since [since]; the group's [pauses]. */
export interface AttendanceState {
  since: string;
  pauses: Pause[];
}

const WEEK_MS = 7 * 86_400_000;
const dayMs = (day: string) => Date.parse(`${day}T00:00:00Z`);

/** 1 = Monday … 7 = Sunday. */
export const weekdayOf = (day: string) => ((new Date(dayMs(day)).getUTCDay() + 6) % 7) + 1;

/**
 * Whether a group that [meets] so meets on [day] and is asked its 人數
 * (testdata/church_rules.json, attendanceDue).
 */
export function attendanceDue(meets: Meets, state: AttendanceState, day: string): boolean {
  if (day < state.since) return false;
  if (state.pauses.some((p) => p.from <= day && day < p.until)) return false;
  if (meets.weekday === undefined || weekdayOf(day) !== meets.weekday) return false;
  if ('roster' in meets) return meets.roster === true;
  const every = meets.every === 2 ? 2 : 1;
  if (!meets.startsOn) return every === 1;
  if (day < meets.startsOn) return false;
  return Math.floor((dayMs(day) - dayMs(meets.startsOn)) / WEEK_MS) % every === 0;
}

/** A group that may meet on a day: its key, its name, the member field naming who leads it, and when it meets. */
interface Due {
  key: string;
  name: string;
  leads: { field: 'leadTypes' | 'leadSmallGroups'; id: string };
  meets: Meets;
}

/** Where a reminder of group [key]'s meeting on [day] takes its 負責人: that meeting's 填寫人數. */
export const fillLink = (key: string, day: string) => `/home?fill=${key}&day=${day}`;

/**
 * Run every hour on the hour: in the churches with 回報人數 on whose clock
 * says [ATTENDANCE_HOUR], one push to the leads of each group that met
 * today and has no 人數 yet (powers.ts remindedOfAttendance: a service's 負責人,
 * not its 牧者; a 小組's 小組長), and one more for yesterday's still
 * without (#93), unless they muted 回報人數提醒. Someone having filled it
 * in, marked 這次沒聚會, or met it with another 小組, asks no one; nobody
 * is asked a third time.
 */
export async function sendAttendanceReminders(deps: PushDeps & { now: () => Date }) {
  const now = deps.now();
  const due = timeZonesAt([ATTENDANCE_HOUR], now);
  if (due.size === 0) return 0;
  const churches = await deps.db.collection('churches').where('attendanceSince', '>', '').get();
  let sent = 0;
  for (const church of churches.docs) {
    if (!isChurchOpen(church) || !due.has(timeZoneOf(church))) continue;
    const cid = church.id;
    const today = dateKeyIn(timeZoneOf(church), now);
    const yesterday = new Date(dayMs(today) - 86_400_000).toISOString().slice(0, 10);
    const since = church.get('attendanceSince') as string;
    for (const [day, again] of [[today, false], [yesterday, true]] as const) {
      for (const g of await dueOn(deps, cid, day)) {
        const uids = await stillAsked(deps, cid, g, day, since);
        if (uids === null) continue;
        sent += await notifyMembers(deps, cid, uids, 'attendance', (w) => ({
          title: w.attendanceTitle,
          body: (again ? w.attendanceAgainBody : w.attendanceBody)(g.name, w.dateWithWeekday(day)),
          link: fillLink(g.key, day),
        }));
      }
    }
  }
  return sent;
}

/**
 * Whom to ask for [g]'s 人數 of [day]: those reminded of it (powers.ts
 * remindedOfAttendance); null when nobody is to be asked, the day having
 * them already or the group not meeting then.
 */
async function stillAsked(deps: { db: PushDeps['db'] }, cid: string, g: Due, day: string, since: string) {
  const [state, filled] = await deps.db.getAll(
    deps.db.doc(`churches/${cid}/attendance/${g.key}`),
    deps.db.doc(`churches/${cid}/attendance/${g.key}/days/${day}`),
  );
  if (filled.exists) return null;
  if (!attendanceDue(g.meets, { since, pauses: pausesOf(state) }, day)) return null;
  const leads = await deps.db
    .collection(`churches/${cid}/members`)
    .where(g.leads.field, 'array-contains', g.leads.id)
    .get();
  return leads.docs.filter((m) => powersOf(m.data()).remindedOfAttendance(groupOf(g.key)!)).map((m) => m.id);
}

/** The pauses attendance/{key} has. */
export function pausesOf(d: DocumentSnapshot | undefined): Pause[] {
  const list = d?.get('pauses');
  return (Array.isArray(list) ? list : []).filter(
    (p): p is Pause => typeof p?.from === 'string' && typeof p?.until === 'string',
  );
}

type Service = { id: string; name?: string; weekday?: number; enabled?: boolean };

/**
 * When service [s] meets on [day]: on its weekday when that day has a
 * roster ([roster]), or every week with 每週都填人數 on ([state],
 * attendance/service:<id>, #93).
 */
function serviceMeets(s: Service, roster: boolean, state: DocumentSnapshot | undefined): Meets {
  return state?.get('everyWeek') === true ? { weekday: s.weekday } : { weekday: s.weekday, roster };
}

/** The services and 小組 of church [cid] meeting on [day], before pauses and what was filled in. */
async function dueOn(deps: { db: PushDeps['db'] }, cid: string, day: string): Promise<Due[]> {
  const weekday = weekdayOf(day);
  const [services, smallGroups] = await Promise.all([
    deps.db.doc(`churches/${cid}/settings/services`).get(),
    deps.db.collection(`churches/${cid}/smallGroups`).where('weekday', '==', weekday).get(),
  ]);
  const meetingServices = ((services.get('services') as Service[] | undefined) ?? [])
    .filter((s) => s.enabled !== false && s.weekday === weekday);
  const [rosters, states] = meetingServices.length === 0
    ? [[], []]
    : await Promise.all([
      deps.db.getAll(...meetingServices.map((s) => deps.db.doc(`churches/${cid}/rosters/${day}_${s.id}`))),
      deps.db.getAll(...meetingServices.map((s) => deps.db.doc(`churches/${cid}/attendance/service:${s.id}`))),
    ]);
  return [
    ...meetingServices.map((s, i) => ({
      key: `service:${s.id}`,
      name: s.name ?? '',
      leads: { field: 'leadTypes' as const, id: s.id },
      meets: serviceMeets(s, rosters[i].exists, states[i]),
    })),
    ...smallGroups.docs.map((g) => ({
      key: `small:${g.id}`,
      name: (g.get('name') as string | undefined) ?? '',
      leads: { field: 'leadSmallGroups' as const, id: g.id },
      meets: meetsOf(g),
    })),
  ];
}

/** When the 小組 [g] meets, as smallGroups/{id} has it. */
export function meetsOf(g: DocumentSnapshot): Meets {
  const weekday = g.get('weekday');
  const every = g.get('every');
  const startsOn = g.get('startsOn');
  return {
    ...(typeof weekday === 'number' ? { weekday } : {}),
    ...(every === 2 ? { every: 2 } : {}),
    ...(typeof startsOn === 'string' ? { startsOn } : {}),
  };
}

const KEY = /^(service|small):[A-Za-z0-9_-]{1,64}$/;

/** The 小組 smallGroups/{id} [doc] has, with its service, for who may fill in its 人數. */
const smallGroupIn = (doc: DocumentSnapshot): Extract<ChurchGroup, { kind: 'small' }> => {
  const service = doc.get('service');
  return { kind: 'small', id: doc.id, service: typeof service === 'string' ? service : null };
};
const SMALL = /^small:[A-Za-z0-9_-]{1,64}$/;
const DAY = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

/**
 * 提醒 on 人數總覽 (#93), by who fills in group `data.key`'s 人數
 * (powers.ts writesAttendance; a service's 負責人 and 牧者 too, #95): one
 * push to whoever is reminded of its 人數 of `data.day`, still without
 * them; at most once a day each group (remindedToday). Returns how many
 * people.
 */
export async function remindAttendance(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  const { key, day } = input;
  if (typeof key !== 'string' || !KEY.test(key) || typeof day !== 'string' || !DAY.test(day)
      || Object.keys(input).some((k) => !['churchId', 'key', 'day'].includes(k))) fail('invalid-argument', 'unknown');
  const { cid, church, powers, member } = await churchAccess(deps, caller, data, 'member');
  if (!powers.overseesAttendance) {
    // A 小組's, by its service's 負責人 and 牧者 too.
    const group = SMALL.test(key)
      ? smallGroupIn(await deps.db.doc(`churches/${cid}/smallGroups/${key.slice('small:'.length)}`).get())
      : groupOf(key)!;
    if (!powers.writesAttendance(group)) fail('permission-denied', 'permissionDenied');
  }
  const since = church.get('attendanceSince');
  const today = dateKeyIn(timeZoneOf(church), deps.now());
  if (typeof since !== 'string' || day > today) fail('failed-precondition', 'unknown');
  const g = (await dueOn(deps, cid, day)).find((d) => d.key === key);
  const uids = g ? await stillAsked(deps, cid, g, day, since) : null;
  // Filled in, or not meeting that day: the overview someone looks at is behind.
  if (!g || uids === null) fail('failed-precondition', 'conflict');
  const asked = deps.db.doc(`churches/${cid}/attendanceAsks/${key}`);
  await deps.db.runTransaction(async (tx) => {
    if ((await tx.get(asked)).get('on') === today) fail('failed-precondition', 'unknown', 'remindedToday');
    tx.set(asked, { on: today, day, by: member.id, at: FieldValue.serverTimestamp() });
  });
  await notifyMembers(deps, cid, uids, 'attendance', (w) => ({
    title: w.attendanceTitle,
    body: w.attendanceAgainBody(g.name, w.dateWithWeekday(day)),
    link: fillLink(key, day),
  }));
  return { people: uids.length };
}

/**
 * 聯合小組 (#93): 小組 `data.key`'s 人數 of `data.day`, a count with a note
 * or none (這次沒聚會), met together with the 小組 `data.together`, by
 * who fills in its 人數 (writesAttendance). Each of those is in the same
 * service, meets that day, and has nothing filled in but having met with
 * this one: it is kept as `with` this one, `together` on this one's. One
 * left out since is cleared, unless its own 小組長 has filled it in.
 */
export async function fillAttendanceTogether(deps: Deps, caller: Caller | null, data: unknown) {
  const input = record(data);
  const { key, day, count, note = '', none, together } = input;
  if (typeof key !== 'string' || !SMALL.test(key) || typeof day !== 'string' || !DAY.test(day)
      || !Array.isArray(together) || together.length > LIMITS.attendanceTogether
      || together.some((t) => typeof t !== 'string' || !SMALL.test(t) || t === key)
      || new Set(together).size !== together.length
      || (none === true
        ? count !== undefined || note !== ''
        : none !== undefined || typeof count !== 'number' || !Number.isInteger(count) || count < 0 || count > LIMITS.attendanceCount
          || typeof note !== 'string' || !withinTextLimit(note, TEXT_LIMITS.attendanceNote))
      || Object.keys(input).some((k) => !['churchId', 'key', 'day', 'count', 'note', 'none', 'together'].includes(k))) {
    fail('invalid-argument', 'unknown');
  }
  const others = together as string[];
  const kept = (note as string).trim();
  const { cid, church, powers, member } = await churchAccess(deps, caller, data, 'member');
  const since = church.get('attendanceSince');
  if (typeof since !== 'string') fail('failed-precondition', 'unknown');
  const smallGroup = (k: string) => deps.db.doc(`churches/${cid}/smallGroups/${k.slice('small:'.length)}`);
  const dayOf = (k: string) => deps.db.doc(`churches/${cid}/attendance/${k}/days/${day}`);
  await deps.db.runTransaction(async (tx) => {
    const host = await tx.get(smallGroup(key));
    const { service } = smallGroupIn(host);
    if (!host.exists || !powers.writesAttendance(smallGroupIn(host))) {
      fail('permission-denied', 'permissionDenied');
    }
    const was = await tx.get(dayOf(key));
    const before = Array.isArray(was.get('together')) ? (was.get('together') as string[]) : [];
    const left = before.filter((k) => !others.includes(k) && SMALL.test(k));
    const [groups, states, days, leftDays] = await Promise.all([
      Promise.all(others.map((k) => tx.get(smallGroup(k)))),
      Promise.all(others.map((k) => tx.get(deps.db.doc(`churches/${cid}/attendance/${k}`)))),
      Promise.all(others.map((k) => tx.get(dayOf(k)))),
      Promise.all(left.map((k) => tx.get(dayOf(k)))),
    ]);
    others.forEach((_, i) => {
      const g = groups[i];
      if (!g.exists || g.get('service') !== service || !attendanceDue(meetsOf(g), { since, pauses: pausesOf(states[i]) }, day)) {
        fail('invalid-argument', 'unknown');
      }
      if (days[i].exists && days[i].get('with') !== key) fail('failed-precondition', 'unknown', 'togetherFilled');
    });
    const by = { by: member.id, updatedAt: FieldValue.serverTimestamp() };
    tx.set(dayOf(key), {
      ...(none === true ? { none: true } : { count, ...(kept ? { note: kept } : {}) }),
      ...(others.length > 0 ? { together: others } : {}),
      ...by,
    });
    for (const k of others) tx.set(dayOf(k), { with: key, ...by });
    left.forEach((k, i) => {
      if (leftDays[i].get('with') === key) tx.delete(dayOf(k));
    });
  });
  return {};
}
