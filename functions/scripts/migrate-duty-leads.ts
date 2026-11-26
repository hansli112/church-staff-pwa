// One-time move of 服事項目's 負責人 off 事工 (2026-11-26). A 事工 used to
// link duties, its 負責人 arranging them; now a duty's 負責人 is held on the
// member (`dutyLead`, `leadDuties`) and a 事工 is a team with its own
// events. Each 負責人 of a 事工 that linked duties becomes the 負責人 of
// each of those duties its service still has; the 事工 stays, with its
// 負責人, and loses `duties` and `addedIn`. Duties linked for events (no
// service) are dropped: an event's roster is its group's 負責人's.
//
//   # Look first (writes nothing):
//   npx tsx scripts/migrate-duty-leads.ts --project marthasit-dev
//   # Then write:
//   npx tsx scripts/migrate-duty-leads.ts --project marthasit-dev --apply
//
// Every church, or one with --church. Prints counts and IDs, not names.
// Credentials: Application Default Credentials, as the other scripts.
import { pathToFileURL } from 'node:url';

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

import { identitiesOf, sameIdentity, withIdentities, type Identity } from '../src/identities.js';

type Change = { path: string; update: Record<string, unknown> };

/** The writes, per church, that move [churches] (all when empty). */
export async function planDutyLeads(db: Firestore, churches: string[] = []) {
  const ids = churches.length > 0 ? churches : (await db.collection('churches').listDocuments()).map((d) => d.id);
  const changes: Change[] = [];
  for (const cid of ids) {
    const settings = await db.doc(`churches/${cid}/settings/ministries`).get();
    const list = settings.get('ministries');
    const isObject = (m: unknown): m is Record<string, unknown> => typeof m === 'object' && m !== null;
    if (!Array.isArray(list) || !list.some((m) => isObject(m) && ('duties' in m || 'addedIn' in m))) continue;
    const services = await db.doc(`churches/${cid}/settings/services`).get();
    const has = (service: string, duty: string) =>
      ((services.get('services') as { id: string; duties?: string[] }[] | undefined) ?? [])
        .some((s) => s.id === service && (s.duties ?? []).includes(duty));
    const linked = new Map<string, { service: string; duty: string }[]>();
    for (const m of list) {
      const duties = ((Array.isArray(m?.duties) ? m.duties : []) as unknown[]).filter(
        (d): d is { service: string; duty: string } =>
          typeof (d as { service?: unknown })?.service === 'string' && typeof (d as { duty?: unknown })?.duty === 'string',
      );
      if (typeof m?.id === 'string') linked.set(m.id, duties.filter((d) => has(d.service, d.duty)));
    }
    const members = await db.collection(`churches/${cid}/members`).get();
    for (const member of members.docs) {
      const held = identitiesOf(member.data());
      const more: Identity[] = held
        .flatMap((i) => ('ministry' in i ? linked.get(i.ministry) ?? [] : []))
        .map((d) => ({ kind: 'dutyLead', service: d.service, duty: d.duty }) as const)
        .filter((i, at, all) => !held.some((h) => sameIdentity(h, i)) && all.findIndex((o) => sameIdentity(o, i)) === at);
      if (more.length > 0) changes.push({ path: member.ref.path, update: withIdentities(member.data(), [...held, ...more]) });
    }
    changes.push({
      path: settings.ref.path,
      update: {
        ministries: list
          .filter((m) => typeof m?.id === 'string' && typeof m?.name === 'string')
          .map((m) => ({ id: m.id, name: m.name })),
      },
    });
  }
  return changes;
}

export async function applyDutyLeads(db: Firestore, changes: Change[]) {
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
  const changes = await planDutyLeads(db, church ? [church] : []);
  const members = changes.filter((c) => c.path.includes('/members/'));
  console.log(JSON.stringify({
    churches: changes.filter((c) => c.path.endsWith('/settings/ministries')).length,
    members: members.map((c) => ({ path: c.path, leadDuties: c.update.leadDuties })),
  }, null, 2));
  if (!argv.includes('--apply')) {
    console.log('Preview only: nothing written. Add --apply to write.');
    return;
  }
  await applyDutyLeads(db, changes);
  console.log(`Updated ${members.length} members.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main(process.argv.slice(2));
