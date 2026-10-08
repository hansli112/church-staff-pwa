import type { Timestamp } from 'firebase-admin/firestore';
import type { FunctionsErrorCode } from 'firebase-functions/v2/https';

import { isChurchOpen } from './access.js';
import { fail, requireCaller, serverTime, type Caller, type Deps } from './common.js';
import { personName } from './limits.js';

/**
 * Invites live at invites/{code}. Admins create and revoke them from the app
 * (firestore.rules); joining goes through [redeemInvite] because only the
 * backend may create a member doc.
 */
export type InviteCheck =
  | { ok: true; code: string; cid: string; churchName: string; expiresAt: Timestamp; zoneTypes: unknown }
  | { ok: false; error: FunctionsErrorCode; reason: 'inviteInvalid' | 'inviteExpired' };

/** Whether invite [raw] can be used now, and to join which church; never throws for a bad code. */
export async function checkInvite(deps: Deps, raw: unknown): Promise<InviteCheck> {
  const no = (error: FunctionsErrorCode, reason: 'inviteInvalid' | 'inviteExpired' = 'inviteInvalid') =>
    ({ ok: false, error, reason }) as const;
  if (typeof raw !== 'string') return no('invalid-argument');
  const code = raw.trim().toUpperCase();
  if (!/^[A-Z0-9]{6,16}$/.test(code)) return no('not-found');
  const snap = await deps.db.doc(`invites/${code}`).get();
  if (!snap.exists || snap.get('revoked') === true) return no('not-found');
  const expiresAt = snap.get('expiresAt') as Timestamp | undefined;
  if (!expiresAt || expiresAt.toMillis() <= deps.now().getTime()) return no('failed-precondition', 'inviteExpired');
  const cid = snap.get('cid') as string;
  const church = await deps.db.doc(`churches/${cid}`).get();
  if (!isChurchOpen(church)) return no('failed-precondition');
  return { ok: true, code, cid, churchName: church.get('name') as string, expiresAt, zoneTypes: snap.get('zoneTypes') as unknown };
}

async function usableInvite(deps: Deps, data: unknown) {
  const invite = await checkInvite(deps, (data as { code?: unknown })?.code);
  if (!invite.ok) fail(invite.error, invite.reason);
  return invite;
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
