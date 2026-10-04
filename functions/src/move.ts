import { createHash } from 'node:crypto';

import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import type { Storage } from 'firebase-admin/storage';

import { openChurch } from './church.js';
import { fail, requireCaller, text, type Caller, type Deps } from './common.js';
import { buildImport, type SelfHostSnapshot, type SourceDoc } from './importer.js';
import { nameKey } from './text.js';

/**
 * 自助搬家: a self-host admin runs one command in their own Cloud Shell,
 * which writes a 搬家檔 (docs/move-format.md), and uploads it here while
 * creating a church. Nobody at the platform touches it.
 *
 * - The file goes to Storage at moves/{uid}/… first; only the uploader can
 *   read or write it (storage.rules), up to 20MB.
 * - movePreview reads it and says what would be moved; moveCommit creates
 *   the church with the uploader as admin and writes everything.
 * - The uploader may say which old member they are ("這位是我") and takes
 *   over that member's zones and groups. Everyone else becomes a pending
 *   member (churches/{cid}/pendingMembers/{old uid}) that its owner claims
 *   by signing in with the same email; rosters keep pointing at the old uid,
 *   which is now the pending member's ID. pendingIndex/{sha256(email)}
 *   (backend only) finds them without storing the email in the key.
 * - No password hashes: letting anyone upload hashes would let them make an
 *   account for someone else's email. Any found in the file are ignored.
 */
export const MOVE_FORMAT = 'church-staff-pwa-move';
export const MOVE_LIMITS = { members: 2000, rosters: 20000, bytes: 20 * 1024 * 1024 };

export type MoveDeps = Deps & { bucket: Pick<ReturnType<Storage['bucket']>, 'file'> };

/** Keys never read from a move file, wherever they appear. */
const SECRET_KEYS = new Set(['passwordHash', 'passwordSalt', 'salt', 'hash', 'password']);

/** The email as the pending index keys it. */
export const emailHash = (email: string) => createHash('sha256').update(email.trim().toLowerCase()).digest('hex');

/** Timestamps written as `{"__time__": ISO}` or `{_seconds, _nanoseconds}` become Date-like. */
function revive(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(revive);
  if (!value || typeof value !== 'object') return value;
  const o = value as Record<string, unknown>;
  const time =
    typeof o.__time__ === 'string'
      ? Date.parse(o.__time__)
      : typeof o._seconds === 'number'
        ? o._seconds * 1000
        : typeof o.seconds === 'number' && Object.keys(o).length <= 2
          ? o.seconds * 1000
          : null;
  if (time !== null && !Number.isNaN(time)) {
    const d = new Date(time);
    return { toDate: () => d };
  }
  return Object.fromEntries(Object.entries(o).filter(([k]) => !SECRET_KEYS.has(k)).map(([k, v]) => [k, revive(v)]));
}

function docs(raw: unknown): SourceDoc[] {
  if (!Array.isArray(raw)) fail('invalid-argument', 'moveInvalid');
  return raw
    .filter((d): d is { id: string; data: unknown } => !!d && typeof d === 'object' && typeof (d as { id?: unknown }).id === 'string')
    .map((d) => ({ id: d.id, data: (revive(d.data) ?? {}) as Record<string, unknown> }));
}

function pathOf(c: Caller, data: unknown): string {
  const path = (data as { path?: unknown })?.path;
  const mine = new RegExp(`^moves/${c.uid.replace(/[^A-Za-z0-9]/g, '')}/[A-Za-z0-9_-]{1,64}\\.json$`);
  if (typeof path !== 'string' || !mine.test(path)) fail('permission-denied', 'permissionDenied');
  return path;
}

/** Reads and checks a move file: the format, then the limits. */
export async function readMoveFile(deps: MoveDeps, path: string) {
  let bytes: Buffer;
  try {
    [bytes] = await deps.bucket.file(path).download();
  } catch {
    fail('not-found', 'moveInvalid');
  }
  if (bytes.length > MOVE_LIMITS.bytes) fail('failed-precondition', 'moveTooLarge', { bytes: bytes.length });
  let raw: Record<string, unknown>;
  try {
    raw = JSON.parse(bytes.toString('utf8'));
  } catch {
    fail('invalid-argument', 'moveInvalid');
  }
  if (raw?.format !== MOVE_FORMAT || raw.version !== 1) fail('invalid-argument', 'moveInvalid');
  // Only these four are read; an `accounts` list with hashes, or anything
  // else, is left behind.
  const snapshot: SelfHostSnapshot = {
    users: docs(raw.users),
    settings: docs(raw.settings ?? []),
    rosters: docs(raw.rosters ?? []),
    staffOrders: docs(raw.staffOrders ?? []),
  };
  const counts = { members: snapshot.users.length, rosters: snapshot.rosters.length };
  if (counts.members > MOVE_LIMITS.members || counts.rosters > MOVE_LIMITS.rosters) {
    fail('failed-precondition', 'moveTooLarge', { ...counts, limits: { members: MOVE_LIMITS.members, rosters: MOVE_LIMITS.rosters } });
  }
  return { snapshot, project: typeof raw.project === 'string' ? raw.project.slice(0, 100) : null };
}

/** What a move would bring, for the uploader to check before committing. */
export async function movePreview(deps: MoveDeps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const { snapshot } = await readMoveFile(deps, pathOf(c, data));
  const { members, services, report } = buildImport(snapshot, null);
  return {
    members: report.members,
    rosters: report.rosters,
    skippedRosters: report.skippedRosters.length,
    services: services.services.map((s) => ({ id: s.id, name: s.name })),
    people: members.map((m) => ({ id: m.uid, name: m.name, email: m.email })),
  };
}

/** Creates the church from the move file, with the caller as its admin. */
export async function moveCommit(deps: MoveDeps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  if (!c.emailVerified) fail('failed-precondition', 'unverifiedEmail');
  const path = pathOf(c, data);
  const input = data as { churchName?: unknown; me?: unknown };
  const churchName = text(input.churchName, 60);
  const { snapshot, project } = await readMoveFile(deps, path);
  const now = Timestamp.fromDate(deps.now());
  const built = buildImport(snapshot, now);
  const me = typeof input.me === 'string' ? built.members.find((m) => m.uid === input.me) : undefined;
  if (input.me != null && !me) fail('invalid-argument', 'unknown');

  // Everything under the church is written first and the church doc last,
  // in openChurch's transaction with the name: until then nothing reads
  // these documents, and a failed move leaves no half-made church (and
  // keeps the name free for a retry).
  const { db } = deps;
  // The name is checked again in openChurch's transaction; this only spares
  // writing everything for a name that is already taken.
  if ((await db.doc(`churchNames/${nameKey(churchName)}`).get()).exists) fail('already-exists', 'duplicateName');
  const root = db.collection('churches').doc();
  const cid = root.id;
  // Which roster days name each person, so claiming rewrites only those.
  const rosterIds = new Map<string, string[]>();
  for (const r of built.rosters) {
    for (const uid of new Set(r.data.duties.flatMap((d) => Object.values(d.uids)))) {
      rosterIds.set(uid, [...(rosterIds.get(uid) ?? []), r.id]);
    }
  }
  const w = db.bulkWriter();
  const failures: unknown[] = [];
  const write = (p: Promise<unknown>) => void p.catch((e) => failures.push(e));
  for (const m of built.members) {
    if (m === me) continue;
    const hash = m.email ? emailHash(m.email) : null;
    write(w.set(root.collection('pendingMembers').doc(m.uid), {
      name: m.name,
      email: m.email,
      emailHash: hash,
      role: m.role,
      groups: m.groups,
      zones: m.zones,
      zoneTypes: m.zoneTypes,
      rosterIds: rosterIds.get(m.uid) ?? [],
      importedAt: now,
    }));
    if (hash) write(w.set(db.doc(`pendingIndex/${hash}`), { churches: { [cid]: m.uid } }, { merge: true }));
  }
  for (const r of built.rosters) {
    const duties = me
      ? r.data.duties.map((d) => ({
          ...d,
          uids: Object.fromEntries(Object.entries(d.uids).map(([n, u]) => [n, u === me.uid ? c.uid : u])),
        }))
      : r.data.duties;
    write(w.set(root.collection('rosters').doc(r.id), { ...r.data, duties, via: 'import', updatedAt: now }));
  }
  for (const o of built.staffOrders) write(w.set(root.collection('staff_orders').doc(o.id), { roles: o.roles }));
  await w.close();
  if (failures.length) {
    console.error(`moveCommit: ${failures.length} writes failed for ${cid}`, failures[0]);
    fail('unavailable', 'unavailable');
  }
  try {
    await openChurch(deps, c, churchName, {
      cid,
      services: built.services,
      admin: me ? { name: me.name, groups: me.groups, zones: me.zones, zoneTypes: me.zoneTypes } : undefined,
      extra: { movedFrom: project, movedBy: c.uid },
    });
  } catch (e) {
    // Taken in the meantime: drop what was written under the unused ID.
    await db.recursiveDelete(root);
    for (const m of built.members) {
      if (m.email) await db.doc(`pendingIndex/${emailHash(m.email)}`).set({ churches: { [cid]: FieldValue.delete() } }, { merge: true });
    }
    throw e;
  }
  await deps.bucket.file(path).delete({ ignoreNotFound: true });
  return { churchId: cid };
}
