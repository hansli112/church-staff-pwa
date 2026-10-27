import { FieldValue, type DocumentSnapshot, type Transaction } from 'firebase-admin/firestore';

import { accessIn, churchAccess } from './access.js';
import { fail, record, text, type Caller, type Deps } from './common.js';
import { weekdayOf } from './attendance.js';
import { identitiesOf, withIdentities, type Identity } from './identities.js';
import { TEXT_LIMITS } from './limits.js';

/**
 * 小組 (#85): churches/{cid}/smallGroups/{id}, each in one service
 * (`service`), with `name` and, for 回報人數, when it meets (`weekday`,
 * `every` 1 or 2 weeks, `startsOn` a day it met). settings/smallGroups
 * keeps every ID ever used (`ids`), which the rules check members' fields
 * against. An admin or the service's 負責人 or 牧者 opens, changes and
 * closes one and names its 小組長; its 小組長 may set when it meets (a 身分, `{kind: 'lead', smallGroup}`,
 * with `leadSmallGroups` for the rules), which the rules cannot let them
 * write on another member: all of it is done here.
 */

const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

const DAY = /^\d{4}-\d{2}-\d{2}$/;

/** Makes or takes away [m]'s 小組長 of [id], with the projection the rules read, and writes [also] with it. */
function setLead(tx: Transaction, m: DocumentSnapshot, id: string, lead: boolean, also: Record<string, unknown> = {}) {
  const others = identitiesOf(m.data()!).filter((i) => !('smallGroup' in i && i.smallGroup === id));
  tx.update(m.ref, { ...withIdentities(m.data()!, lead ? [...others, { kind: 'lead', smallGroup: id }] : others), ...also });
}

/**
 * `{ churchId, op: 'save', group: { id?, name, service, weekday?, every?,
 * startsOn? }, leads? }` opens a 小組 (no id) or changes one, and with
 * `leads` (uids) makes them its 小組長 and nobody else; `{ churchId, op:
 * 'delete', id }` closes it, taking it off its 小組長 and 同工. Its 人數
 * stay. Returns its id.
 */
export async function editSmallGroup(deps: Deps, caller: Caller | null, data: unknown) {
  const access = await churchAccess(deps, caller, data, 'member');
  const { cid } = access;
  const input = record(data);
  if (input.op !== 'save' && input.op !== 'delete') fail('invalid-argument', 'unknown');
  const saving = input.op === 'save';
  const group = saving ? record(input.group) : {};
  const id = saving ? group.id : input.id;
  if (id !== undefined && (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(id))) fail('invalid-argument', 'unknown');
  if (!saving && id === undefined) fail('invalid-argument', 'unknown');
  const fields = saving ? smallGroupFields(group) : null;
  const leads = input.leads === undefined ? null : strings(input.leads);
  if (leads && (!Array.isArray(input.leads) || leads.length !== input.leads.length || leads.length > 20
      || leads.some((u) => !/^[A-Za-z0-9_-]{1,128}$/.test(u)))) fail('invalid-argument', 'unknown');

  const root = deps.db.doc(`churches/${cid}`);
  const at = id === undefined ? root.collection('smallGroups').doc() : root.collection('smallGroups').doc(id as string);
  await deps.db.runTransaction(async (tx) => {
    const { powers, docs: [services, was] } = await accessIn(tx, deps, access, root.collection('settings').doc('services'), at);
    if (id !== undefined && !was.exists) fail('not-found', 'notFound');
    const before = was.exists ? (was.get('service') as string) : null;
    const after = (fields?.service as string | undefined) ?? null;
    // Its 小組長 set when it meets, and nothing else.
    const scheduling = was.exists && fields !== null && leads === null
      && fields.name === was.get('name') && fields.service === before
      && powers.schedulesSmallGroup({ kind: 'small', id: at.id, service: before });
    if (!scheduling && !powers.mayEditSmallGroup(before, after)) fail('permission-denied', 'permissionDenied');
    if (after !== null && !((services.get('services') as { id: string }[] | undefined) ?? []).some((s) => s.id === after)) {
      fail('invalid-argument', 'unknown');
    }
    // Who leads it now, and who is one of it: changed with it.
    const [nowLeads, staff] = await Promise.all([
      tx.get(root.collection('members').where('leadSmallGroups', 'array-contains', at.id)),
      saving ? null : tx.get(root.collection('members').where('smallGroups', 'array-contains', at.id)),
    ]);
    const named = leads ? ((leads.length ? await tx.getAll(...leads.map((u) => root.collection('members').doc(u))) : []) as DocumentSnapshot[]) : [];
    if (named.some((m) => !m.exists)) fail('not-found', 'notFound');

    if (!saving) {
      tx.delete(at);
      const out = { smallGroups: FieldValue.arrayRemove(at.id) };
      for (const m of nowLeads.docs) setLead(tx, m, at.id, false, out);
      for (const m of staff!.docs) if (!nowLeads.docs.some((l) => l.id === m.id)) tx.update(m.ref, out);
      return;
    }
    tx.set(at, fields!);
    tx.set(root.collection('settings').doc('smallGroups'), { ids: FieldValue.arrayUnion(at.id) }, { merge: true });
    if (leads) {
      for (const m of nowLeads.docs) if (!leads.includes(m.id)) setLead(tx, m, at.id, false);
      for (const m of named) if (!nowLeads.docs.some((l) => l.id === m.id)) setLead(tx, m, at.id, true);
    }
  });
  return { id: at.id };
}

/** What a 小組 is, as the app sends it, checked. */
function smallGroupFields(g: Record<string, unknown>) {
  const service = g.service;
  if (typeof service !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(service)) fail('invalid-argument', 'unknown');
  const out: Record<string, unknown> = { name: text(g.name, TEXT_LIMITS.profileName), service };
  if (g.weekday !== undefined && g.weekday !== null) {
    if (!Number.isInteger(g.weekday) || (g.weekday as number) < 1 || (g.weekday as number) > 7) fail('invalid-argument', 'unknown');
    out.weekday = g.weekday;
  }
  if (g.every !== undefined && g.every !== null) {
    if (g.every !== 1 && g.every !== 2) fail('invalid-argument', 'unknown');
    out.every = g.every;
  }
  if (g.startsOn !== undefined && g.startsOn !== null) {
    // A day it meets: on its weekday.
    if (typeof g.startsOn !== 'string' || !DAY.test(g.startsOn) || out.weekday === undefined
        || weekdayOf(g.startsOn) !== out.weekday) fail('invalid-argument', 'unknown');
    out.startsOn = g.startsOn;
  }
  return out;
}


// From the names self-host and older versions kept (`zones[].smallGroups`).

/** The 小組 a member's [zones] name, once each: `{ service, name }`. */
export function namedSmallGroups(zones: unknown) {
  const out = new Map<string, { service: string; name: string }>();
  for (const z of (Array.isArray(zones) ? zones : []) as { serviceType?: unknown; smallGroups?: unknown }[]) {
    if (typeof z?.serviceType !== 'string') continue;
    for (const name of strings(z.smallGroups)) {
      const n = name.trim();
      if (n) out.set(nameKey(z.serviceType, n), { service: z.serviceType, name: n });
    }
  }
  return [...out.values()];
}

/** How [smallGroupsByName] keys a 小組. */
export const nameKey = (service: string, name: string) => `${service}\u0000${name.trim()}`;

/** The 小組 in [docs] (churches/{cid}/smallGroups) by service and name; the first, for two of one name. */
export function smallGroupsByName(docs: DocumentSnapshot[]) {
  const out = new Map<string, string>();
  for (const g of [...docs].sort((a, b) => a.id.localeCompare(b.id))) {
    const key = nameKey(g.get('service') as string, g.get('name') as string);
    if (!out.has(key)) out.set(key, g.id);
  }
  return out;
}

/**
 * What a member moved from self-host or an older version is in, by the
 * names their [zones] keep: the 小組 they are one of (`smallGroups`), and
 * for a 小組長 there (`role` leader) the 身分 of leading those.
 */
export function claimedSmallGroups(zones: unknown, role: unknown, byName: Map<string, string>) {
  const ids = [...new Set(namedSmallGroups(zones).flatMap((g) => byName.get(nameKey(g.service, g.name)) ?? []))];
  return {
    smallGroups: ids,
    identities: role === 'leader' ? ids.map((smallGroup): Identity => ({ kind: 'lead', smallGroup })) : [],
  };
}
