import { FieldValue, type DocumentSnapshot } from 'firebase-admin/firestore';
import type { Storage } from 'firebase-admin/storage';

import { CHURCH_ID, isChurchOpen } from './access.js';
import { releaseCalendarIfConnector, type CalDeps } from './calendar.js';
import { runEach, type Deps } from './common.js';
import { identitiesOf, sameIdentity, type Identity } from './identities.js';
import type { NamedIdentity } from './languages.js';
import { ministriesOf } from './ministries.js';
import { forgetNotificationsFrom } from './notificationList.js';
import { ICON_FILES, iconStoragePath, makeIcons } from './icons.js';
import { personName } from './limits.js';
import { adminUids, notifyMembers, type PushDeps } from './push.js';
import { loggable } from './redact.js';

/**
 * Who made a Firestore write, from a trigger's auth context: the uid of a
 * person, or undefined for the backend itself (authType `system`).
 */
export const editorOf = (auth: { authType: string; authId?: string }) =>
  auth.authType === 'system' ? undefined : auth.authId;

/**
 * A member doc deleted: removed by an admin, left on their own, or their
 * account deleted. A calendar they connected goes with them, so do the
 * church's notifications in their 通知列表, and their leaving is told to
 * the admins; one failing never stops the others.
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
    notifications: () => forgetNotificationsFrom(deps.db, member.id, cid),
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
  const name = member.get('name') as string | undefined;
  return notifyMembers(deps, cid, await adminUids(deps.db, cid), 'memberLeft', (w) => ({
    title: church.get('name') as string,
    body: w.memberLeft(name || null),
    link: '/me/members',
  }));
}

/**
 * A member given a 身分 by someone else (an admin, a 負責人 naming a
 * 小組長, the backend) is told what they are now: one push, opening 首頁,
 * where 開始使用 shows what to do first. Not what they gave themself, nor
 * what was taken away. Returns how many devices it reached.
 */
export async function onIdentitiesGiven(
  deps: PushDeps,
  cid: string,
  before: DocumentSnapshot,
  after: DocumentSnapshot,
  editor: string | undefined,
) {
  if (!after.exists || editor === after.id) return 0;
  const had = identitiesOf(before.data() ?? {});
  const given = identitiesOf(after.data()!).filter((i) => !had.some((h) => sameIdentity(h, i)));
  if (given.length === 0) return 0;
  const root = deps.db.doc(`churches/${cid}`);
  const smallGroupIds = given.flatMap((i) => ('smallGroup' in i ? [i.smallGroup] : []));
  const [church, services, ministries, ...smallGroups] = await deps.db.getAll(
    root,
    root.collection('settings').doc('services'),
    root.collection('settings').doc('ministries'),
    ...smallGroupIds.map((id) => root.collection('smallGroups').doc(id)),
  );
  if (!isChurchOpen(church)) return 0;
  const serviceList = (services.get('services') as { id: string; name: string }[] | undefined) ?? [];
  const service = (id: string) => serviceList.find((s) => s.id === id)?.name ?? id;
  const ministry = (id: string) => ministriesOf(ministries).find((m) => m.id === id)?.name ?? id;
  const smallGroup = (id: string) => (smallGroups.find((g) => g.id === id)?.get('name') as string | undefined) ?? id;
  const named = (i: Identity): NamedIdentity => {
    if (i.kind === 'admin' || i.kind === 'office') return i;
    if (i.kind === 'pastor') return { kind: 'pastor', of: i.services?.map(service) ?? null };
    if ('service' in i) return { kind: 'lead', of: service(i.service) };
    if ('ministry' in i) return { kind: 'lead', of: ministry(i.ministry) };
    return { kind: 'smallGroupLead', of: smallGroup(i.smallGroup) };
  };
  return notifyMembers(deps, cid, [after.id], 'identity', (w) => ({
    title: church.get('name') as string,
    body: w.identityGiven(given.map(named)),
    link: '/home',
  }));
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
    console.error(`onLogoUploaded: no icons for ${cid}`, loggable(e));
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
