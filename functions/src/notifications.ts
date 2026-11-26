// Duty reminders. Roster change pushes are in rosterChange.ts.
import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { isChurchOpen } from './access.js';
import { DAY_MS } from './common.js';
import { familiesOf } from './family.js';
import type { Words } from './languages.js';
import { notifyMembers, type PushDeps } from './push.js';
import { rosterDay, rosterLink, serviceNames } from './rosters.js';
import { dateKeyIn, timeZoneOf, timeZonesAt, type ChurchTimeZone } from './timeZones.js';

/**
 * The hours a member may be reminded at, on their church's clock
 * (`notificationPrefs.reminderHour`), and the one unless they pick another.
 * Matches ReminderHours in app/lib/domain/models.dart and firestore.rules
 * (test/parity.test.ts).
 */
export const REMINDER_HOURS: { first: number; last: number; usual: number } = { first: 6, last: 22, usual: 19 };

/**
 * How many days before a duty a member is reminded, when they are
 * (`notificationPrefs.reminderDays`), and the number unless they pick
 * another. Matches ReminderDays in app/lib/domain/models.dart and
 * firestore.rules (test/parity.test.ts).
 */
export const REMINDER_DAYS: { first: number; last: number; usual: number } = { first: 1, last: 14, usual: 1 };

/**
 * Which days a member is reminded: Monday, of the week's duties, some days
 * ([REMINDER_DAYS]) before each, or both. Matches ReminderTiming in
 * app/lib/domain/models.dart and firestore.rules (test/parity.test.ts).
 */
export const REMINDER_TIMINGS = ['weekly', 'dayBefore', 'both'] as const;
export type ReminderTiming = (typeof REMINDER_TIMINGS)[number];

function reminderTiming(member: DocumentSnapshot): ReminderTiming {
  const t = member.get('notificationPrefs.reminderTiming');
  return t === 'dayBefore' || t === 'both' ? t : 'weekly';
}

function reminderDays(member: DocumentSnapshot): number {
  const d = member.get('notificationPrefs.reminderDays');
  return Number.isInteger(d) && d >= REMINDER_DAYS.first && d <= REMINDER_DAYS.last ? d : REMINDER_DAYS.usual;
}

/** The day [days] after [dateKey]. */
const daysAfter = (dateKey: string, days: number) =>
  new Date(Date.parse(`${dateKey}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);

function reminderHour(member: DocumentSnapshot): number {
  const h = member.get('notificationPrefs.reminderHour');
  return Number.isInteger(h) && h >= REMINDER_HOURS.first && h <= REMINDER_HOURS.last ? h : REMINDER_HOURS.usual;
}

/** Someone's duties on one roster: which, of what service or event. */
interface DutyLine {
  dateKey: string;
  name: string;
  roles: string[];
  /** The roster's page. */
  link: string;
  /** Whose, of one's 家人 without an account; none for one's own. */
  who?: string;
}

/** [line] of [item], with whose it is when it is a family member's. */
const whose = (w: Words, item: DutyLine, line: string) => (item.who ? w.familyLine(item.who, line) : line);

/** Where a reminder of [lines] opens: the roster if it is about one, else 首頁, which lists them. */
const reminderLink = (lines: DutyLine[]) => (lines.length === 1 ? lines[0].link : '/home');

/**
 * Duty reminders, run every hour on the hour: to everyone with a uid on a
 * duty of an active church whose clock says the hour they picked
 * ([REMINDER_HOURS], 19 unless they picked another), as each chose: on
 * Monday one message listing their duties from that Monday to Sunday, and
 * every day one listing those some days ahead ([REMINDER_DAYS], tomorrow's
 * unless they picked more; not on Monday for those getting both when the
 * weekly list has that day); one about a single roster opens it.
 * An event's roster counts on the day it starts, by its title; not once
 * its event is cancelled.
 */
export async function sendReminders(deps: PushDeps & { now: () => Date }) {
  const now = deps.now().getTime();
  // Days before other than tomorrow, only as many as someone picked.
  const pickedDays = await deps.db
    .collectionGroup('members')
    .where('notificationPrefs.reminderDays', '>', REMINDER_DAYS.usual)
    .select('notificationPrefs.reminderDays')
    .get();
  const ahead = new Set([REMINDER_DAYS.usual, ...pickedDays.docs.map(reminderDays)]);
  let sent = 0;
  for (let hour = REMINDER_HOURS.first; hour <= REMINDER_HOURS.last; hour++) {
    const due = timeZonesAt([hour], new Date(now));
    if (due.size === 0) continue;
    // Off the usual hour, only the churches where someone picked it.
    let pickedIn: Set<string> | null = null;
    if (hour !== REMINDER_HOURS.usual) {
      const picked = await deps.db.collectionGroup('members').where('notificationPrefs.reminderHour', '==', hour).select().get();
      if (picked.empty) continue;
      pickedIn = new Set(picked.docs.map((d) => d.ref.parent.parent!.id));
    }
    sent += await remindAt(deps, now, due, hour, pickedIn, ahead);
  }
  return sent;
}

/** [sendReminders] for the churches of [due], all at [hour] now; of [pickedIn], those where someone picked it, if given. */
async function remindAt(
  deps: PushDeps,
  now: number,
  due: Set<ChurchTimeZone>,
  hour: number,
  pickedIn: Set<string> | null,
  ahead: Set<number>,
) {
  // Those due now share one offset, so one today and Monday.
  const timeZone = [...due][0];
  const today = dateKeyIn(timeZone, new Date(now));
  const isMonday = new Date(`${today}T00:00:00Z`).getUTCDay() === 1;
  const sunday = daysAfter(today, 6);
  // The week's on Monday, and each number of days ahead someone picked:
  // at most 7 + 14 days, under the 30 `in` takes.
  const days = new Set([...(isMonday ? [0, 1, 2, 3, 4, 5, 6] : []), ...ahead].map((d) => daysAfter(today, d)));
  const rosters = await deps.db
    .collectionGroup('rosters')
    .where('dateKey', 'in', [...days])
    .get();
  const byChurch = new Map<string, DocumentSnapshot[]>();
  for (const r of rosters.docs) {
    const cid = r.ref.parent.parent!.id;
    byChurch.set(cid, [...(byChurch.get(cid) ?? []), r]);
  }
  let sent = 0;
  for (const [cid, docs] of byChurch) {
    if (pickedIn && !pickedIn.has(cid)) continue;
    const church = await deps.db.doc(`churches/${cid}`).get();
    if (!isChurchOpen(church) || !due.has(timeZoneOf(church))) continue;
    const services = await serviceNames(deps, cid);
    const perUid = new Map<string, DutyLine[]>();
    for (const day of docs.map(rosterDay)) {
      // Nor a deleted service's: its rosters stay saved, out of sight.
      if (!day || day.cancelled || (!day.event && !services(day.serviceId!))) continue;
      for (const [uid, roles] of day.holders) {
        perUid.set(uid, [...(perUid.get(uid) ?? []), { dateKey: day.dateKey, name: day.name(services), roles, link: rosterLink(day) }]);
      }
    }
    if (perUid.size === 0) continue;
    // 家人 (family.ts): those without an account are told to their families.
    const ids = [...perUid.keys()];
    const known = await deps.db.getAll(...ids.map((uid) => deps.db.doc(`churches/${cid}/members/${uid}`)));
    const families = await familiesOf(deps, cid, known.filter((m) => !m.exists).map((m) => m.id));
    const theirs = new Map<string, DutyLine[]>();
    for (const [kid, { name, to }] of families) {
      for (const uid of to) {
        theirs.set(uid, [...(theirs.get(uid) ?? []), ...perUid.get(kid)!.map((i) => ({ ...i, who: name }))]);
      }
    }
    const extra = [...theirs.keys()].filter((uid) => !perUid.has(uid));
    const members = [
      ...known,
      ...(extra.length ? await deps.db.getAll(...extra.map((uid) => deps.db.doc(`churches/${cid}/members/${uid}`))) : []),
    ];
    for (const member of members) {
      if (!member.exists || reminderHour(member) !== hour) continue;
      const timing = reminderTiming(member);
      const inDays = reminderDays(member);
      const target = daysAfter(today, inDays);
      // One's own first on a day, then the family's.
      const items = [...(perUid.get(member.id) ?? []), ...(theirs.get(member.id) ?? [])];
      const name = (member.get('name') as string | undefined)?.trim() || null;
      // Monday's list has the week in it, so those choosing both get one
      // message unless the day ahead is past Sunday.
      const weekly = isMonday && timing !== 'dayBefore';
      // Days past Sunday are read for those reminded further ahead.
      const week = items.filter((i) => i.dateKey <= sunday).sort((a, b) => a.dateKey.localeCompare(b.dateKey));
      if (weekly && week.length > 0) {
        sent += await notifyMembers(deps, cid, [member.id], 'reminder', (w) => ({
          title: w.weekReminder(name),
          body: week.map((i) => whose(w, i, w.datedDutyLine(w.dateWithWeekday(i.dateKey), w.dutyLine(i.name, i.roles)))).join(w.lineSeparator),
          link: reminderLink(week),
        }));
      }
      const next = items.filter((i) => i.dateKey === target);
      if (timing !== 'weekly' && !(weekly && target <= sunday) && next.length > 0) {
        sent += await notifyMembers(deps, cid, [member.id], 'reminder', (w) => ({
          title: inDays === 1 ? w.tomorrowReminder(name) : w.daysAheadReminder(name, inDays),
          // Further than tomorrow, the day is said.
          body: next
            .map((i) => {
              const line = w.dutyLine(i.name, i.roles);
              return whose(w, i, inDays === 1 ? line : w.datedDutyLine(w.dateWithWeekday(i.dateKey), line));
            })
            .join(w.lineSeparator),
          link: reminderLink(next),
        }));
      }
    }
  }
  return sent;
}
