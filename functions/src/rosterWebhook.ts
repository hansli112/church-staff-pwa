import { Timestamp, type DocumentSnapshot } from 'firebase-admin/firestore';

import { CHURCH_TIME_ZONE } from './calendar.js';
import { dateKeyUtc8, type Deps } from './common.js';
import { deliver, type WebhookDeps } from './webhook.js';

/**
 * 服事表異動 webhooks, batched: each roster write of an upcoming day adds
 * one entry to the church's outbox (webhookOutbox/{cid}/rosterChanges,
 * backend only), and every 5 minutes each church's outbox goes out as one
 * `roster.changed` notice and is emptied. A whole import is one notice.
 *
 * One document per change, keyed by the trigger's event id, so a burst of
 * writes never contends on a single document and a retried trigger adds
 * nothing twice.
 */
export const MAX_LISTED = 200;

interface Duty {
  role?: unknown;
  people?: unknown;
}

const names = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

/** Per duty, who was put on and who was taken off. */
export function dutyChanges(before: unknown, after: unknown) {
  const people = (duties: unknown) => {
    const out = new Map<string, string[]>();
    for (const d of Array.isArray(duties) ? (duties as Duty[]) : []) {
      if (typeof d?.role === 'string') out.set(d.role, names(d.people));
    }
    return out;
  };
  const a = people(before);
  const b = people(after);
  const roles = [...new Set([...b.keys(), ...a.keys()])];
  return roles
    .map((duty) => {
      const was = a.get(duty) ?? [];
      const now = b.get(duty) ?? [];
      return { duty, added: now.filter((p) => !was.includes(p)), removed: was.filter((p) => !now.includes(p)) };
    })
    .filter((d) => d.added.length || d.removed.length);
}

/**
 * From onRosterWritten: queues the change for churches with roster notices
 * on. Past days and changes that move nobody are left out.
 */
export async function queueRosterChange(
  deps: Deps,
  cid: string,
  before: DocumentSnapshot | undefined,
  after: DocumentSnapshot | undefined,
  editedBy: string | undefined,
  eventId: string,
) {
  const doc = after?.exists ? after : before;
  const dateKey = doc?.get('dateKey') as string | undefined;
  const type = doc?.get('type') as string | undefined;
  if (!dateKey || !type || dateKey < dateKeyUtc8(deps.now())) return false;
  const [church, hook] = await Promise.all([
    deps.db.doc(`churches/${cid}`).get(),
    deps.db.doc(`churches/${cid}/settings/webhook`).get(),
  ]);
  if (church.get('status') !== 'active' || hook.get('events.roster') !== true) return false;
  const duties = dutyChanges(before?.exists ? before.get('duties') : [], after?.exists ? after.get('duties') : []);
  if (duties.length === 0) return false;
  const [services, editor] = await Promise.all([
    deps.db.doc(`churches/${cid}/settings/services`).get(),
    editedBy ? deps.db.doc(`churches/${cid}/members/${editedBy}`).get() : null,
  ]);
  const list = (services.get('services') as { id: string; name: string }[] | undefined) ?? [];
  await deps.db.doc(`webhookOutbox/${cid}/rosterChanges/${eventId}`).set({
    date: dateKey,
    serviceId: type,
    serviceName: list.find((s) => s.id === type)?.name ?? '',
    duties,
    actorUid: editedBy ?? null,
    actorName: (editor?.get('name') as string | undefined) || null,
    via: (after?.get('via') as string | undefined) ?? 'app',
    at: Timestamp.fromDate(deps.now()),
  });
  return true;
}

/**
 * Every 5 minutes: one `roster.changed` notice per church with queued
 * changes, then those changes are deleted. A closed church's or a switched-
 * off outbox is emptied without sending.
 */
export async function sendRosterChanges(deps: WebhookDeps) {
  const queued = await deps.db.collectionGroup('rosterChanges').get();
  const byChurch = new Map<string, FirebaseFirestore.QueryDocumentSnapshot[]>();
  for (const d of queued.docs) {
    const cid = d.ref.parent.parent?.id;
    if (cid && d.ref.parent.parent?.parent.id === 'webhookOutbox') byChurch.set(cid, [...(byChurch.get(cid) ?? []), d]);
  }
  let sent = 0;
  for (const [cid, docs] of byChurch) {
    const changes = docs
      .map((d) => d.data())
      .sort((a, b) => (a.at as Timestamp).toMillis() - (b.at as Timestamp).toMillis())
      .map((c) => ({
        date: c.date,
        serviceId: c.serviceId,
        serviceName: c.serviceName,
        duties: c.duties,
        actorUid: c.actorUid,
        actorName: c.actorName,
        via: c.via,
      }));
    const church = await deps.db.doc(`churches/${cid}`).get();
    const result = await deliver(deps, cid, 'roster.changed', {
      action: 'changed',
      source: 'martha',
      churchId: cid,
      churchName: church.get('name') ?? '',
      timeZone: CHURCH_TIME_ZONE,
      count: changes.length,
      imported: changes.some((c) => c.via === 'import'),
      changes: changes.slice(0, MAX_LISTED),
      more: Math.max(0, changes.length - MAX_LISTED),
    });
    if (result) sent++;
    const w = deps.db.bulkWriter();
    for (const d of docs) void w.delete(d.ref);
    await w.close();
  }
  return sent;
}
