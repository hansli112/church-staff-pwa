import type { DocumentSnapshot } from 'firebase-admin/firestore';

import type { Deps } from './common.js';
import { adminUids, notifyMembers, type PushDeps } from './push.js';

/**
 * A member's name lives on each member doc (what the church sees) and on
 * users/{uid} (what they edit). Rules let them write only the latter, so
 * this copies a changed name to every church they belong to.
 */
export async function syncProfileName(
  deps: Deps,
  uid: string,
  before: DocumentSnapshot | undefined,
  after: DocumentSnapshot | undefined,
) {
  const name = after?.get('name') as string | undefined;
  if (!after?.exists || typeof name !== 'string' || name.trim() === '') return 0;
  if (before?.get('name') === name) return 0;
  const memberships = await deps.db.collectionGroup('members').where('uid', '==', uid).get();
  const stale = memberships.docs.filter((m) => m.get('name') !== name);
  await Promise.all(stale.map((m) => m.ref.update({ name })));
  return stale.length;
}

/**
 * When someone leaves a church on their own (their own uid deleted the
 * doc, not an admin), tell the church's admins.
 */
export async function onMemberLeft(
  deps: PushDeps,
  cid: string,
  member: DocumentSnapshot,
  deletedBy: string | undefined,
) {
  if (!deletedBy || deletedBy !== member.id) return 0;
  const church = await deps.db.doc(`churches/${cid}`).get();
  if (church.get('status') !== 'active') return 0;
  const name = (member.get('name') as string | undefined) || '有人';
  return notifyMembers(deps, cid, await adminUids(deps.db, cid), 'memberLeft', {
    title: church.get('name') as string,
    body: `${name} 退出了教會`,
    link: '/me/members',
  });
}

/** After a logo upload, bump the church's logoVersion so apps refetch it. */
export async function onLogoUploaded(deps: Deps, path: string, generation: string) {
  const match = /^churches\/([A-Za-z0-9]+)\/logo\.png$/.exec(path);
  if (!match) return false;
  const ref = deps.db.doc(`churches/${match[1]}`);
  if (!(await ref.get()).exists) return false;
  await ref.update({ logoVersion: generation });
  return true;
}
