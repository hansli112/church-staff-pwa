import type { DocumentSnapshot } from 'firebase-admin/firestore';

import { fail, requireCaller, type Caller, type Deps } from './common.js';

/**
 * Church access: every callable that acts in one church starts here. It
 * turns the request into the church, the caller's membership there and what
 * that lets them do, the way firestore.rules decides it for direct writes
 * (isMember, isAdmin, inGroup, canEditRosterType).
 *
 * The order of refusals:
 * 1. not signed in, or no member of the church → permissionDenied (a
 *    stranger learns nothing about the church);
 * 2. the church is not active (教會停用: suspended by the operator, or
 *    deleted by its admin) → churchClosed, whatever the member may do;
 * 3. the member lacks the level → permissionDenied.
 *
 * Invites (invites.ts) and the church preview do not come here: they are
 * for people who are not members, and say inviteInvalid / notFound.
 */

/** A church ID: Firestore's auto IDs are 20 letters and digits. */
export const CHURCH_ID = '[A-Za-z0-9]{1,64}';
const churchIdPattern = new RegExp(`^${CHURCH_ID}$`);

export const isChurchId = (value: unknown): value is string =>
  typeof value === 'string' && churchIdPattern.test(value);

/** [value] as a church ID, or an invalid-argument failure. */
export function churchId(value: unknown): string {
  if (!isChurchId(value)) fail('invalid-argument', 'unknown');
  return value;
}

/** Permission groups (firestore.rules hasValidGroups). Admins hold every one. */
export type Group = 'roster-editors' | 'calendar-editors';

/**
 * What the caller must be in the church:
 * - `anyone`: signed in, member or not (claiming a pending member);
 * - `member`: any member;
 * - `admin`;
 * - `{ group }`: admin, or in the group;
 * - `{ rosterEditor: type }`: may edit that service's rosters: the church
 *   has the service type, and the caller is admin or a roster editor with
 *   a zone in it.
 */
export type Level = 'anyone' | 'member' | 'admin' | { group: Group } | { rosterEditor: string };

export interface ChurchAccess {
  cid: string;
  caller: Caller;
  church: DocumentSnapshot;
  /** The caller's member doc; missing only for `anyone`. */
  member: DocumentSnapshot;
  admin: boolean;
  /** Whether the church is active. False only with `closed: 'allow'`. */
  open: boolean;
  inGroup(group: Group): boolean;
}

/** Fails with churchClosed: the church is suspended or deleted. */
export function churchClosed(): never {
  fail('failed-precondition', 'churchClosed');
}

/**
 * The caller's access to the church `data.churchId`, which must be open and
 * where they must have [level]. With `closed: 'allow'` a closed church
 * passes too (restoring a deleted church).
 */
export async function churchAccess(
  deps: Deps,
  caller: Caller | null,
  data: unknown,
  level: Level,
  opts: { closed?: 'allow' } = {},
): Promise<ChurchAccess> {
  const c = requireCaller(caller);
  const cid = churchId((data as { churchId?: unknown })?.churchId);
  const [church, member] = await Promise.all([
    deps.db.doc(`churches/${cid}`).get(),
    deps.db.doc(`churches/${cid}/members/${c.uid}`).get(),
  ]);
  if (level === 'anyone') {
    if (!church.exists) fail('not-found', 'notFound');
  } else if (!member.exists) {
    fail('permission-denied', 'permissionDenied');
  }
  const open = church.get('status') === 'active';
  if (!open && opts.closed !== 'allow') churchClosed();

  const admin = member.exists && member.get('role') === 'admin';
  const groups = (member.get('groups') as string[] | undefined) ?? [];
  const access: ChurchAccess = {
    cid,
    caller: c,
    church,
    member,
    admin,
    open,
    inGroup: (group) => admin || (member.exists && groups.includes(group)),
  };
  if (!(await has(deps, access, level))) fail('permission-denied', 'permissionDenied');
  return access;
}

async function has(deps: Deps, a: ChurchAccess, level: Level) {
  if (level === 'anyone' || level === 'member') return true;
  if (level === 'admin') return a.admin;
  if ('group' in level) return a.inGroup(level.group);
  const type = level.rosterEditor;
  if (!(await serviceTypes(deps, a.cid)).includes(type)) return false;
  return a.admin
    || (a.inGroup('roster-editors') && ((a.member.get('zoneTypes') as string[] | undefined) ?? []).includes(type));
}

/**
 * Every service ID the church has ever had (firestore.rules serviceTypes):
 * settings/services `ids` only grows.
 */
async function serviceTypes(deps: Deps, cid: string) {
  const doc = await deps.db.doc(`churches/${cid}/settings/services`).get();
  return (doc.get('ids') as string[] | undefined) ?? [];
}
