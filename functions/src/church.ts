import { Timestamp } from 'firebase-admin/firestore';
import type { Storage } from 'firebase-admin/storage';

import { churchAccess, churchClosed, churchId, isChurchOpen } from './access.js';
import { forgetCalendar, type CalDeps } from './calendar.js';
import { forgetLinkSource } from './churchLink.js';
import { forgetPendingClaims } from './claim.js';
import { DAY_MS, fail, requireCaller, runEach, serverTime, text, type Caller, type Deps } from './common.js';
import { forgetInvites } from './invites.js';
import { personName, TEXT_LIMITS } from './limits.js';
import { nameKey } from './text.js';
import { forgetWebhook } from './webhook.js';

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
  const name = text((data as { name?: unknown })?.name, TEXT_LIMITS.churchName);
  return { churchId: await openChurch(deps, c, name) };
}

/**
 * Creates church [name] with [c] as its admin, in one transaction with the
 * name reservation. [services] and the admin's [zones] and [groups] come
 * from a move; [extra] goes on the church doc. Returns the church ID.
 */
export async function openChurch(
  deps: Deps,
  c: Caller,
  name: string,
  opts: {
    services?: { services: unknown[]; ids: string[] };
    admin?: { name?: string; groups?: string[]; zones?: unknown[]; zoneTypes?: string[] };
    extra?: Record<string, unknown>;
    /** A church ID picked beforehand, e.g. for data written first. */
    cid?: string;
  } = {},
) {
  if (!c.emailVerified) fail('failed-precondition', 'unverifiedEmail');
  const key = nameKey(name);
  if (!key) fail('invalid-argument', 'unknown');

  const { db } = deps;
  const churchRef = opts.cid ? db.doc(`churches/${opts.cid}`) : db.collection('churches').doc();
  const cid = churchRef.id;
  const profile = await db.doc(`users/${c.uid}`).get();
  const memberName = personName(opts.admin?.name) || personName(profile.get('name')) || personName(c.name);
  const services = opts.services ?? { services: DEFAULT_SERVICES, ids: DEFAULT_SERVICES.map((s) => s.id) };

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
      ...opts.extra,
    });
    tx.create(churchRef.collection('members').doc(c.uid), {
      uid: c.uid,
      name: memberName,
      email: c.email ?? '',
      role: 'admin',
      groups: opts.admin?.groups ?? [],
      zones: opts.admin?.zones ?? [],
      zoneTypes: opts.admin?.zoneTypes ?? [],
      joinedAt: serverTime(),
    });
    tx.create(churchRef.collection('settings').doc('services'), { ...services, updatedAt: serverTime() });
  });
  return cid;
}

/** Marks the church deleted. Restorable for [RESTORE_DAYS] days. */
export async function deleteChurch(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid } = await churchAccess(deps, caller, data, 'admin');
  await deps.db.runTransaction(async (tx) => {
    const ref = deps.db.doc(`churches/${cid}`);
    // Only an open church can be deleted, checked again here: deleting and
    // restoring a church the operator just suspended would reopen it.
    if (!isChurchOpen(await tx.get(ref))) churchClosed();
    tx.update(ref, { status: 'deleted', deletedAt: Timestamp.fromDate(deps.now()) });
  });
  return {};
}

/**
 * Reopens a church its admin deleted, within [RESTORE_DAYS] days. An open
 * church stays as it is; a suspended one, or one deleted too long ago, is
 * closed for good as far as its admin goes.
 */
export async function restoreChurch(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid } = await churchAccess(deps, caller, data, 'admin', { closed: 'allow' });
  await deps.db.runTransaction(async (tx) => {
    const ref = deps.db.doc(`churches/${cid}`);
    const snap = await tx.get(ref);
    if (isChurchOpen(snap)) return;
    if (snap.get('status') !== 'deleted') churchClosed();
    const deletedAt = snap.get('deletedAt') as Timestamp | null;
    if (deletedAt && deps.now().getTime() - deletedAt.toMillis() > RESTORE_DAYS * DAY_MS) churchClosed();
    tx.update(ref, { status: 'active', deletedAt: null });
  });
  return {};
}

export type PurgeDeps = CalDeps & { bucket?: Pick<ReturnType<Storage['bucket']>, 'deleteFiles'> };

/**
 * Forgets everything kept about church [cid] outside its churches/{cid}
 * tree. Each store's own module says how; add a step here with any new
 * store that keeps something per church. The steps run side by side; it
 * throws, after all have run, when any failed.
 */
export function forgetChurch(deps: PurgeDeps, cid: string) {
  return runEach(`purge ${cid}`, {
    calendar: () => forgetCalendar(deps, cid),
    webhook: () => forgetWebhook(deps, cid),
    churchLink: () => forgetLinkSource(deps, cid),
    invites: () => forgetInvites(deps, cid),
    // Reads the pending members, so before the tree goes.
    pendingClaims: () => forgetPendingClaims(deps, cid),
    // The logo and the icons made from it.
    logo: async () => deps.bucket?.deleteFiles({ prefix: `churches/${cid}/` }),
  });
}

/**
 * Removes every church deleted more than [RESTORE_DAYS] days ago: what
 * other stores keep about it ([forgetChurch]), then the churches/{cid}
 * tree and its name reservation. A church whose stores could not all be
 * forgotten is left for the next run: the church doc is what finds them.
 */
export async function purgeDeletedChurches(deps: PurgeDeps) {
  const cutoff = Timestamp.fromMillis(deps.now().getTime() - RESTORE_DAYS * DAY_MS);
  const expired = await deps.db
    .collection('churches')
    .where('status', '==', 'deleted')
    .where('deletedAt', '<', cutoff)
    .get();
  const purged: string[] = [];
  for (const doc of expired.docs) {
    try {
      await forgetChurch(deps, doc.id);
    } catch {
      continue;
    }
    await deps.db.recursiveDelete(doc.ref);
    const key = doc.get('nameKey') as string | undefined;
    if (key) await deps.db.doc(`churchNames/${key}`).delete();
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
  const cid = churchId((data as { churchId?: unknown })?.churchId);
  const snap = await deps.db.doc(`churches/${cid}`).get();
  if (!isChurchOpen(snap)) fail('not-found', 'notFound');
  const version = snap.get('logoVersion') as string | undefined;
  return {
    churchId: cid,
    name: snap.get('name') as string,
    logoPath: version ? publicLogoPath(cid, version) : null,
  };
}
