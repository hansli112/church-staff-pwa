import { churchClosed, churchId } from './access.js';
import { fail, id, requireOperator, serverTime, text, type Caller, type Deps } from './common.js';
import { matchesSearch, nameKey } from './text.js';

/**
 * The platform operator's back office: find a church, rename it (to settle
 * a squatted name), hand it to a new admin, suspend or reopen it. Only
 * callers with the `operator` custom claim get in.
 */
export async function adminSearchChurches(deps: Deps, caller: Caller | null, data: unknown) {
  requireOperator(caller);
  const query = typeof (data as { query?: unknown })?.query === 'string'
    ? ((data as { query: string }).query)
    : '';
  // Scale is tens to hundreds of churches; a scan is fine and keeps the
  // search forgiving (part of a name, any width or case).
  const all = await deps.db.collection('churches').select('name', 'status').get();
  const hits = all.docs
    .filter((d) => d.id === query.trim() || matchesSearch((d.get('name') as string) ?? '', query))
    .slice(0, 50);
  const churches = await Promise.all(
    hits.map(async (d) => {
      const members = d.ref.collection('members');
      const [count, admins] = await Promise.all([
        members.count().get(),
        members.where('role', '==', 'admin').get(),
      ]);
      return {
        id: d.id,
        name: d.get('name'),
        status: d.get('status'),
        memberCount: count.data().count,
        admins: admins.docs.map((a) => ({ uid: a.id, name: a.get('name'), email: a.get('email') })),
      };
    }),
  );
  return { churches };
}

/** Renames a church, still subject to the duplicate-name check. */
export async function adminRenameChurch(deps: Deps, caller: Caller | null, data: unknown) {
  requireOperator(caller);
  const input = data as { churchId?: unknown; name?: unknown };
  const cid = churchId(input?.churchId);
  const name = text(input?.name, 60);
  const key = nameKey(name);
  const { db } = deps;
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`churches/${cid}`);
    const church = await tx.get(ref);
    if (!church.exists) fail('not-found', 'unknown');
    const oldKey = church.get('nameKey') as string | undefined;
    if (oldKey !== key) {
      const reserved = await tx.get(db.doc(`churchNames/${key}`));
      if (reserved.exists && reserved.get('cid') !== cid) fail('already-exists', 'duplicateName');
      tx.set(db.doc(`churchNames/${key}`), { cid, createdAt: serverTime() });
      if (oldKey) tx.delete(db.doc(`churchNames/${oldKey}`));
    }
    tx.update(ref, { name, nameKey: key });
  });
  return {};
}

/** Makes a member of the church its admin (other admins stay admins). */
export async function adminTransferAdmin(deps: Deps, caller: Caller | null, data: unknown) {
  requireOperator(caller);
  const input = data as { churchId?: unknown; uid?: unknown };
  const cid = churchId(input?.churchId);
  const uid = id(input?.uid);
  const ref = deps.db.doc(`churches/${cid}/members/${uid}`);
  const member = await ref.get();
  if (!member.exists) fail('not-found', 'unknown');
  await ref.update({ role: 'admin' });
  return {};
}

export async function adminSetStatus(deps: Deps, caller: Caller | null, data: unknown) {
  requireOperator(caller);
  const input = data as { churchId?: unknown; status?: unknown };
  const cid = churchId(input?.churchId);
  if (input?.status !== 'active' && input?.status !== 'suspended') {
    fail('invalid-argument', 'unknown');
  }
  const ref = deps.db.doc(`churches/${cid}`);
  const church = await ref.get();
  if (!church.exists) fail('failed-precondition', 'unknown');
  // A deleted church is its admin's to restore (or let go), not the operator's.
  if (church.get('status') === 'deleted') churchClosed();
  await ref.update({ status: input.status });
  return {};
}

/** The last [days] daily snapshots, newest first. */
export async function adminStats(deps: Deps, caller: Caller | null, data: unknown) {
  requireOperator(caller);
  const raw = Number((data as { days?: unknown })?.days ?? 30);
  const days = Number.isFinite(raw) ? Math.min(Math.max(Math.trunc(raw), 1), 366) : 30;
  const snap = await deps.db.collection('stats').orderBy('date', 'desc').limit(days).get();
  return { days: snap.docs.map((d) => d.data()) };
}

/** A church's members, so the operator can pick who becomes admin. */
export async function adminChurchMembers(deps: Deps, caller: Caller | null, data: unknown) {
  requireOperator(caller);
  const cid = churchId((data as { churchId?: unknown })?.churchId);
  const snap = await deps.db.collection(`churches/${cid}/members`).orderBy('name').limit(500).get();
  return {
    members: snap.docs.map((d) => ({
      uid: d.id,
      name: d.get('name') ?? '',
      email: d.get('email') ?? '',
      role: d.get('role') ?? 'staff',
    })),
  };
}
