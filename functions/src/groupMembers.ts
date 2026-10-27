import { accessIn, churchAccess } from './access.js';
import { fail, record, strings, type Caller, type Deps } from './common.js';
import { ministriesOf } from './ministries.js';
import type { ChurchGroup } from './powers.js';

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

export async function setGroupMember(deps: Deps, caller: Caller | null, data: unknown) {
  const access = await churchAccess(deps, caller, data, 'member');
  const { cid } = access;
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
    const { powers, docs: [them, services, ministries, small] } = await accessIn(
      tx,
      deps,
      access,
      target,
      deps.db.doc(`churches/${cid}/settings/services`),
      deps.db.doc(`churches/${cid}/settings/ministries`),
      deps.db.doc(`churches/${cid}/smallGroups/${typeof smallGroup === 'string' ? smallGroup : '-'}`),
    );
    // The group as it is now: a deleted 事工 or 小組 takes no one.
    const group: ChurchGroup = typeof service === 'string'
      ? { kind: 'service', id: service }
      : typeof ministry === 'string'
        ? { kind: 'ministry', id: ministry }
        : { kind: 'small', id: smallGroup as string, service: small.exists ? (small.get('service') as string) : null };
    const known = group.kind === 'ministry'
      ? ministriesOf(ministries).find((m) => m.id === group.id)
      : group.kind === 'small'
        ? (small.exists ? small : undefined)
        : (services.get('services') as { id: string; duties?: string[] }[] | undefined)?.find((s) => s.id === group.id);
    if (!known) fail('permission-denied', 'permissionDenied');
    if (!them.exists) fail('not-found', 'notFound');
    if (!powers.mayMove(them.data()!, group)) fail('permission-denied', 'permissionDenied');
    if (group.kind === 'small') {
      const current = strings(them.get('smallGroups'));
      tx.update(target, { smallGroups: member ? [...new Set([...current, group.id])] : current.filter((g) => g !== group.id) });
    } else if (group.kind === 'service') {
      const serves = (known as { duties?: string[] }).duties ?? [];
      if (duties.some((d) => !serves.includes(d))) fail('invalid-argument', 'unknown');
      const zones = (them.get('zones') as Zone[] | undefined) ?? [];
      const was = zones.find((z) => z.serviceType === group.id);
      const others = zones.filter((z) => z.serviceType !== group.id);
      const next = member ? [...others, was ?? { serviceType: group.id, duties, smallGroups }] : others;
      tx.update(target, { zones: next, zoneTypes: [...new Set(next.map((z) => z.serviceType))] });
    } else {
      const current = strings(them.get('ministries'));
      tx.update(target, { ministries: member ? [...new Set([...current, group.id])] : current.filter((m) => m !== group.id) });
    }
  });
}
