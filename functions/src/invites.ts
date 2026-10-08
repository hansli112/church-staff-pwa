import type { Timestamp } from 'firebase-admin/firestore';

import { isChurchOpen } from './access.js';
import { fail, requireCaller, serverTime, type Caller, type Deps } from './common.js';
import { personName } from './limits.js';

/**
 * Invites live at invites/{code}. Admins create and revoke them from the app
 * (firestore.rules); joining goes through [redeemInvite] because only the
 * backend may create a member doc.
 */
async function usableInvite(deps: Deps, data: unknown) {
  const raw = (data as { code?: unknown })?.code;
  if (typeof raw !== 'string') fail('invalid-argument', 'inviteInvalid');
  const code = raw.trim().toUpperCase();
  if (!/^[A-Z0-9]{6,16}$/.test(code)) fail('not-found', 'inviteInvalid');
  const snap = await deps.db.doc(`invites/${code}`).get();
  if (!snap.exists || snap.get('revoked') === true) fail('not-found', 'inviteInvalid');
  const expiresAt = snap.get('expiresAt') as Timestamp | undefined;
  if (!expiresAt || expiresAt.toMillis() <= deps.now().getTime()) {
    fail('failed-precondition', 'inviteExpired');
  }
  const cid = snap.get('cid') as string;
  const church = await deps.db.doc(`churches/${cid}`).get();
  if (!isChurchOpen(church)) fail('failed-precondition', 'inviteInvalid');
  return { code, cid, churchName: church.get('name') as string, expiresAt, zoneTypes: snap.get('zoneTypes') as unknown };
}

/**
 * The 牧區 an invite puts its members in: the services it names that the
 * church still has, each once, in the invite's order.
 */
async function inviteZoneTypes(deps: Deps, cid: string, raw: unknown): Promise<string[]> {
  if (!Array.isArray(raw) || raw.length === 0) return [];
  const settings = await deps.db.doc(`churches/${cid}/settings/services`).get();
  const services = settings.get('services');
  const have = new Set(
    Array.isArray(services)
      ? services.map((s: { id?: unknown }) => s?.id).filter((id): id is string => typeof id === 'string')
      : [],
  );
  return [...new Set(raw.filter((t): t is string => typeof t === 'string' && have.has(t)))];
}

/**
 * The church an invite is for. Open before sign-in, so the login page can say
 * who is inviting: the code is the secret, and it is enough to join anyway.
 * Signed out, only the name.
 */
export async function previewInvite(deps: Deps, caller: Caller | null, data: unknown) {
  const invite = await usableInvite(deps, data);
  if (!caller) return { churchName: invite.churchName };
  return {
    churchId: invite.cid,
    churchName: invite.churchName,
    expiresAt: invite.expiresAt.toMillis(),
  };
}

/**
 * Joins the caller to the invite's church, in the 牧區 the invite names.
 * Joining twice is a no-op.
 */
export async function redeemInvite(deps: Deps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const invite = await usableInvite(deps, data);
  const { db } = deps;
  const memberRef = db.doc(`churches/${invite.cid}/members/${c.uid}`);
  const profile = await db.doc(`users/${c.uid}`).get();
  const zoneTypes = await inviteZoneTypes(deps, invite.cid, invite.zoneTypes);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(memberRef);
    if (existing.exists) return;
    tx.create(memberRef, {
      uid: c.uid,
      name: personName(profile.get('name')) || personName(c.name),
      email: c.email ?? '',
      role: 'staff',
      groups: [],
      zones: zoneTypes.map((serviceType) => ({ serviceType, duties: [] })),
      zoneTypes,
      joinedAt: serverTime(),
      invitedWith: invite.code,
    });
  });
  return { churchId: invite.cid };
}

/** Deletes every invite to church [cid]: the church is purged. */
export async function forgetInvites(deps: Deps, cid: string) {
  const invites = await deps.db.collection('invites').where('cid', '==', cid).get();
  await Promise.all(invites.docs.map((d) => d.ref.delete()));
}
