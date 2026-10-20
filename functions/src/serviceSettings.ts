import { isDeepStrictEqual } from 'node:util';

import { churchAccess, churchClosed, isChurchOpen } from './access.js';
import { fail, id, record, serverTime, type Caller, type Deps } from './common.js';
import { LIMITS } from './limits.js';

interface Service {
  id: string;
  name: string;
  weekday: number;
  enabled: boolean;
  duties: string[];
  events: { name: string; color: number }[];
}

interface DutyRename { from: string; to: string }

function exactKeys(value: Record<string, unknown>, keys: string[]) {
  if (Object.keys(value).length !== keys.length || keys.some((k) => !Object.hasOwn(value, k))) fail('invalid-argument', 'unknown');
}

function label(value: unknown): string {
  if (typeof value !== 'string' || !value.trim()) fail('invalid-argument', 'unknown');
  return value;
}

function service(value: unknown): Service {
  const s = record(value);
  exactKeys(s, ['id', 'name', 'weekday', 'enabled', 'duties', 'events']);
  const serviceId = id(s.id);
  const name = label(s.name);
  if (!Number.isInteger(s.weekday) || (s.weekday as number) < 1 || (s.weekday as number) > 7 || typeof s.enabled !== 'boolean') {
    fail('invalid-argument', 'unknown');
  }
  if (!Array.isArray(s.duties) || !Array.isArray(s.events)) fail('invalid-argument', 'unknown');
  const duties = s.duties.map(label);
  const events = s.events.map((value) => {
    const e = record(value);
    exactKeys(e, ['name', 'color']);
    if (!Number.isInteger(e.color) || (e.color as number) < 0 || (e.color as number) > 5) fail('invalid-argument', 'unknown');
    return { name: label(e.name), color: e.color as number };
  });
  if (new Set(duties).size !== duties.length || new Set(events.map((e) => e.name)).size !== events.length) fail('invalid-argument', 'unknown');
  return { id: serviceId, name, weekday: s.weekday as number, enabled: s.enabled, duties, events };
}

function rename(value: unknown, before: Service, after: Service): DutyRename | undefined {
  if (value === undefined) return undefined;
  const r = record(value);
  exactKeys(r, ['from', 'to']);
  const from = label(r.from);
  const to = label(r.to);
  if (!validDutyRename(before.duties, after.duties, from, to)) fail('invalid-argument', 'unknown');
  return { from, to };
}

/**
 * Whether [after] is [before] with duty [from] renamed [to] in place and
 * nothing else changed (testdata/church_rules.json, dutyRename).
 */
export function validDutyRename(before: string[], after: string[], from: string, to: string) {
  return from !== to && before.includes(from) && !before.includes(to)
    && isDeepStrictEqual(after, before.map((d) => d === from ? to : d));
}

/** Edits one configured service; saved roster wording is never rewritten here. */
export async function editService(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'admin');
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'before', 'after', 'dutyRename'].includes(k))) fail('invalid-argument', 'unknown');
  const before = service(input.before);
  const after = service(input.after);
  if (before.id !== after.id) fail('invalid-argument', 'unknown');
  const dutyRename = rename(input.dutyRename, before, after);
  await deps.db.runTransaction(async (tx) => {
    const ref = deps.db.doc(`churches/${cid}/settings/services`);
    const [church, admin, settings] = await tx.getAll(
      deps.db.doc(`churches/${cid}`), deps.db.doc(`churches/${cid}/members/${c.uid}`), ref,
    );
    // Serialize authorization with all writes, not just the initial callable check.
    if (!admin.exists) fail('permission-denied', 'permissionDenied');
    if (!isChurchOpen(church)) churchClosed();
    if (admin.get('role') !== 'admin') fail('permission-denied', 'permissionDenied');
    const services = settings.get('services') as Service[] | undefined;
    const ids = settings.get('ids') as string[] | undefined;
    if (!Array.isArray(services) || services.length < 1 || services.length > LIMITS.services
        || !Array.isArray(ids) || ids.length > 100) fail('failed-precondition', 'unknown', 'invalidServiceSettings');
    if (!isDeepStrictEqual(services.find((s) => s.id === before.id), before)) fail('aborted', 'conflict');
    if (dutyRename) {
      const [members, pending, order, ministries] = await Promise.all([
        tx.get(deps.db.collection(`churches/${cid}/members`)),
        tx.get(deps.db.collection(`churches/${cid}/pendingMembers`)),
        tx.get(deps.db.doc(`churches/${cid}/staff_orders/${before.id}`)),
        tx.get(deps.db.doc(`churches/${cid}/settings/ministries`)),
      ]);
      const roles = order.get('roles') as Record<string, string[]> | undefined;
      if (roles && Object.hasOwn(roles, dutyRename.to)) fail('aborted', 'conflict');
      // Count settings and staff order too. A refused transaction commits none
      // of its queued updates; never split one rename into partial batches.
      let writeCount = 1 + (roles && Object.hasOwn(roles, dutyRename.from) ? 1 : 0);
      for (const member of [...members.docs, ...pending.docs]) {
        const zones = (member.get('zones') ?? []) as { serviceType: string; duties: string[] }[];
        let changed = false;
        const next = zones.map((z) => {
          if (z.serviceType !== before.id || !z.duties.includes(dutyRename.from)) return z;
          changed = true;
          return { ...z, duties: [...new Set(z.duties.map((d) => d === dutyRename.from ? dutyRename.to : d))] };
        });
        if (changed) {
          if (++writeCount > 500) fail('resource-exhausted', 'quotaExceeded', 'tooManyChanges');
          tx.update(member.ref, { zones: next });
        }
      }
      // The 事工 that link the duty (#82) keep leading it under its new name.
      const linked = ministries.get('ministries') as { duties?: { service: string; duty: string }[] }[] | undefined;
      const renamed = (d: { service: string; duty: string }) => d.service === before.id && d.duty === dutyRename.from;
      if (Array.isArray(linked) && linked.some((m) => (m.duties ?? []).some(renamed))) {
        if (++writeCount > 500) fail('resource-exhausted', 'quotaExceeded', 'tooManyChanges');
        tx.update(ministries.ref, {
          ministries: linked.map((m) => ({
            ...m,
            ...(m.duties && { duties: m.duties.map((d) => (renamed(d) ? { ...d, duty: dutyRename.to } : d)) }),
          })),
        });
      }
      if (roles && Object.hasOwn(roles, dutyRename.from)) {
        const next = { ...roles, [dutyRename.to]: roles[dutyRename.from] };
        delete next[dutyRename.from];
        tx.update(order.ref, { roles: next });
      }
    }
    tx.update(ref, {
      services: services.map((s) => s.id === before.id ? after : s),
      updatedAt: serverTime(),
    });
  });
  return {};
}
