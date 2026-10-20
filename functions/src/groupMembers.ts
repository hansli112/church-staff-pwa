import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { churchAccess, churchClosed, isChurchOpen } from './access.js';
import { fail, type Caller, type Deps } from './common.js';

/**
 * 加為同工 and 移出 on a group's page (#82): a service's or a 事工's 負責人
 * (or an admin) adds someone already in the church as one of its 同工, or
 * takes them out. Nothing else on the member changes: who leads what is
 * set only by an admin, on the member's page.
 *
 * A service's 同工 are its 牧區 (`zones`, with the duties they serve there,
 * and `zoneTypes`); a 事工's are `ministries`. The rules cannot let a lead
 * write one entry of another member's zones list, so this is done here.
 */

interface Zone {
  serviceType: string;
  duties: string[];
  smallGroups?: string[];
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('invalid-argument', 'unknown');
  return value as Record<string, unknown>;
}

const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

export async function setGroupMember(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'member');
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'uid', 'service', 'ministry', 'member', 'duties'].includes(k))) {
    fail('invalid-argument', 'unknown');
  }
  const { uid, service, ministry, member } = input;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid) || typeof member !== 'boolean'
      || (typeof service === 'string') === (typeof ministry === 'string')) fail('invalid-argument', 'unknown');
  const duties = input.duties === undefined ? [] : input.duties;
  if (!Array.isArray(duties) || duties.some((d) => typeof d !== 'string') || duties.length > 50) fail('invalid-argument', 'unknown');

  await deps.db.runTransaction(async (tx) => {
    const target = deps.db.doc(`churches/${cid}/members/${uid}`);
    const [church, me, them, services, ministries] = (await tx.getAll(
      deps.db.doc(`churches/${cid}`),
      deps.db.doc(`churches/${cid}/members/${c.uid}`),
      target,
      deps.db.doc(`churches/${cid}/settings/services`),
      deps.db.doc(`churches/${cid}/settings/ministries`),
    )) as DocumentSnapshot[];
    // Checked again inside: a lead taken away meanwhile changes nothing.
    if (!me.exists) fail('permission-denied', 'permissionDenied');
    if (!isChurchOpen(church)) churchClosed();
    const admin = me.get('role') === 'admin';
    if (typeof service === 'string') {
      if (!admin && !strings(me.get('leadTypes')).includes(service)) fail('permission-denied', 'permissionDenied');
      const known = (services.get('services') as { id: string; duties?: string[] }[] | undefined)?.find((s) => s.id === service);
      if (!known) fail('permission-denied', 'permissionDenied');
      if (duties.some((d) => !(known.duties ?? []).includes(d))) fail('invalid-argument', 'unknown');
      if (!them.exists) fail('not-found', 'notFound');
      const zones = ((them.get('zones') as Zone[] | undefined) ?? []).filter((z) => z.serviceType !== service);
      const was = ((them.get('zones') as Zone[] | undefined) ?? []).find((z) => z.serviceType === service);
      const next = member ? [...zones, was ?? { serviceType: service, duties: [...new Set(duties as string[])], smallGroups: [] }] : zones;
      tx.update(target, { zones: next, zoneTypes: [...new Set(next.map((z) => z.serviceType))] });
    } else {
      const id = ministry as string;
      if (!admin && !strings(me.get('leadMinistries')).includes(id)) fail('permission-denied', 'permissionDenied');
      if (!strings(ministries.get('ids')).includes(id)) fail('permission-denied', 'permissionDenied');
      if (!them.exists) fail('not-found', 'notFound');
      const current = strings(them.get('ministries'));
      tx.update(target, { ministries: member ? [...new Set([...current, id])] : current.filter((m) => m !== id) });
    }
  });
}
