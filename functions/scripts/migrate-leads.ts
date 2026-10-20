// One-time move to 身分 (#82). Members in the old permission groups and
// without any 身分 yet get one: calendar-editors is folded into 行政;
// roster-editors alone, which edited only the rosters of their 牧區, makes
// them 負責人 of the services they are in (the group itself now means 行政,
// every service's). Admins need nothing: role admin is 管理員.
//
//   # Look first (writes nothing):
//   npx tsx scripts/migrate-leads.ts --project marthasit-dev
//   # Then write:
//   npx tsx scripts/migrate-leads.ts --project marthasit-dev --apply
//
// Every church, or one with --church. Prints counts and member IDs, not
// names. Credentials: Application Default Credentials, as the other scripts.
import { pathToFileURL } from 'node:url';

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

import { claimedGroups } from '../src/claim.js';

/** The members to change, and how, in [churches] (all when empty). */
export async function planLeads(db: Firestore, churches: string[] = []) {
  const ids = churches.length > 0 ? churches : (await db.collection('churches').listDocuments()).map((d) => d.id);
  const changes: { path: string; update: Record<string, unknown> }[] = [];
  for (const cid of ids) {
    const members = await db.collection(`churches/${cid}/members`).get();
    for (const m of members.docs) {
      const groups = m.get('groups');
      if (m.get('role') === 'admin' || m.get('identities') !== undefined) continue;
      if (!Array.isArray(groups) || groups.length === 0) continue;
      changes.push({ path: m.ref.path, update: claimedGroups(groups, m.get('zoneTypes')) });
    }
  }
  return changes;
}

export async function applyLeads(db: Firestore, changes: { path: string; update: Record<string, unknown> }[]) {
  for (const c of changes) await db.doc(c.path).update(c.update);
}

async function main(argv: string[]) {
  const flag = (name: string) => {
    const i = argv.indexOf(`--${name}`);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  const emulated = !!process.env.FIRESTORE_EMULATOR_HOST;
  const project = flag('project') ?? (emulated ? 'demo-martha' : undefined);
  if (!project) throw new Error('Need --project (or the emulators)');
  const church = flag('church');
  const db = getFirestore(initializeApp({ projectId: project }));
  const changes = await planLeads(db, church ? [church] : []);
  console.log(JSON.stringify({ members: changes.map((c) => c.path), leadTypes: changes.map((c) => c.update.leadTypes) }, null, 2));
  if (!argv.includes('--apply')) {
    console.log('Preview only: nothing written. Add --apply to write.');
    return;
  }
  await applyLeads(db, changes);
  console.log(`Updated ${changes.length} members.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main(process.argv.slice(2));
