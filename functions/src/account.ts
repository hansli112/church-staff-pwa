import type { Auth } from 'firebase-admin/auth';
import { Timestamp } from 'firebase-admin/firestore';

import { isChurchOpen } from './access.js';
import { fail, requireCaller, type Caller, type Deps } from './common.js';
import { forgetJoinRequestsOf } from './joinRequests.js';

/**
 * Deletes the caller's account (App Store guideline 5.1.1(v)): every
 * membership, users/{uid}, their requests to join, then the Auth user. Names already on rosters
 * stay, as plain text.
 *
 * The only admin of a church others are in must hand it over first, so no
 * church is left without someone who can manage it. The error lists those
 * churches. A church with no one else in it is deleted along with the
 * account, as deleteChurch would, and cleaned up after RESTORE_DAYS.
 */
export async function deleteAccount(deps: Deps & { auth: Auth }, caller: Caller | null) {
  const c = requireCaller(caller);
  const { db } = deps;
  const memberships = await db.collectionGroup('members').where('uid', '==', c.uid).get();

  const blocking: string[] = [];
  const alone: FirebaseFirestore.DocumentReference[] = [];
  for (const m of memberships.docs) {
    if (m.get('role') !== 'admin') continue;
    const church = m.ref.parent.parent!;
    const churchSnap = await church.get();
    if (churchSnap.get('status') === 'deleted') continue;
    const admins = await church.collection('members').where('role', '==', 'admin').limit(2).get();
    if (admins.size >= 2) continue;
    const members = await church.collection('members').limit(2).get();
    if (members.size >= 2) blocking.push(churchSnap.get('name') as string);
    else if (isChurchOpen(churchSnap)) alone.push(church);
  }
  if (blocking.length > 0) fail('failed-precondition', 'lastAdmin', blocking);
  // First: should it fail, nothing else is gone yet.
  await forgetJoinRequestsOf(deps, c.uid);

  const writer = db.bulkWriter();
  const deletedAt = Timestamp.fromDate(deps.now());
  for (const church of alone) void writer.update(church, { status: 'deleted', deletedAt });
  for (const m of memberships.docs) void writer.delete(m.ref);
  void writer.delete(db.doc(`users/${c.uid}`));
  await writer.close();
  await deps.auth.deleteUser(c.uid);
  return {};
}
