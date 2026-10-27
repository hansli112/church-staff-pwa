/**
 * 身分 (#82) on a member doc: `identities`, beside what the rules read of
 * them (`role`, `groups`, `leadTypes`, `leadMinistries`,
 * `leadSmallGroups`). Every backend write of someone's 身分 goes through
 * [withIdentities], as every app write goes through Member.withIdentities
 * (testdata/church_rules.json, memberIdentities and identityProjection).
 */

export type Identity =
  | { kind: 'admin' }
  | { kind: 'office' }
  | { kind: 'pastor'; services?: string[] }
  | { kind: 'lead'; service: string }
  | { kind: 'lead'; ministry: string }
  | { kind: 'lead'; smallGroup: string };

const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

/** One stored 身分; null for a kind not known. */
function parse(v: unknown): Identity | null {
  const i = (v ?? {}) as Record<string, unknown>;
  if (i.kind === 'admin' || i.kind === 'office') return { kind: i.kind };
  if (i.kind === 'pastor') return Array.isArray(i.services) ? { kind: 'pastor', services: strings(i.services) } : { kind: 'pastor' };
  if (i.kind !== 'lead') return null;
  if (typeof i.service === 'string') return { kind: 'lead', service: i.service };
  if (typeof i.ministry === 'string') return { kind: 'lead', ministry: i.ministry };
  if (typeof i.smallGroup === 'string') return { kind: 'lead', smallGroup: i.smallGroup };
  return null;
}

const key = (i: Identity) => JSON.stringify(i);

export const sameIdentity = (a: Identity, b: Identity) => key(a) === key(b);

const isAdminIdentity = (i: Identity) => i.kind === 'admin' || (i.kind === 'pastor' && i.services === undefined);

/**
 * The 身分 member doc [m] holds, as the app reads it (Member.identities):
 * those stored, with 管理員 for role admin and 行政 for the old permission
 * groups when none says so, and a 小組長 an app from before #85 dropped.
 */
export function identitiesOf(m: Record<string, unknown>): Identity[] {
  const stored = (Array.isArray(m.identities) ? m.identities : []).map(parse).filter((i): i is Identity => i !== null);
  const admin = m.role === 'admin';
  return [
    ...(admin && !stored.some(isAdminIdentity) ? [{ kind: 'admin' } as const] : []),
    ...(!admin && strings(m.groups).length > 0 && !stored.some((i) => i.kind === 'office') ? [{ kind: 'office' } as const] : []),
    ...stored,
    ...strings(m.leadSmallGroups)
      .filter((g) => !stored.some((i) => 'smallGroup' in i && i.smallGroup === g))
      .map((smallGroup) => ({ kind: 'lead', smallGroup }) as const),
  ];
}

/**
 * Member doc [m] holding [next] as their 身分: the fields to write, with
 * what the rules read set to match. 管理員 and a whole church's 牧者 are
 * role admin, 行政 the two permission groups.
 */
export function withIdentities(m: Record<string, unknown>, next: Identity[]) {
  const identities = [...new Map(next.map((i) => [key(i), i])).values()];
  const admin = identities.some(isAdminIdentity);
  const role = admin ? 'admin' : m.role === 'admin' || typeof m.role !== 'string' ? 'staff' : m.role;
  const each = (f: (i: Identity) => string[]) => [...new Set(identities.flatMap(f))];
  return {
    role,
    groups: identities.some((i) => i.kind === 'office') ? ['roster-editors', 'calendar-editors'] : [],
    identities,
    leadTypes: each((i) => ('service' in i ? [i.service] : i.kind === 'pastor' ? (i.services ?? []) : [])),
    leadMinistries: each((i) => ('ministry' in i ? [i.ministry] : [])),
    leadSmallGroups: each((i) => ('smallGroup' in i ? [i.smallGroup] : [])),
  };
}
