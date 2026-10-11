// Evening reminders. Roster change pushes are in rosterChange.ts.
import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { isChurchOpen } from './access.js';
import { DAY_MS, dateKeyUtc8 } from './common.js';
import { notifyMembers, type PushDeps } from './push.js';
import { dateWithWeekday, dutiesByUid, isEvent, shortDate } from './rosterChange.js';

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

async function serviceName(deps: PushDeps, cid: string, type: string) {
  const settings = await deps.db.doc(`churches/${cid}/settings/services`).get();
  const list = (settings.get('services') as { id: string; name: string }[] | undefined) ?? [];
  return list.find((s) => s.id === type)?.name ?? '';
}

/** One duty to be reminded of: on which day, and what. */
interface DutyLine {
  dateKey: string;
  text: string;
}

/**
 * Evening reminders (UTC+8), for everyone with a uid on a duty of an active
 * church, as each chose: on Monday one message listing their duties from
 * that Monday to Sunday, and every evening one listing tomorrow's. An
 * event's roster counts on the day it starts, by its title; not once its
 * event is cancelled.
 */
export async function sendReminders(deps: PushDeps & { now: () => Date }) {
  const now = deps.now().getTime();
  const today = dateKeyUtc8(new Date(now));
  const tomorrow = dateKeyUtc8(new Date(now + DAY_MS));
  const isMonday = new Date(`${today}T00:00:00Z`).getUTCDay() === 1;
  const from = isMonday ? today : tomorrow;
  const until = isMonday ? dateKeyUtc8(new Date(now + 6 * DAY_MS)) : tomorrow;
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
    if (!isChurchOpen(church)) continue;
    const perUid = new Map<string, DutyLine[]>();
    for (const r of docs) {
      if (r.get('cancelledAt') != null) continue;
      const name =
        isEvent(r) ? ((r.get('title') as string | undefined) ?? '') : await serviceName(deps, cid, r.get('type') as string);
      const dateKey = r.get('dateKey') as string;
      for (const [uid, roles] of dutiesByUid(r.get('duties'))) {
        perUid.set(uid, [...(perUid.get(uid) ?? []), { dateKey, text: `${name} ${roles.join('、')}` }]);
      }
    }
    if (perUid.size === 0) continue;
    const members = await deps.db.getAll(...[...perUid.keys()].map((uid) => deps.db.doc(`churches/${cid}/members/${uid}`)));
    for (const member of members) {
      if (!member.exists) continue;
      const timing = reminderTiming(member);
      const items = perUid.get(member.id)!;
      if (isMonday && timing !== 'dayBefore') {
        const week = [...items].sort((a, b) => a.dateKey.localeCompare(b.dateKey));
        sent += await notifyMembers(deps, cid, [member.id], 'reminder', {
          title: `這週的服事（${shortDate(today)}–${shortDate(until)}）`,
          body: week.map((i) => `${dateWithWeekday(i.dateKey)}${i.text}`).join('；'),
          link: '/home',
        });
      }
      const next = items.filter((i) => i.dateKey === tomorrow);
      if (timing !== 'weekly' && next.length > 0) {
        sent += await notifyMembers(deps, cid, [member.id], 'reminder', {
          title: `明天的服事（${shortDate(tomorrow)}）`,
          body: next.map((i) => i.text).join('；'),
          link: '/home',
        });
      }
    }
  }
  return sent;
}
