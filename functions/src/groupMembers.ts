import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { churchAccess, churchClosed, isChurchOpen } from './access.js';
import { fail, record, type Caller, type Deps } from './common.js';
import { ministriesOf } from './ministries.js';

/**
 * 加為同工 and 移出 on a group's page (#82): a service's, a 事工's or a
 * 小組's (#85) 負責人 (or an admin) adds someone already in the church as
 * one of its 同工, or takes them out. Nothing else on the member changes: who leads what is
 * set only by an admin, on the member's page.
 *
 * A service's 同工 are its 牧區 (`zones`, with the duties they serve and
 * their 小組 there, and `zoneTypes`); a 事工's are `ministries`; a 小組's
 * `smallGroups`, which the 負責人 of its service also manage. The rules
 * cannot let a lead write one entry of another member's zones list, so
 * this is done here.
 */

interface Zone {
  serviceType: string;
  duties: string[];
  smallGroups?: string[];
}

/** A service (its 牧區), a 事工, or a 小組 of [service]. */
export type GroupRef = { service: string; smallGroup?: string } | { ministry: string };

const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

/** The member fields who may move whom reads. */
interface Fields {
  role?: unknown;
  groups?: unknown;
  identities?: unknown;
  leadTypes?: unknown;
  leadMinistries?: unknown;
  leadSmallGroups?: unknown;
}

/**
 * Whether [caller] may add [target] to [group] or take them out
 * (testdata/church_rules.json, groupMembership): an admin anyone; the
 * group's 負責人 only a plain 同工, since giving or taking a 身分 is the
 * admin's.
 */
export function mayMoveMember(caller: Fields, target: Fields, group: GroupRef) {
  if (caller.role === 'admin') return true;
  const leads = 'ministry' in group
    ? strings(caller.leadMinistries).includes(group.ministry)
    : strings(caller.leadTypes).includes(group.service)
      || (group.smallGroup !== undefined && strings(caller.leadSmallGroups).includes(group.smallGroup));
  const plain = target.role !== 'admin' && strings(target.groups).length === 0
    && !(Array.isArray(target.identities) && target.identities.length > 0);
  return leads && plain;
}

export async function setGroupMember(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'member');
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'uid', 'service', 'ministry', 'smallGroup', 'member', 'duties', 'smallGroups'].includes(k))) {
    fail('invalid-argument', 'unknown');
  }
  const { uid, service, ministry, smallGroup, member } = input;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid) || typeof member !== 'boolean'
      || [service, ministry, smallGroup].filter((g) => typeof g === 'string').length !== 1
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
    const [church, me, them, services, ministries, small] = (await tx.getAll(
      deps.db.doc(`churches/${cid}`),
      deps.db.doc(`churches/${cid}/members/${c.uid}`),
      target,
      deps.db.doc(`churches/${cid}/settings/services`),
      deps.db.doc(`churches/${cid}/settings/ministries`),
      deps.db.doc(`churches/${cid}/smallGroups/${typeof smallGroup === 'string' ? smallGroup : '-'}`),
    )) as DocumentSnapshot[];
    // Checked again inside: a lead taken away meanwhile changes nothing.
    if (!me.exists) fail('permission-denied', 'permissionDenied');
    if (!isChurchOpen(church)) churchClosed();
    // The group as it is now: a deleted 事工 or 小組 takes no one.
    const group: GroupRef = typeof service === 'string'
      ? { service }
      : typeof ministry === 'string'
        ? { ministry }
        : { smallGroup: smallGroup as string, service: small.exists ? (small.get('service') as string) : '' };
    const known = 'ministry' in group
      ? ministriesOf(ministries).find((m) => m.id === group.ministry)
      : group.smallGroup !== undefined
        ? (small.exists ? small : undefined)
        : (services.get('services') as { id: string; duties?: string[] }[] | undefined)?.find((s) => s.id === group.service);
    if (!known) fail('permission-denied', 'permissionDenied');
    if (!them.exists) fail('not-found', 'notFound');
    if (!mayMoveMember(me.data()!, them.data()!, group)) fail('permission-denied', 'permissionDenied');
    if (!('ministry' in group) && group.smallGroup !== undefined) {
      const current = strings(them.get('smallGroups'));
      tx.update(target, { smallGroups: member ? [...new Set([...current, group.smallGroup])] : current.filter((g) => g !== group.smallGroup) });
    } else if ('service' in group) {
      const serves = (known as { duties?: string[] }).duties ?? [];
      if (duties.some((d) => !serves.includes(d))) fail('invalid-argument', 'unknown');
      const zones = (them.get('zones') as Zone[] | undefined) ?? [];
      const was = zones.find((z) => z.serviceType === group.service);
      const others = zones.filter((z) => z.serviceType !== group.service);
      const next = member ? [...others, was ?? { serviceType: group.service, duties, smallGroups }] : others;
      tx.update(target, { zones: next, zoneTypes: [...new Set(next.map((z) => z.serviceType))] });
    } else {
      const current = strings(them.get('ministries'));
      tx.update(target, { ministries: member ? [...new Set([...current, group.ministry])] : current.filter((m) => m !== group.ministry) });
    }
  });
}
