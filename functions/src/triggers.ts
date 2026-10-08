import { FieldValue, type DocumentSnapshot } from 'firebase-admin/firestore';
import type { Storage } from 'firebase-admin/storage';

import { CHURCH_ID, isChurchOpen } from './access.js';
import { releaseCalendarIfConnector, type CalDeps } from './calendar.js';
import { runEach, type Deps } from './common.js';
import { ICON_FILES, iconStoragePath, makeIcons } from './icons.js';
import { personName } from './limits.js';
import { adminUids, notifyMembers, type PushDeps } from './push.js';

/**
 * Who made a Firestore write, from a trigger's auth context: the uid of a
 * person, or undefined for the backend itself (authType `system`).
 */
export const editorOf = (auth: { authType: string; authId?: string }) =>
  auth.authType === 'system' ? undefined : auth.authId;

/**
 * A member doc deleted: removed by an admin, left on their own, or their
 * account deleted. A calendar they connected goes with them, and their
 * leaving is told to the admins; one failing never stops the other.
 */
export async function onMemberDeleted(
  deps: CalDeps & PushDeps,
  cid: string,
  member: DocumentSnapshot,
  deletedBy: string | undefined,
) {
  return runEach(`member ${cid}/${member.id} deleted`, {
    calendar: () => releaseCalendarIfConnector(deps, cid, member.id),
    memberLeft: () => onMemberLeft(deps, cid, member, deletedBy),
  });
}

/**
 * A member doc changed. An admin who is no longer one lets go of the
 * church's calendar if they connected it. Returns whether it was released.
 */
export async function onMemberUpdated(deps: CalDeps, cid: string, before: DocumentSnapshot, after: DocumentSnapshot) {
  if (before.get('role') !== 'admin' || after.get('role') === 'admin') return false;
  return releaseCalendarIfConnector(deps, cid, after.id);
}

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
  const raw = after?.get('name') as unknown;
  const name = personName(raw);
  if (!after?.exists || name === '') return 0;
  if (before?.get('name') === raw) return 0;
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
  if (!isChurchOpen(church)) return 0;
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
