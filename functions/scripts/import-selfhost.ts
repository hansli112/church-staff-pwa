// Moves a self-host church-staff-pwa deployment into one hosted church.
//
//   # 1. Look first: reads the source, writes nothing, prints counts.
//   npx tsx scripts/import-selfhost.ts --source church-staff-pwa --church-id grace \
//     --church-name 恩典堂 --dry-run
//   # 2. Into dev (or the emulators: set FIRESTORE_EMULATOR_HOST), then compare.
//   npx tsx scripts/import-selfhost.ts --source church-staff-pwa --target martha-app-dev \
//     --church-id grace --church-name 恩典堂 --really
//   # 3. Accounts, keeping passwords (the script prints these commands with
//   #    the source project's hash parameters filled in):
//   firebase auth:export users.json --project church-staff-pwa
//   firebase auth:import users.json --project martha-app-dev --hash-algo=SCRYPT ...
//
// Credentials: Application Default Credentials (gcloud auth
// application-default login) for an account that can read the source and
// write the target. Nothing is read from .local/.
//
// Re-running writes the same document IDs, so it never duplicates.
import { initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore, type QuerySnapshot } from 'firebase-admin/firestore';

import { buildImport } from '../src/importer.js';
import { nameKey } from '../src/text.js';

const args = process.argv.slice(2);
const flag = (name: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};
const source = flag('source');
const churchId = flag('church-id');
const churchName = flag('church-name');
const dryRun = args.includes('--dry-run');
const emulated = !!process.env.FIRESTORE_EMULATOR_HOST;
const target = flag('target') ?? (emulated ? 'demo-martha' : undefined);
if (!source || !churchId || !churchName) throw new Error('Need --source, --church-id and --church-name');
if (!/^[A-Za-z0-9]{1,64}$/.test(churchId)) throw new Error('--church-id: letters and digits only');
if (!dryRun && !target) throw new Error('Need --target (or the emulators) unless --dry-run');
if (!dryRun && !emulated && !args.includes('--really')) throw new Error('Writing to a real project needs --really');

// The source must never go through the emulator variables.
const savedHost = process.env.FIRESTORE_EMULATOR_HOST;
delete process.env.FIRESTORE_EMULATOR_HOST;
const sourceApp: App = initializeApp({ projectId: source }, 'source');
const src = getFirestore(sourceApp);

async function readAll() {
  const [users, settings, rosters, orders] = await Promise.all([
    src.collection('users').get(),
    src.collection('settings').get(),
    src.collection('rosters').get(),
    src.collection('staff_orders').get(),
  ]);
  return { users, settings, rosters, orders };
}

async function main() {
  const data = await readAll();
  const docs = (q: QuerySnapshot) => q.docs.map((d) => ({ id: d.id, data: d.data() }));
  const { members, services, rosters, staffOrders, report } = buildImport(
    { users: docs(data.users), settings: docs(data.settings), rosters: docs(data.rosters), staffOrders: docs(data.orders) },
    Timestamp.now(),
  );

  console.log(`Source ${source}:`);
  console.log(`  users → members      ${report.members} (admins: ${report.admins})`);
  console.log(`  services             ${report.services.length} (${report.services.join(', ')})`);
  console.log(`  rosters              ${report.rosters}${report.skippedRosters.length ? `, skipped ${report.skippedRosters.length}: ${report.skippedRosters.join(', ')}` : ''}`);
  console.log(`  staff orders         ${report.staffOrders}`);
  console.log(`  not imported         settings/${report.droppedSettings.join(', settings/') || '—'}; small groups on ${report.smallGroupPeople} people`);
  if (report.unnamedMembers) console.log(`  ⚠ ${report.unnamedMembers} users have no name`);

  if (dryRun) return;
  if (savedHost) process.env.FIRESTORE_EMULATOR_HOST = savedHost;
  const db: Firestore = getFirestore(initializeApp({ projectId: target }, 'target'));
  const root = db.doc(`churches/${churchId}`);
  const key = nameKey(churchName!);
  const reserved = await db.doc(`churchNames/${key}`).get();
  if (reserved.exists && reserved.get('cid') !== churchId) throw new Error(`Name ${churchName} is taken by ${reserved.get('cid')}`);

  const w = db.bulkWriter();
  void w.set(db.doc(`churchNames/${key}`), { cid: churchId, createdAt: Timestamp.now() });
  void w.set(root, {
    name: churchName,
    nameKey: key,
    status: 'active',
    createdBy: members.find((m) => m.role === 'admin')?.uid ?? null,
    createdAt: Timestamp.now(),
    deletedAt: null,
    importedFrom: source,
  });
  void w.set(root.collection('settings').doc('services'), { ...services, updatedAt: Timestamp.now() });
  for (const m of members) void w.set(root.collection('members').doc(m.uid), m);
  for (const u of data.users.docs) {
    void w.set(db.doc(`users/${u.id}`), {
      name: (u.get('name') as string | undefined)?.trim() ?? '',
      email: (u.get('email') as string | undefined) ?? '',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    }, { merge: true });
  }
  for (const r of rosters) void w.set(root.collection('rosters').doc(r.id), { ...r.data, updatedAt: Timestamp.now() });
  for (const o of staffOrders) void w.set(root.collection('staff_orders').doc(o.id), { roles: o.roles });
  await w.close();
  console.log(`Wrote churches/${churchId} in ${target}.`);
  await printAuthCommands();
}

/** The auth:import line with the source project's password hash parameters. */
async function printAuthCommands() {
  try {
    const { GoogleAuth } = await import('google-auth-library');
    const client = await new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] }).getClient();
    const res = await client.request<{ signIn?: { hashConfig?: Record<string, unknown> } }>({
      url: `https://identitytoolkit.googleapis.com/admin/v2/projects/${source}/config`,
      headers: { 'x-goog-user-project': source! },
    });
    const h = res.data.signIn?.hashConfig ?? {};
    // The signer key is a secret: it goes into a file under .local/ (git-
    // ignored), not into the terminal or a log.
    const { mkdirSync, writeFileSync } = await import('node:fs');
    mkdirSync('../.local', { recursive: true });
    const file = '../.local/auth-import.sh';
    writeFileSync(
      file,
      [
        '#!/bin/sh',
        'set -e',
        `npx firebase auth:export users.json --format=json --project ${source}`,
        `npx firebase auth:import users.json --project ${target} --hash-algo=SCRYPT` +
          ` --hash-key='${h.signerKey}' --salt-separator='${h.saltSeparator}' --rounds=${h.rounds} --mem-cost=${h.memoryCost}`,
        'rm users.json',
        '',
      ].join('\n'),
      { mode: 0o700 },
    );
    console.log(`\nAccounts: run ${file} to move them with their passwords and uids (it holds the hash key; delete it after).`);
  } catch (e) {
    console.log('\nCould not read the password hash parameters; copy them from the Firebase console (Authentication › Users › ⋮).');
    console.log(String(e));
  }
}

await main();
