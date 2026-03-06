#!/usr/bin/env node
import fs from 'node:fs';
import process from 'node:process';
import admin from 'firebase-admin';

function getArg(name) {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return undefined;
  return process.argv[idx + 1];
}

const dryRun = process.argv.includes('--dry-run');
const force = process.argv.includes('--force');
const serviceAccountPath =
  getArg('--service-account') || process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (!serviceAccountPath) {
  console.error(
    'Missing service account. Use --service-account <path> or set GOOGLE_APPLICATION_CREDENTIALS.',
  );
  process.exit(1);
}

if (!fs.existsSync(serviceAccountPath)) {
  console.error(`Service account file not found: ${serviceAccountPath}`);
  process.exit(1);
}

const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

function getWebTokens(data) {
  const fcm = data?.fcm;
  if (!fcm || typeof fcm !== 'object') return [];
  const tokens = fcm.webTokens;
  if (!Array.isArray(tokens)) return [];
  return [...new Set(tokens.filter((v) => typeof v === 'string').map((v) => v.trim()).filter(Boolean))];
}

async function main() {
  const snap = await db.collection('users').get();
  let scanned = 0;
  let updated = 0;
  let skippedExisting = 0;
  let enabledCount = 0;
  let disabledCount = 0;

  for (const doc of snap.docs) {
    scanned += 1;
    const data = doc.data() || {};
    const prefs = data.notificationPrefs;
    const existing = prefs && typeof prefs === 'object' ? prefs.weeklyRosterReminder : undefined;
    if (typeof existing === 'boolean' && !force) {
      skippedExisting += 1;
      continue;
    }

    const tokens = getWebTokens(data);
    const enabled = tokens.length > 0;
    if (enabled) {
      enabledCount += 1;
    } else {
      disabledCount += 1;
    }

    if (!dryRun) {
      await doc.ref.set(
        {
          notificationPrefs: {
            weeklyRosterReminder: enabled,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true },
      );
    }
    updated += 1;
  }

  console.log(`Scanned users: ${scanned}`);
  console.log(`Updated users: ${updated}${dryRun ? ' (dry-run)' : ''}`);
  console.log(`Skipped existing prefs: ${skippedExisting}${force ? ' (force mode on)' : ''}`);
  console.log(`Set weeklyRosterReminder=true: ${enabledCount}`);
  console.log(`Set weeklyRosterReminder=false: ${disabledCount}`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await admin.app().delete().catch(() => {});
  });
