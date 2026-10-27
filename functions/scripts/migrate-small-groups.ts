// One-time move to 小組 (#85). The small-group names members kept in their
// 牧區 (`zones[].smallGroups`) become 小組 (churches/{cid}/smallGroups, in
// that service), and each member is one of those they named; one whose
// old 身分 was 小組長 (role leader) leads them. Pending members are left:
// they get theirs when they sign in (claim.ts). Run again, it changes
// nothing more. Run it after scripts/migrate-leads.ts, which it checks.
//
//   # Look first (writes nothing):
//   npx tsx scripts/migrate-small-groups.ts --project marthasit-dev
//   # Then write:
//   npx tsx scripts/migrate-small-groups.ts --project marthasit-dev --apply
//
// Every church, or one with --church. Prints counts and IDs, not names.
// Credentials: Application Default Credentials, as the other scripts.
import { pathToFileURL } from 'node:url';

import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, type Firestore } from 'firebase-admin/firestore';

import { identitiesOf, sameIdentity, withIdentities } from '../src/identities.js';
import { claimedSmallGroups, nameKey, namedSmallGroups, smallGroupsByName } from '../src/smallGroups.js';

type Write = { path: string; set?: Record<string, unknown>; update?: Record<string, unknown> };

/** What to write in [churches] (all when empty). */
export async function planSmallGroups(db: Firestore, churches: string[] = []) {
  const ids = churches.length > 0 ? churches : (await db.collection('churches').listDocuments()).map((d) => d.id);
  const writes: Write[] = [];
  for (const cid of ids) {
    const [members, pending, existing, services] = await Promise.all([
      db.collection(`churches/${cid}/members`).get(),
      db.collection(`churches/${cid}/pendingMembers`).get(),
      db.collection(`churches/${cid}/smallGroups`).get(),
      db.doc(`churches/${cid}/settings/services`).get(),
    ]);
    // 小組長 is added to the 身分 a member has; one still in the old
    // permission groups gets theirs from migrate-leads.ts first.
    const unmoved = members.docs.filter((m) => m.get('role') !== 'admin' && m.get('identities') === undefined
      && Array.isArray(m.get('groups')) && (m.get('groups') as unknown[]).length > 0);
    if (unmoved.length) throw new Error(`Run scripts/migrate-leads.ts first: ${unmoved.map((m) => m.ref.path).join(', ')}`);
    const known = new Set(((services.get('ids') as string[] | undefined) ?? []));
    const byName = smallGroupsByName(existing.docs);
    const made: string[] = [];
    for (const g of [...members.docs, ...pending.docs].flatMap((m) => namedSmallGroups(m.get('zones')))) {
      const key = nameKey(g.service, g.name);
      if (byName.has(key) || !known.has(g.service)) continue;
      const at = db.collection(`churches/${cid}/smallGroups`).doc();
      byName.set(key, at.id);
      made.push(at.id);
      writes.push({ path: at.path, set: { name: g.name, service: g.service } });
    }
    if (made.length) writes.push({ path: `churches/${cid}/settings/smallGroups`, set: { ids: FieldValue.arrayUnion(...made) } });
    for (const m of members.docs) {
      const claimed = claimedSmallGroups(m.get('zones'), m.get('role'), byName);
      const has = new Set((m.get('smallGroups') as string[] | undefined) ?? []);
      const holds = identitiesOf(m.data());
      const joins = claimed.smallGroups.filter((id) => !has.has(id));
      const led = claimed.identities.filter((i) => !holds.some((h) => sameIdentity(h, i)));
      if (!joins.length && !led.length) continue;
      writes.push({
        path: m.ref.path,
        update: {
          ...(joins.length ? { smallGroups: FieldValue.arrayUnion(...joins) } : {}),
          ...(led.length ? withIdentities(m.data(), [...holds, ...led]) : {}),
        },
      });
    }
  }
  return writes;
}

export async function applySmallGroups(db: Firestore, writes: Write[]) {
  for (const w of writes) {
    if (w.set) await db.doc(w.path).set(w.set, { merge: true });
    else await db.doc(w.path).update(w.update!);
  }
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
  const writes = await planSmallGroups(db, church ? [church] : []);
  console.log(JSON.stringify(writes.map((w) => w.path), null, 2));
  if (!argv.includes('--apply')) {
    console.log('Preview only: nothing written. Add --apply to write.');
    return;
  }
  await applySmallGroups(db, writes);
  console.log(`Wrote ${writes.length} documents.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main(process.argv.slice(2));
