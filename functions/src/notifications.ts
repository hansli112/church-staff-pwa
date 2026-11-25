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
 * Which days a member is reminded: Monday, of the week's duties, the day
 * before each, or both. Matches ReminderTiming in
 * app/lib/domain/models.dart and firestore.rules (test/parity.test.ts).
 */
export const REMINDER_TIMINGS = ['weekly', 'dayBefore', 'both'] as const;
export type ReminderTiming = (typeof REMINDER_TIMINGS)[number];

function reminderTiming(member: DocumentSnapshot): ReminderTiming {
  const t = member.get('notificationPrefs.reminderTiming');
  return t === 'dayBefore' || t === 'both' ? t : 'weekly';
}

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
 * every day one listing tomorrow's (except Monday for those getting both,
 * whose weekly list has tomorrow); one about a single roster opens it.
 * An event's roster counts on the day it starts, by its title; not once
 * its event is cancelled.
 */
export async function sendReminders(deps: PushDeps & { now: () => Date }) {
  const now = deps.now().getTime();
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
    sent += await remindAt(deps, now, due, hour, pickedIn);
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
) {
  // Those due now share one offset, so one today, tomorrow and Monday.
  const timeZone = [...due][0];
  const today = dateKeyIn(timeZone, new Date(now));
  const tomorrow = dateKeyIn(timeZone, new Date(now + DAY_MS));
  const isMonday = new Date(`${today}T00:00:00Z`).getUTCDay() === 1;
  const from = isMonday ? today : tomorrow;
  const until = isMonday ? dateKeyIn(timeZone, new Date(now + 6 * DAY_MS)) : tomorrow;
  const rosters = await deps.db
    .collectionGroup('rosters')
    .where('dateKey', '>=', from)
    .where('dateKey', '<=', until)
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
      // One's own first on a day, then the family's.
      const items = [...(perUid.get(member.id) ?? []), ...(theirs.get(member.id) ?? [])];
      const name = (member.get('name') as string | undefined)?.trim() || null;
      // Monday's list has tomorrow in it, so those choosing both get one message.
      const weekly = isMonday && timing !== 'dayBefore';
      if (weekly) {
        const week = [...items].sort((a, b) => a.dateKey.localeCompare(b.dateKey));
        sent += await notifyMembers(deps, cid, [member.id], 'reminder', (w) => ({
          title: w.weekReminder(name),
          body: week.map((i) => whose(w, i, w.datedDutyLine(w.dateWithWeekday(i.dateKey), w.dutyLine(i.name, i.roles)))).join(w.lineSeparator),
          link: reminderLink(week),
        }));
      }
      const next = items.filter((i) => i.dateKey === tomorrow);
      if (!weekly && timing !== 'weekly' && next.length > 0) {
        sent += await notifyMembers(deps, cid, [member.id], 'reminder', (w) => ({
          title: w.tomorrowReminder(name),
          body: next.map((i) => whose(w, i, w.dutyLine(i.name, i.roles))).join(w.lineSeparator),
          link: reminderLink(next),
        }));
      }
    }
  }
  return sent;
}
