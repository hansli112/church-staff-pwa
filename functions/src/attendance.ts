import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { isChurchOpen } from './access.js';
import { groupOf, powersOf } from './powers.js';
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

/** A group that may meet today: its key, its name, and the member field naming who leads it. */
interface Due {
  key: string;
  name: string;
  leads: { field: 'leadTypes' | 'leadSmallGroups'; id: string };
}

/**
 * Run every hour on the hour: in the churches with 回報人數 on whose clock
 * says [ATTENDANCE_HOUR], one push to the leads of each group that met
 * today and has no 人數 yet (powers.ts remindedOfAttendance: a service's 負責人,
 * not its 牧者; a 小組's 小組長),
 * unless they muted 回報人數提醒. Someone having filled it in, or marked
 * 這次沒聚會, asks no one; nobody is asked twice.
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
    const since = church.get('attendanceSince') as string;
    const groups = await dueToday(deps, cid, today);
    for (const g of groups) {
      const [state, day] = await deps.db.getAll(
        deps.db.doc(`churches/${cid}/attendance/${g.key}`),
        deps.db.doc(`churches/${cid}/attendance/${g.key}/days/${today}`),
      );
      if (day.exists) continue;
      if (!attendanceDue(g.meets, { since, pauses: pausesOf(state) }, today)) continue;
      const leads = await deps.db
        .collection(`churches/${cid}/members`)
        .where(g.leads.field, 'array-contains', g.leads.id)
        .get();
      const reminded = leads.docs.filter((m) => powersOf(m.data()).remindedOfAttendance(groupOf(g.key)!));
      sent += await notifyMembers(deps, cid, reminded.map((m) => m.id), 'attendance', (w) => ({
        title: w.attendanceTitle,
        body: w.attendanceBody(g.name, w.dateWithWeekday(today)),
        link: '/home',
      }));
    }
  }
  return sent;
}

/** The pauses attendance/{key} has. */
export function pausesOf(d: DocumentSnapshot | undefined): Pause[] {
  const list = d?.get('pauses');
  return (Array.isArray(list) ? list : []).filter(
    (p): p is Pause => typeof p?.from === 'string' && typeof p?.until === 'string',
  );
}

/** The services and 小組 of church [cid] meeting on [today], before pauses and what was filled in. */
async function dueToday(deps: PushDeps, cid: string, today: string): Promise<(Due & { meets: Meets })[]> {
  const weekday = weekdayOf(today);
  const [services, smallGroups] = await Promise.all([
    deps.db.doc(`churches/${cid}/settings/services`).get(),
    deps.db.collection(`churches/${cid}/smallGroups`).where('weekday', '==', weekday).get(),
  ]);
  const meetingServices = ((services.get('services') as { id: string; name?: string; weekday?: number; enabled?: boolean }[] | undefined) ?? [])
    .filter((s) => s.enabled !== false && s.weekday === weekday);
  const rosters = meetingServices.length === 0
    ? []
    : await deps.db.getAll(...meetingServices.map((s) => deps.db.doc(`churches/${cid}/rosters/${today}_${s.id}`)));
  return [
    ...meetingServices.map((s, i) => ({
      key: `service:${s.id}`,
      name: s.name ?? '',
      leads: { field: 'leadTypes' as const, id: s.id },
      meets: { weekday: s.weekday, roster: rosters[i].exists },
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
