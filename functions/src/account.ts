import type { Auth } from 'firebase-admin/auth';

import { fail, requireCaller, type Caller, type Deps } from './common.js';

/**
 * Deletes the caller's account (App Store guideline 5.1.1(v)): every
 * membership, users/{uid}, then the Auth user. Names already on rosters
 * stay, as plain text.
 *
 * The only admin of a church must hand it over first, so no church is left
 * without someone who can manage it. The error lists those churches.
 */
export async function deleteAccount(deps: Deps & { auth: Auth }, caller: Caller | null) {
  const c = requireCaller(caller);
  const { db } = deps;
  const memberships = await db.collectionGroup('members').where('uid', '==', c.uid).get();

  const blocking: string[] = [];
  for (const m of memberships.docs) {
    if (m.get('role') !== 'admin') continue;
    const church = m.ref.parent.parent!;
    const churchSnap = await church.get();
    if (churchSnap.get('status') === 'deleted') continue;
    const admins = await church.collection('members').where('role', '==', 'admin').limit(2).get();
    if (admins.size < 2) blocking.push(churchSnap.get('name') as string);
  }
  if (blocking.length > 0) fail('failed-precondition', 'lastAdmin', blocking);

  const writer = db.bulkWriter();
  for (const m of memberships.docs) void writer.delete(m.ref);
  void writer.delete(db.doc(`users/${c.uid}`));
  await writer.close();
  await deps.auth.deleteUser(c.uid);
  return {};
}
