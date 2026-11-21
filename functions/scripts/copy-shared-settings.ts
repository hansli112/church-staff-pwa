// One-time fill of settings/shared (src/sharedSettings.ts) for the churches
// there were before onSettingsWritten: from then on it follows by itself.
// Run it after deploying the functions and before the app that reads it.
// Run again, it writes nothing more.
//
//   npx tsx scripts/copy-shared-settings.ts --project marthasit-dev
//
// Prints counts, not names. Credentials: Application Default Credentials,
// as the other scripts.
import { pathToFileURL } from 'node:url';

import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

import { copySharedSettings } from '../src/sharedSettings.js';

async function main(argv: string[]) {
  const i = argv.indexOf('--project');
  const project = i >= 0 ? argv[i + 1] : process.env.FIRESTORE_EMULATOR_HOST ? 'demo-martha' : undefined;
  if (!project) throw new Error('Need --project (or the emulators)');
  const db = getFirestore(initializeApp({ projectId: project }));
  const churches = await db.collection('churches').listDocuments();
  let wrote = 0;
  for (const church of churches) {
    if (await copySharedSettings({ db, now: () => new Date(), fetch }, church.id)) wrote++;
  }
  console.log(`${churches.length} churches, ${wrote} written.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main(process.argv.slice(2));
