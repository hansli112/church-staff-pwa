// Evening reminders. Roster change pushes are in rosterChange.ts.
import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { isChurchOpen } from './access.js';
import { dateKeyUtc8 } from './common.js';
import { notifyMembers, type PushDeps } from './push.js';
import { dutiesByUid, shortDate } from './rosterChange.js';

async function serviceName(deps: PushDeps, cid: string, type: string) {
  const settings = await deps.db.doc(`churches/${cid}/settings/services`).get();
  const list = (settings.get('services') as { id: string; name: string }[] | undefined) ?? [];
  return list.find((s) => s.id === type)?.name ?? '';
}

/**
 * Evening reminders for tomorrow (UTC+8): everyone with a uid on a duty of
 * an active church gets one message listing their duties that day.
 */
export async function sendReminders(deps: PushDeps & { now: () => Date }) {
  const tomorrow = dateKeyUtc8(new Date(deps.now().getTime() + 86400e3));
  const rosters = await deps.db.collectionGroup('rosters').where('dateKey', '==', tomorrow).get();
  const byChurch = new Map<string, DocumentSnapshot[]>();
  for (const r of rosters.docs) {
    const cid = r.ref.parent.parent!.id;
    byChurch.set(cid, [...(byChurch.get(cid) ?? []), r]);
  }
  let sent = 0;
  for (const [cid, docs] of byChurch) {
    const church = await deps.db.doc(`churches/${cid}`).get();
    if (!isChurchOpen(church)) continue;
    const perUid = new Map<string, string[]>();
    for (const r of docs) {
      const name = await serviceName(deps, cid, r.get('type') as string);
      for (const [uid, roles] of dutiesByUid(r.get('duties'))) {
        perUid.set(uid, [...(perUid.get(uid) ?? []), `${name} ${roles.join('、')}`]);
      }
    }
    for (const [uid, items] of perUid) {
      sent += await notifyMembers(deps, cid, [uid], 'reminder', {
        title: `明天的服事（${shortDate(tomorrow)}）`,
        body: items.join('；'),
        link: '/home',
      });
    }
  }
  return sent;
}
