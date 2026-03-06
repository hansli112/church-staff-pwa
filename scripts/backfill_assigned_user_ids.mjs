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

function trimString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function uniqueStrings(values) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const v = trimString(value);
    if (!v || seen.has(v)) continue;
    seen.add(v);
    out.push(v);
  }
  return out;
}

async function loadUserNameIndex() {
  const snap = await db.collection('users').get();
  const byName = new Map();
  const ambiguous = new Set();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const name = trimString(data.name);
    const uid = trimString(doc.id);
    if (!name || !uid) continue;

    if (byName.has(name) && byName.get(name) !== uid) {
      ambiguous.add(name);
      byName.delete(name);
      continue;
    }
    if (!ambiguous.has(name)) {
      byName.set(name, uid);
    }
  }

  return { byName, ambiguous };
}

function normalizeDuty(duty, nameToUid) {
  if (!duty || typeof duty !== 'object') return { duty, changed: false, warnings: [] };

  const people = Array.isArray(duty.people) ? duty.people.map(trimString).filter(Boolean) : [];
  const existingMap = duty.personIdsByName && typeof duty.personIdsByName === 'object'
    ? Object.fromEntries(
        Object.entries(duty.personIdsByName)
          .map(([k, v]) => [trimString(k), trimString(v)])
          .filter(([k, v]) => k && v),
      )
    : {};

  const nextMap = { ...existingMap };
  const warnings = [];

  for (const name of people) {
    if (!name || name === '待定') continue;
    if (nextMap[name]) continue;
    const uid = nameToUid.get(name);
    if (!uid) {
      warnings.push(`Unmatched name: ${name}`);
      continue;
    }
    nextMap[name] = uid;
  }

  for (const key of Object.keys(nextMap)) {
    if (!people.includes(key)) {
      delete nextMap[key];
    }
  }

  const assignedUserIds = uniqueStrings(
    people
      .filter((name) => name !== '待定')
      .map((name) => nextMap[name])
      .filter(Boolean),
  );

  const prevAssigned = Array.isArray(duty.assignedUserIds)
    ? uniqueStrings(duty.assignedUserIds)
    : [];

  const mapChanged = JSON.stringify(existingMap) !== JSON.stringify(nextMap);
  const assignedChanged = JSON.stringify(prevAssigned) !== JSON.stringify(assignedUserIds);

  return {
    duty: {
      ...duty,
      personIdsByName: nextMap,
      assignedUserIds,
    },
    changed: mapChanged || assignedChanged,
    warnings,
  };
}

async function main() {
  const { byName, ambiguous } = await loadUserNameIndex();
  const rosterSnap = await db.collection('rosters').get();

  let scanned = 0;
  let updated = 0;
  let dutyUpdates = 0;
  const unmatchedNames = new Set();

  for (const doc of rosterSnap.docs) {
    scanned += 1;
    const data = doc.data() || {};
    const duties = Array.isArray(data.duties) ? data.duties : null;
    if (!duties) continue;

    let changed = false;
    const nextDuties = duties.map((duty) => {
      const result = normalizeDuty(duty, byName);
      if (result.changed) {
        changed = true;
        dutyUpdates += 1;
      }
      for (const warning of result.warnings) {
        if (warning.startsWith('Unmatched name: ')) {
          unmatchedNames.add(warning.slice('Unmatched name: '.length));
        }
      }
      return result.duty;
    });

    if (!changed) continue;

    if (!dryRun) {
      await doc.ref.update({ duties: nextDuties });
    }
    updated += 1;
  }

  console.log(`Scanned rosters: ${scanned}`);
  console.log(`Updated rosters: ${updated}${dryRun ? ' (dry-run)' : ''}`);
  console.log(`Updated duties: ${dutyUpdates}`);
  if (ambiguous.size) {
    console.log(`Ambiguous user names skipped (${ambiguous.size}): ${[...ambiguous].sort().join(', ')}`);
  }
  if (unmatchedNames.size) {
    console.log(`Unmatched names (${unmatchedNames.size}): ${[...unmatchedNames].sort().join(', ')}`);
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await admin.app().delete().catch(() => {});
  });
