// One-time roster identity repair. Runtime notifications never resolve names.
// The CLI is read-only unless --apply is explicitly supplied; all reads/writes
// are scoped to one church. It prints counts and roster IDs, not identities.
//
//   # Look first (writes nothing):
//   npx tsx scripts/backfill-roster-uids.ts --project marthasit-dev --church grace
//   # Names a person confirmed by hand, for duties the automatic pass leaves
//   # alone (an explicit empty map, a shared or shortened name):
//   npx tsx scripts/backfill-roster-uids.ts --project marthasit-dev --church grace \
//     --confirm confirmed.json
//   # Then write, on a real project only with --apply:
//   npx tsx scripts/backfill-roster-uids.ts --project marthasit-dev --church grace --apply
//
// confirmed.json: {"format":"martha-roster-uid-backfill","version":1,
//   "bindings":[{"rosterId":"…","dutyIndex":0,"name":"…","uid":"…"}]}
// Credentials: Application Default Credentials, as the other scripts.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, type Firestore, type Timestamp } from 'firebase-admin/firestore';

import { isChurchId } from '../src/access.js';
import { exactUidIndex } from '../src/importer.js';

interface Binding {
  dutyIndex: number;
  name: string;
  uid: string;
  confirmed: boolean;
}

interface PlannedRoster {
  id: string;
  version: Timestamp;
  normalizations: number[];
  bindings: Binding[];
}

export interface BackfillSummary {
  churchId: string;
  scannedRosters: number;
  scannedDuties: number;
  normalizedUidMaps: number;
  automaticBindings: number;
  confirmedBindings: number;
  preservedUnbound: number;
  unknownNames: number;
  ambiguousNames: number;
  invalidDuties: number;
  invalidUidMaps: number;
  rostersToChange: number;
  rosterIds: string[];
}

export interface UidBackfillPlan {
  churchId: string;
  rosters: PlannedRoster[];
  summary: BackfillSummary;
}

class BackfillError extends Error {}
const refuse = (reason: string): never => { throw new BackfillError(reason); };
const record = (value: unknown): value is Record<string, unknown> => !!value && typeof value === 'object' && !Array.isArray(value);
const validUid = (value: unknown): value is string => typeof value === 'string' && !!value && !value.includes('/');

/** Bindings a person confirmed by hand: the only way to bind an explicit empty map. */
export interface UidConfirmations {
  format: 'martha-roster-uid-backfill';
  version: 1;
  bindings: { rosterId: string; dutyIndex: number; name: string; uid: string }[];
}

function confirmedBindings(raw: UidConfirmations | undefined) {
  const byRoster = new Map<string, { dutyIndex: number; name: string; uid: string }[]>();
  if (raw === undefined) return byRoster;
  if (!record(raw) || raw.format !== 'martha-roster-uid-backfill' || raw.version !== 1 || !Array.isArray(raw.bindings)) {
    refuse('invalidConfirmations');
  }
  for (const item of raw.bindings as unknown[]) {
    const b = record(item) ? item : refuse('invalidConfirmations');
    const { rosterId, dutyIndex, name, uid } = b;
    if (typeof rosterId !== 'string' || !rosterId || rosterId.includes('/') ||
        typeof dutyIndex !== 'number' || !Number.isInteger(dutyIndex) || dutyIndex < 0 ||
        typeof name !== 'string' || !name || !validUid(uid)) {
      return refuse('invalidConfirmations');
    }
    const list = byRoster.get(rosterId) ?? [];
    list.push({ dutyIndex, name, uid });
    byRoster.set(rosterId, list);
  }
  return byRoster;
}

/**
 * Read-only preview. An explicit empty/partial UID map is never inferred
 * from names; only [confirmations] bind there, and only to a current member
 * named on that duty whose name has no binding yet.
 */
export async function createUidBackfillPlan(db: Firestore, churchId: string, confirmations?: UidConfirmations): Promise<UidBackfillPlan> {
  if (!isChurchId(churchId)) refuse('invalidChurchId');
  const confirmed = confirmedBindings(confirmations);
  const root = db.doc(`churches/${churchId}`);
  const [church, members, pending, rosters] = await Promise.all([
    root.get(), root.collection('members').select('name').get(), root.collection('pendingMembers').select('name').get(), root.collection('rosters').get(),
  ]);
  if (!church.exists) refuse('churchNotFound');
  const memberNames = new Map(members.docs.map((m) => [m.id, m.get('name') as unknown]));
  const index = exactUidIndex([...members.docs, ...pending.docs].map((m) => ({ uid: m.id, name: m.get('name') as unknown })));
  const summary: BackfillSummary = {
    churchId, scannedRosters: rosters.size, scannedDuties: 0, normalizedUidMaps: 0,
    automaticBindings: 0, confirmedBindings: 0, preservedUnbound: 0,
    unknownNames: 0, ambiguousNames: 0, invalidDuties: 0, invalidUidMaps: 0,
    rostersToChange: 0, rosterIds: [],
  };
  const planned: PlannedRoster[] = [];
  const rosterIds = new Set(rosters.docs.map((r) => r.id));
  for (const id of confirmed.keys()) if (!rosterIds.has(id)) refuse('confirmedRosterMissing');
  for (const roster of rosters.docs) {
    const duties = roster.get('duties') as unknown;
    if (!Array.isArray(duties)) { summary.invalidDuties++; continue; }
    const normalizations: number[] = [];
    const bindings: Binding[] = [];
    const confirmedHere = confirmed.get(roster.id) ?? [];
    for (const [dutyIndex, duty] of duties.entries()) {
      summary.scannedDuties++;
      if (!record(duty) || typeof duty.role !== 'string' || !Array.isArray(duty.people) || duty.people.some((p) => typeof p !== 'string')) {
        if (confirmedHere.some((b) => b.dutyIndex === dutyIndex)) refuse('confirmedDutyInvalid');
        summary.invalidDuties++;
        continue;
      }
      const people = [...new Set(duty.people as string[])];
      const hasMap = Object.hasOwn(duty, 'uids');
      if (hasMap && !record(duty.uids)) {
        if (confirmedHere.some((b) => b.dutyIndex === dutyIndex)) refuse('confirmedDutyInvalid');
        summary.invalidUidMaps++;
        continue;
      }
      const map = (hasMap ? duty.uids : {}) as Record<string, unknown>;
      const confirmedNames = new Set<string>();
      for (const b of confirmedHere.filter((c) => c.dutyIndex === dutyIndex)) {
        // A confirmation adds a binding; it never replaces one or names
        // someone who is not on this duty or not a current member.
        if (!people.includes(b.name) || validUid(map[b.name]) || !memberNames.has(b.uid) || confirmedNames.has(b.name)) {
          refuse('confirmationRejected');
        }
        confirmedNames.add(b.name);
        bindings.push({ dutyIndex, name: b.name, uid: b.uid, confirmed: true });
        summary.confirmedBindings++;
      }
      if (hasMap) {
        summary.preservedUnbound += people.filter((name) => !validUid(map[name]) && !confirmedNames.has(name)).length;
        continue;
      }
      normalizations.push(dutyIndex);
      summary.normalizedUidMaps++;
      for (const name of people) {
        if (confirmedNames.has(name)) continue;
        const uid = index.unique.get(name);
        if (uid && memberNames.get(uid) === name) {
          bindings.push({ dutyIndex, name, uid, confirmed: false });
          summary.automaticBindings++;
        } else if (index.ambiguous.has(name)) summary.ambiguousNames++;
        else summary.unknownNames++;
      }
    }
    if (normalizations.length || bindings.length) planned.push({ id: roster.id, version: roster.updateTime!, normalizations, bindings });
  }
  summary.rosterIds = planned.map((p) => p.id).sort();
  summary.rostersToChange = planned.length;
  return { churchId, rosters: planned, summary };
}

/** Apply only the planned UID-map changes; never change names, duties, dates or other roster fields. */
export async function applyUidBackfillPlan(db: Firestore, plan: UidBackfillPlan) {
  if (!isChurchId(plan.churchId)) refuse('invalidChurchId');
  let appliedRosters = 0;
  const conflictRosterIds: string[] = [];
  for (const roster of plan.rosters) {
    if (!roster.id || roster.id.includes('/')) refuse('invalidRosterId');
    const ref = db.doc(`churches/${plan.churchId}/rosters/${roster.id}`);
    const applied = await db.runTransaction(async (tx) => {
      const root = db.doc(`churches/${plan.churchId}`);
      const [current, church, members, pending] = await Promise.all([
        tx.get(ref), tx.get(root), tx.get(root.collection('members').select('name')), tx.get(root.collection('pendingMembers').select('name')),
      ]);
      if (!church.exists || !current.updateTime?.isEqual(roster.version)) return false;
      const memberNames = new Map(members.docs.map((m) => [m.id, m.get('name') as unknown]));
      const index = exactUidIndex([...members.docs, ...pending.docs].map((m) => ({ uid: m.id, name: m.get('name') as unknown })));
      for (const binding of roster.bindings) {
        if (!memberNames.has(binding.uid) || (!binding.confirmed && (memberNames.get(binding.uid) !== binding.name || index.unique.get(binding.name) !== binding.uid))) return false;
      }
      const duties = current.get('duties') as Record<string, unknown>[];
      const next = duties.map((d, index) => roster.normalizations.includes(index) ? { ...d, uids: {} } : { ...d });
      for (const binding of roster.bindings) {
        const duty = next[binding.dutyIndex];
        duty.uids = { ...(duty.uids as Record<string, unknown> | undefined), [binding.name]: binding.uid };
      }
      tx.update(ref, { duties: next, via: 'import', updatedAt: FieldValue.serverTimestamp() });
      return true;
    });
    if (applied) appliedRosters++;
    else conflictRosterIds.push(roster.id);
  }
  return { appliedRosters, conflicts: conflictRosterIds.length, conflictRosterIds };
}

async function main(argv: string[]) {
  const flag = (name: string) => {
    const i = argv.indexOf(`--${name}`);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  const emulated = !!process.env.FIRESTORE_EMULATOR_HOST;
  const project = flag('project') ?? (emulated ? 'demo-martha' : undefined);
  const churchId = flag('church');
  if (!project || !churchId) throw new Error('Need --project (or the emulators) and --church');
  const confirmPath = flag('confirm');
  const confirmations = confirmPath ? (JSON.parse(readFileSync(confirmPath, 'utf8')) as UidConfirmations) : undefined;
  const db = getFirestore(initializeApp({ projectId: project }));
  const plan = await createUidBackfillPlan(db, churchId, confirmations);
  console.log(JSON.stringify(plan.summary, null, 2));
  if (!argv.includes('--apply')) {
    console.log('Preview only: nothing written. Add --apply to write.');
    return;
  }
  console.log(JSON.stringify(await applyUidBackfillPlan(db, plan), null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main(process.argv.slice(2));
