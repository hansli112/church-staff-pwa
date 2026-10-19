// Evening reminders. Roster change pushes are in rosterChange.ts.
import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { isChurchOpen } from './access.js';
import { DAY_MS } from './common.js';
import { notifyMembers, type PushDeps } from './push.js';
import { rosterDay, serviceNames } from './rosters.js';
import { dateKeyIn, timeZoneOf, timeZonesAt } from './timeZones.js';

/** The hour of the evening reminders, on each church's clock. */
export const REMINDER_HOUR = 19;

/**
 * When a member is reminded: Monday evening of the week's duties, the
 * evening before each, or both. Matches ReminderTiming in
 * app/lib/domain/models.dart.
 */
export type ReminderTiming = 'weekly' | 'dayBefore' | 'both';

function reminderTiming(member: DocumentSnapshot): ReminderTiming {
  const t = member.get('notificationPrefs.reminderTiming');
  return t === 'dayBefore' || t === 'both' ? t : 'weekly';
}

/** Someone's duties on one day: which, of what service or event. */
interface DutyLine {
  dateKey: string;
  name: string;
  roles: string[];
}

/**
 * Evening reminders, run every hour on the hour: for the churches whose
 * clock says [REMINDER_HOUR], to everyone with a uid on a duty of an
 * active one, as each chose: on Monday one message listing their duties
 * from that Monday to Sunday, and every evening one listing tomorrow's
 * (except Monday for those getting both, whose weekly list has tomorrow).
 * An event's roster counts on the day it starts, by its title; not once
 * its event is cancelled.
 */
export async function sendReminders(deps: PushDeps & { now: () => Date }) {
  const now = deps.now().getTime();
  // Those due now share one offset, so one today, tomorrow and Monday.
  const due = timeZonesAt([REMINDER_HOUR], new Date(now));
  const timeZone = [...due][0];
  if (!timeZone) return 0;
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
    const church = await deps.db.doc(`churches/${cid}`).get();
    if (!isChurchOpen(church) || !due.has(timeZoneOf(church))) continue;
    const services = await serviceNames(deps, cid);
    const perUid = new Map<string, DutyLine[]>();
    for (const day of docs.map(rosterDay)) {
      if (!day || day.cancelled) continue;
      for (const [uid, roles] of day.holders) {
        perUid.set(uid, [...(perUid.get(uid) ?? []), { dateKey: day.dateKey, name: day.name(services), roles }]);
      }
    }
    if (perUid.size === 0) continue;
    const members = await deps.db.getAll(...[...perUid.keys()].map((uid) => deps.db.doc(`churches/${cid}/members/${uid}`)));
    for (const member of members) {
      if (!member.exists) continue;
      const timing = reminderTiming(member);
      const items = perUid.get(member.id)!;
      const name = (member.get('name') as string | undefined)?.trim() || null;
      // Monday's list has tomorrow in it, so those choosing both get one message.
      const weekly = isMonday && timing !== 'dayBefore';
      if (weekly) {
        const week = [...items].sort((a, b) => a.dateKey.localeCompare(b.dateKey));
        sent += await notifyMembers(deps, cid, [member.id], 'reminder', (w) => ({
          title: w.weekReminder(name),
          body: week.map((i) => w.datedDutyLine(w.dateWithWeekday(i.dateKey), w.dutyLine(i.name, i.roles))).join(w.lineSeparator),
          link: '/home',
        }));
      }
      const next = items.filter((i) => i.dateKey === tomorrow);
      if (!weekly && timing !== 'weekly' && next.length > 0) {
        sent += await notifyMembers(deps, cid, [member.id], 'reminder', (w) => ({
          title: w.tomorrowReminder(name),
          body: next.map((i) => w.dutyLine(i.name, i.roles)).join(w.lineSeparator),
          link: '/home',
        }));
      }
    }
  }
  return sent;
}
