import type { DocumentReference, DocumentSnapshot, Transaction } from 'firebase-admin/firestore';

import { accessIn, churchAccess } from './access.js';
import { fail, record, strings, type Caller, type Deps } from './common.js';
import { ministriesOf } from './ministries.js';
import type { ChurchGroup } from './powers.js';

/**
 * 加為同工 and 移出 on a group's page (#82): a service's or a 小組's (#85)
 * 負責人 (or an admin) adds someone already in the church as one of its
 * 同工, or takes them out. Nothing else on the member changes: who leads
 * what is set only by an admin, on the member's page. A 事工 has no 同工
 * of its own (#94): its people are those on its duties' lists ([setDuty]).
 *
 * A service's 同工 are `zones` (with the duties they serve and their 小組
 * there, and `zoneTypes`); a 小組's `smallGroups`, which the 負責人 of its
 * service also manage. The rules cannot let a lead write one entry of
 * another member's zones list, so this is done here.
 */

interface Zone {
  serviceType: string;
  duties: string[];
  smallGroups?: string[];
}

export async function setGroupMember(deps: Deps, caller: Caller | null, data: unknown) {
  const access = await churchAccess(deps, caller, data, 'member');
  const { cid } = access;
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'uid', 'service', 'smallGroup', 'member', 'duties', 'smallGroups'].includes(k))) {
    fail('invalid-argument', 'unknown');
  }
  const { uid, service, smallGroup, member } = input;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid) || typeof member !== 'boolean'
      || [service, smallGroup].filter((g) => typeof g === 'string').length !== 1
      || (typeof smallGroup === 'string' && !/^[A-Za-z0-9_-]{1,64}$/.test(smallGroup))) fail('invalid-argument', 'unknown');
  const list = (v: unknown) => {
    if (v === undefined) return [];
    if (!Array.isArray(v) || v.some((d) => typeof d !== 'string') || v.length > 50) fail('invalid-argument', 'unknown');
    return [...new Set(v as string[])];
  };
  const duties = list(input.duties);
  const smallGroups = list(input.smallGroups);

  await deps.db.runTransaction(async (tx) => {
    const target = deps.db.doc(`churches/${cid}/members/${uid}`);
    const { powers, docs: [them, services, small] } = await accessIn(
      tx,
      deps,
      access,
      target,
      deps.db.doc(`churches/${cid}/settings/services`),
      deps.db.doc(`churches/${cid}/smallGroups/${typeof smallGroup === 'string' ? smallGroup : '-'}`),
    );
    // The group as it is now: a closed 小組 takes no one.
    const group: ChurchGroup = typeof service === 'string'
      ? { kind: 'service', id: service }
      : { kind: 'small', id: smallGroup as string, service: small.exists ? (small.get('service') as string) : null };
    const known = group.kind === 'small'
      ? (small.exists ? small : undefined)
      : serviceIn(services, group.id);
    if (!known) fail('permission-denied', 'permissionDenied');
    if (!them.exists) fail('not-found', 'notFound');
    if (!powers.mayMove(them.data()!, group)) fail('permission-denied', 'permissionDenied');
    if (group.kind === 'small') {
      const current = strings(them.get('smallGroups'));
      tx.update(target, { smallGroups: member ? [...new Set([...current, group.id])] : current.filter((g) => g !== group.id) });
    } else {
      const serves = (known as { duties?: string[] }).duties ?? [];
      if (duties.some((d) => !serves.includes(d))) fail('invalid-argument', 'unknown');
      const zones = (them.get('zones') as Zone[] | undefined) ?? [];
      const was = zones.find((z) => z.serviceType === group.id);
      const others = zones.filter((z) => z.serviceType !== group.id);
      writeZones(tx, target, member ? [...others, was ?? { serviceType: group.id, duties, smallGroups }] : others);
    }
  });
}

/**
 * Puts member `uid` on the list of `duty` in `service` (`on`), or takes
 * them off it (#94): from a duty's page, a 事工's, the member's, or while
 * arranging (加到名單). Put on it, they become one of the service's 同工
 * if they were not; taken off, they stay one. Only a duty the service has
 * is put on; any is taken off (one renamed or removed since). Who may:
 * Powers.editsDutyList.
 */
export async function setDuty(deps: Deps, caller: Caller | null, data: unknown) {
  const access = await churchAccess(deps, caller, data, 'member');
  const { cid } = access;
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'uid', 'service', 'duty', 'on'].includes(k))) fail('invalid-argument', 'unknown');
  const { uid, service, duty, on } = input;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid) || typeof on !== 'boolean'
      || typeof service !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(service)
      || typeof duty !== 'string' || duty.length === 0 || duty.length > 100) fail('invalid-argument', 'unknown');

  await deps.db.runTransaction(async (tx) => {
    const target = deps.db.doc(`churches/${cid}/members/${uid}`);
    const { powers, docs: [them, services, ministries] } = await accessIn(
      tx,
      deps,
      access,
      target,
      deps.db.doc(`churches/${cid}/settings/services`),
      deps.db.doc(`churches/${cid}/settings/ministries`),
    );
    const known = serviceIn(services, service);
    if (!known || !powers.editsDutyList(ministriesOf(ministries), service, duty)) fail('permission-denied', 'permissionDenied');
    if (!them.exists) fail('not-found', 'notFound');
    if (on && !(known.duties ?? []).includes(duty)) fail('invalid-argument', 'unknown');
    const zones = (them.get('zones') as Zone[] | undefined) ?? [];
    const was = zones.find((z) => z.serviceType === service);
    if (on ? was?.duties.includes(duty) : !was?.duties.includes(duty)) return;
    writeZones(tx, target, was
      ? zones.map((z) => z === was ? { ...z, duties: on ? [...z.duties, duty] : z.duties.filter((d) => d !== duty) } : z)
      : [...zones, { serviceType: service, duties: [duty], smallGroups: [] }]);
  });
}

/** Service [id] in settings/services [services], if the church has it. */
const serviceIn = (services: DocumentSnapshot, id: string) =>
  (services.get('services') as { id: string; duties?: string[] }[] | undefined)?.find((s) => s.id === id);

/** [zones] on member [target], and `zoneTypes`, which the rules read. */
function writeZones(tx: Transaction, target: DocumentReference, zones: Zone[]) {
  tx.update(target, { zones, zoneTypes: [...new Set(zones.map((z) => z.serviceType))] });
}
