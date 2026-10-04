import { Timestamp } from 'firebase-admin/firestore';
import type { Storage } from 'firebase-admin/storage';

import { fail, requireCaller, requireChurchAdmin, serverTime, text, type Caller, type Deps } from './common.js';
import { nameKey } from './text.js';

/** How long a deleted church can be restored. */
export const RESTORE_DAYS = 30;

/**
 * The services a new church starts with. Mirrors defaultServices in
 * app/lib/data/memory/memory_backend.dart.
 */
export const DEFAULT_SERVICES = [
  {
    id: 'sunday',
    name: '主日崇拜',
    weekday: 7,
    enabled: true,
    duties: ['司會', '敬拜', '司琴', '音控', '投影', '招待'],
    events: [
      { name: '聖餐', color: 0 },
      { name: '浸禮', color: 4 },
    ],
  },
];

/**
 * Creates a church with the caller as its admin.
 *
 * Names are unique after normalization. The reservation lives in
 * churchNames/{nameKey}, written in the same transaction as the church, so
 * two people creating the same name at once cannot both succeed.
 */
export async function createChurch(deps: Deps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  if (!c.emailVerified) fail('failed-precondition', 'unverifiedEmail');
  const name = text((data as { name?: unknown })?.name, 60);
  const key = nameKey(name);
  if (!key) fail('invalid-argument', 'unknown');

  const { db } = deps;
  const churchRef = db.collection('churches').doc();
  const cid = churchRef.id;
  const profile = await db.doc(`users/${c.uid}`).get();
  const memberName = (profile.get('name') as string | undefined) || c.name || '';

  await db.runTransaction(async (tx) => {
    const reserved = await tx.get(db.doc(`churchNames/${key}`));
    if (reserved.exists) fail('already-exists', 'duplicateName');
    tx.create(db.doc(`churchNames/${key}`), { cid, createdAt: serverTime() });
    tx.create(churchRef, {
      name,
      nameKey: key,
      status: 'active',
      createdBy: c.uid,
      createdAt: serverTime(),
      deletedAt: null,
    });
    tx.create(churchRef.collection('members').doc(c.uid), {
      uid: c.uid,
      name: memberName,
      email: c.email ?? '',
      role: 'admin',
      groups: [],
      zones: [],
      zoneTypes: [],
      joinedAt: serverTime(),
    });
    tx.create(churchRef.collection('settings').doc('services'), {
      services: DEFAULT_SERVICES,
      ids: DEFAULT_SERVICES.map((s) => s.id),
      updatedAt: serverTime(),
    });
  });
  return { churchId: cid };
}

/** Marks the church deleted. Restorable for [RESTORE_DAYS] days. */
export async function deleteChurch(deps: Deps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const cid = churchId(data);
  await requireChurchAdmin(deps.db, cid, c);
  await deps.db.runTransaction(async (tx) => {
    const ref = deps.db.doc(`churches/${cid}`);
    // Only an open church can be deleted: deleting and restoring a church
    // the operator suspended would otherwise reopen it.
    if ((await tx.get(ref)).get('status') !== 'active') fail('failed-precondition', 'permissionDenied');
    tx.update(ref, { status: 'deleted', deletedAt: Timestamp.fromDate(deps.now()) });
  });
  return {};
}

export async function restoreChurch(deps: Deps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const cid = churchId(data);
  await requireChurchAdmin(deps.db, cid, c);
  await deps.db.runTransaction(async (tx) => {
    const ref = deps.db.doc(`churches/${cid}`);
    const snap = await tx.get(ref);
    if (snap.get('status') !== 'deleted') return;
    const deletedAt = snap.get('deletedAt') as Timestamp | null;
    if (deletedAt && deps.now().getTime() - deletedAt.toMillis() > RESTORE_DAYS * 86400e3) {
      fail('failed-precondition', 'unknown');
    }
    tx.update(ref, { status: 'active', deletedAt: null });
  });
  return {};
}

/**
 * Removes every church deleted more than [RESTORE_DAYS] days ago: the whole
 * churches/{cid} tree, its name reservation, invites and logo.
 */
export async function purgeDeletedChurches(deps: Deps, storage?: Storage, beforePurge?: (cid: string) => Promise<unknown>) {
  const cutoff = Timestamp.fromMillis(deps.now().getTime() - RESTORE_DAYS * 86400e3);
  const expired = await deps.db
    .collection('churches')
    .where('status', '==', 'deleted')
    .where('deletedAt', '<', cutoff)
    .get();
  const purged: string[] = [];
  for (const doc of expired.docs) {
    const key = doc.get('nameKey') as string | undefined;
    // Data kept outside the church tree, e.g. the calendar grant.
    if (beforePurge) await beforePurge(doc.id);
    await deps.db.recursiveDelete(doc.ref);
    if (key) await deps.db.doc(`churchNames/${key}`).delete();
    await deps.db.doc(`linkSources/${doc.id}`).delete();
    await deps.db.doc(`webhookSecrets/${doc.id}`).delete();
    await deps.db.recursiveDelete(deps.db.doc(`webhookOutbox/${doc.id}`));
    const invites = await deps.db.collection('invites').where('cid', '==', doc.id).get();
    await Promise.all(invites.docs.map((d) => d.ref.delete()));
    // The logo and the icons made from it.
    if (storage) await storage.bucket().deleteFiles({ prefix: `churches/${doc.id}/` });
    purged.push(doc.id);
  }
  return purged;
}

/**
 * Where the church page serves a church's logo, under its church URL. The
 * version is the logo's storage generation, so a new logo is a new URL.
 */
export function publicLogoPath(cid: string, version: string, file = 'logo.png') {
  return `/c/${cid}/icons/${version}/${file}`;
}

/**
 * Name and logo of an active church, for someone opening its church URL
 * who is not a member. Public: the same is on the church page anyway.
 */
export async function churchPreview(deps: Deps, _caller: Caller | null, data: unknown) {
  const cid = churchId(data);
  const snap = await deps.db.doc(`churches/${cid}`).get();
  if (snap.get('status') !== 'active') fail('not-found', 'notFound');
  const version = snap.get('logoVersion') as string | undefined;
  return {
    churchId: cid,
    name: snap.get('name') as string,
    logoPath: version ? publicLogoPath(cid, version) : null,
  };
}

function churchId(data: unknown): string {
  const value = (data as { churchId?: unknown })?.churchId;
  if (typeof value !== 'string' || !/^[A-Za-z0-9]{1,64}$/.test(value)) {
    fail('invalid-argument', 'unknown');
  }
  return value;
}
