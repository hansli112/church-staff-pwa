import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { dateKeyUtc8 } from './common.js';
import { notifyMembers, type PushDeps } from './push.js';

interface Duty {
  role: string;
  people?: string[];
  uids?: Record<string, string>;
}

/** uid → the duties they hold on this roster. */
export function dutiesByUid(duties: unknown): Map<string, string[]> {
  const out = new Map<string, string[]>();
  if (!Array.isArray(duties)) return out;
  for (const d of duties as Duty[]) {
    if (typeof d?.role !== 'string') continue;
    for (const [name, uid] of Object.entries(d.uids ?? {})) {
      if (typeof uid !== 'string' || !(d.people ?? []).includes(name)) continue;
      out.set(uid, [...(out.get(uid) ?? []), d.role]);
    }
  }
  return out;
}

export interface RosterChange {
  added: Map<string, string[]>;
  removed: Map<string, string[]>;
}

/** Who was put on or taken off which duty between two versions of a day. */
export function rosterChange(before: unknown, after: unknown): RosterChange {
  const a = dutiesByUid(before);
  const b = dutiesByUid(after);
  const added = new Map<string, string[]>();
  const removed = new Map<string, string[]>();
  for (const [uid, roles] of b) {
    const was = new Set(a.get(uid) ?? []);
    const extra = roles.filter((r) => !was.has(r));
    if (extra.length) added.set(uid, extra);
  }
  for (const [uid, roles] of a) {
    const now = new Set(b.get(uid) ?? []);
    const gone = roles.filter((r) => !now.has(r));
    if (gone.length) removed.set(uid, gone);
  }
  return { added, removed };
}

function shortDate(dateKey: string) {
  const [, m, d] = dateKey.split('-').map(Number);
  return `${m}/${d}`;
}

async function serviceName(deps: PushDeps, cid: string, type: string) {
  const settings = await deps.db.doc(`churches/${cid}/settings/services`).get();
  const list = (settings.get('services') as { id: string; name: string }[] | undefined) ?? [];
  return list.find((s) => s.id === type)?.name ?? '';
}

/**
 * Tells people when they are put on or taken off a duty on an upcoming
 * day. The editor making the change is not told about their own change.
 */
export async function onRosterWritten(
  deps: PushDeps & { now: () => Date },
  cid: string,
  before: DocumentSnapshot | undefined,
  after: DocumentSnapshot | undefined,
  editedBy: string | undefined,
) {
  const doc = after?.exists ? after : before;
  // Bulk writes (import) would send one push per person per day; the
  // import itself is the news, not each day.
  if (after?.get('via') === 'import') return 0;
  const dateKey = doc?.get('dateKey') as string | undefined;
  const type = doc?.get('type') as string | undefined;
  if (!dateKey || !type || dateKey < dateKeyUtc8(deps.now())) return 0;
  const church = await deps.db.doc(`churches/${cid}`).get();
  if (church.get('status') !== 'active') return 0;
  const change = rosterChange(before?.exists ? before.get('duties') : [], after?.exists ? after.get('duties') : []);
  const name = await serviceName(deps, cid, type);
  const link = `/rosters/${type}/${dateKey}`;
  let sent = 0;
  for (const [uid, roles] of change.added) {
    if (uid === editedBy) continue;
    sent += await notifyMembers(deps, cid, [uid], 'rosterChange', {
      title: church.get('name') as string,
      body: `你被排進 ${shortDate(dateKey)} ${name}：${roles.join('、')}`,
      link,
    });
  }
  for (const [uid, roles] of change.removed) {
    if (uid === editedBy) continue;
    sent += await notifyMembers(deps, cid, [uid], 'rosterChange', {
      title: church.get('name') as string,
      body: `${shortDate(dateKey)} ${name} 的${roles.join('、')}已改由別人負責`,
      link,
    });
  }
  return sent;
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
    if (church.get('status') !== 'active') continue;
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
