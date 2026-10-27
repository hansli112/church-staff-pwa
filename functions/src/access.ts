import type { DocumentReference, DocumentSnapshot, Transaction } from 'firebase-admin/firestore';

import { fail, requireCaller, type Caller, type Deps } from './common.js';
import { ledDuties, ministriesOf } from './ministries.js';
import { powersOf, type Powers } from './powers.js';

/**
 * Church access: every callable that acts in one church starts here. It
 * turns the request into the church, the caller's membership there and what
 * that lets them do ([Powers]), the way firestore.rules decides it for
 * direct writes (isMember, isAdmin, inGroup, canEditRosterType).
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
 *   has the service type, and the caller is admin, 行政 (roster-editors,
 *   every service) or leads it (`leadTypes`: its 負責人 or 牧者, #82).
 * - `{ arranges: type }`: a roster editor of it, or a 事工's 負責人 whose
 *   事工 links one of its duties (they arrange only those, through
 *   editLedDuties): photo import is theirs too.
 */
export type Level = 'anyone' | 'member' | 'admin' | { group: Group } | { rosterEditor: string } | { arranges: string };

export interface ChurchAccess {
  cid: string;
  caller: Caller;
  church: DocumentSnapshot;
  /** The caller's member doc; missing only for `anyone`. */
  member: DocumentSnapshot;
  /** Whether the church is active. False only with `closed: 'allow'`. */
  open: boolean;
  /** What the caller may do there. */
  powers: Powers;
}

/**
 * A church's status: open (`active`), suspended by the platform operator,
 * or deleted by its admin (restorable for RESTORE_DAYS, then purged).
 */
export type ChurchStatus = 'active' | 'suspended' | 'deleted';

/** Whether [church] is open: not suspended, deleted or missing. */
export const isChurchOpen = (church: DocumentSnapshot | null | undefined) =>
  church?.get('status') === 'active';

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
  const open = isChurchOpen(church);
  if (!open && opts.closed !== 'allow') churchClosed();

  const powers = powersOf(member.data() ?? {});
  const access: ChurchAccess = {
    cid,
    caller: c,
    church,
    member,
    open,
    powers,
  };
  if (!(await has(deps, access, level))) fail('permission-denied', 'permissionDenied');
  return access;
}

async function has(deps: Deps, a: ChurchAccess, level: Level) {
  if (level === 'anyone' || level === 'member') return true;
  if (level === 'admin') return a.powers.admin;
  if ('group' in level) return a.powers.inGroup(level.group);
  if ('arranges' in level) {
    if (await has(deps, a, { rosterEditor: level.arranges })) return true;
    if (a.powers.ministries.length === 0) return false;
    const doc = await deps.db.doc(`churches/${a.cid}/settings/ministries`).get();
    return ledDuties(ministriesOf(doc), a.powers.ministries, level.arranges).size > 0;
  }
  const type = level.rosterEditor;
  if (!(await serviceTypes(deps, a.cid)).includes(type)) return false;
  return a.powers.editsRosters(type);
}

/**
 * [a] read again in transaction [tx], with [refs]: a member gone or a
 * church closed meanwhile is refused as [churchAccess] refuses, and what
 * they may do is as they are now (a lead taken away meanwhile writes
 * nothing). Returns their powers and [refs]' docs.
 */
export async function accessIn(tx: Transaction, deps: Deps, a: ChurchAccess, ...refs: DocumentReference[]) {
  const [church, me, ...docs] = (await tx.getAll(
    deps.db.doc(`churches/${a.cid}`),
    deps.db.doc(`churches/${a.cid}/members/${a.caller.uid}`),
    ...refs,
  )) as DocumentSnapshot[];
  if (!me.exists) fail('permission-denied', 'permissionDenied');
  if (!isChurchOpen(church)) churchClosed();
  return { powers: powersOf(me.data()!), docs };
}

/**
 * Every service ID the church has ever had (firestore.rules serviceTypes):
 * settings/services `ids` only grows.
 */
async function serviceTypes(deps: Deps, cid: string) {
  const doc = await deps.db.doc(`churches/${cid}/settings/services`).get();
  return (doc.get('ids') as string[] | undefined) ?? [];
}
