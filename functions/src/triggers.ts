import { FieldValue, type DocumentSnapshot } from 'firebase-admin/firestore';
import type { Storage } from 'firebase-admin/storage';

import { CHURCH_ID } from './access.js';
import type { Deps } from './common.js';
import { ICON_FILES, iconStoragePath, makeIcons } from './icons.js';
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

export type LogoDeps = Deps & { bucket: Pick<ReturnType<Storage['bucket']>, 'file' | 'getFiles'> };

/**
 * After a logo upload: make the home-screen icons next to it, then bump the
 * church's logoVersion so apps refetch it and the church page links the new
 * icons (logoIcons says they exist for that version). A logo that cannot be
 * read still gets its version; the church page then uses it as is.
 */
export async function onLogoUploaded(deps: LogoDeps, path: string, generation: string) {
  const match = new RegExp(`^churches/(${CHURCH_ID})/logo\\.png$`).exec(path);
  if (!match) return false;
  const cid = match[1];
  const ref = deps.db.doc(`churches/${cid}`);
  if (!(await ref.get()).exists) return false;

  let icons = false;
  try {
    const [logo] = await deps.bucket.file(path).download();
    const made = await makeIcons(logo);
    await Promise.all(
      ICON_FILES.map((f) =>
        deps.bucket.file(iconStoragePath(cid, generation, f)).save(made[f], { contentType: 'image/png', resumable: false }),
      ),
    );
    icons = true;
  } catch (e) {
    console.error(`onLogoUploaded: no icons for ${cid}`, e);
  }

  const applied = await deps.db.runTransaction(async (tx) => {
    const current = (await tx.get(ref)).get('logoVersion') as string | undefined;
    // Two uploads close together can finish out of order; the newer wins.
    if (current && /^\d+$/.test(current) && /^\d+$/.test(generation) && BigInt(current) > BigInt(generation)) return false;
    tx.update(ref, { logoVersion: generation, logoIcons: icons ? generation : FieldValue.delete() });
    return true;
  });

  // Icons of older logos are no longer linked from anywhere. Never touch a
  // newer upload's: its trigger may still be about to link them. A late,
  // older upload removes only its own.
  const [files] = await deps.bucket.getFiles({ prefix: `churches/${cid}/logo-` });
  const versionOf = (name: string) => /\/logo-(\d+)-[^/]+$/.exec(name)?.[1];
  const stale = files.filter((f) => {
    const v = versionOf(f.name);
    if (!v || !/^\d+$/.test(generation)) return false;
    return applied ? BigInt(v) < BigInt(generation) : v === generation;
  });
  await Promise.all(stale.map((f) => f.delete({ ignoreNotFound: true })));
  return true;
}
