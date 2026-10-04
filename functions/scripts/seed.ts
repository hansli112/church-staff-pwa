// Seeds a performance-test church: 150 members, three services, a year of
// rosters, staff orders. The same shape as the app's in-memory demo
// (app/lib/data/memory/demo_data.dart), so numbers are comparable.
//
//   # against the emulators (default)
//   FIRESTORE_EMULATOR_HOST=localhost:8181 FIREBASE_AUTH_EMULATOR_HOST=localhost:9199 \
//     npx tsx scripts/seed.ts
//   # against a real project: needs --project and --really
//   npx tsx scripts/seed.ts --project marthasit-dev --really
//
// Re-running replaces the same documents (fixed IDs), so it never duplicates.
// Sign in as perf-admin@example.com / perf-admin-123 (emulator only).
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const flag = (name: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? (args[i + 1] ?? '') : undefined;
};
const emulated = !!process.env.FIRESTORE_EMULATOR_HOST;
const projectId = flag('project') ?? (emulated ? 'demo-martha' : undefined);
if (!projectId) throw new Error('Set FIRESTORE_EMULATOR_HOST or pass --project');
if (!emulated && !args.includes('--really')) {
  throw new Error(`Refusing to write to real project ${projectId} without --really`);
}
const memberCount = Number(flag('members') ?? 150);
const cid = flag('church') ?? 'perf';

initializeApp({ projectId });
const db = getFirestore();

const services = [
  {
    id: 'sunday',
    name: '主日崇拜',
    weekday: 7,
    enabled: true,
    duties: ['司會', '敬拜主領', '司琴', '鼓', '音控', '投影', '招待', '奉獻'],
    events: [
      { name: '聖餐', color: 0 },
      { name: '浸禮', color: 4 },
      { name: '特會', color: 5 },
    ],
  },
  { id: 'youth', name: '青年崇拜', weekday: 6, enabled: true, duties: ['司會', '敬拜主領', '吉他', '音控', '投影'], events: [] },
  { id: 'prayer', name: '禱告會', weekday: 3, enabled: true, duties: ['帶領', '司琴'], events: [] },
];

const surnames = '陳林黃張李王吳劉蔡楊許鄭謝郭洪曾邱廖賴徐周葉蘇莊呂江何蕭羅高潘簡朱鍾彭游詹胡施沈余趙盧梁顏柯孫魏翁戴范宋方';
const given = '志明美玲雅婷家豪俊傑淑芬怡君宗翰佳穎建宏欣怡冠宇思妤承恩惠如柏翰詩涵子軒心怡育誠文華';
const ch = (s: string, i: number) => [...s][i % [...s].length];

interface Member {
  uid: string;
  name: string;
  zones: { serviceType: string; duties: string[] }[];
}

const members: Member[] = [];
for (let i = 0; i < memberCount; i++) {
  const name = ch(surnames, i) + ch(given, i * 7) + ch(given, i * 13 + 3);
  const zones = services
    .map((s, j) => ({ s, j }))
    .filter(({ j }) => (i + j) % 3 !== 2)
    .map(({ s, j }) => ({
      serviceType: s.id,
      duties: s.duties.filter((_, k) => (i + k * 5 + j) % 6 === 0),
    }));
  members.push({ uid: `perf-m${i}`, name, zones });
}

function dateKey(d: Date) {
  return d.toISOString().slice(0, 10);
}

async function main() {
  const auth = getAuth();
  let adminUid = members[0].uid;
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    try {
      adminUid = (await auth.getUserByEmail('perf-admin@example.com')).uid;
    } catch {
      adminUid = (
        await auth.createUser({
          uid: members[0].uid,
          email: 'perf-admin@example.com',
          password: 'perf-admin-123',
          emailVerified: true,
          displayName: members[0].name,
        })
      ).uid;
    }
  }

  const writer = db.bulkWriter();
  void writer.set(db.doc(`churches/${cid}`), {
    name: '效能測試教會',
    nameKey: `效能測試教會${cid}`,
    status: 'active',
    createdBy: adminUid,
    createdAt: Timestamp.now(),
    deletedAt: null,
  });
  void writer.set(db.doc(`churchNames/效能測試教會${cid}`), { cid });
  void writer.set(db.doc(`churches/${cid}/settings/services`), {
    services,
    ids: services.map((s) => s.id),
    updatedAt: Timestamp.now(),
  });
  for (const [i, m] of members.entries()) {
    void writer.set(db.doc(`churches/${cid}/members/${m.uid}`), {
      uid: m.uid,
      name: m.name,
      email: `${m.uid}@example.com`,
      role: i === 0 ? 'admin' : i % 10 === 0 ? 'leader' : 'staff',
      groups: i % 15 === 1 ? ['roster-editors'] : [],
      zones: m.zones,
      zoneTypes: m.zones.map((z) => z.serviceType),
      joinedAt: Timestamp.now(),
    });
  }
  void writer.set(db.doc(`users/${adminUid}`), {
    name: members[0].name,
    email: 'perf-admin@example.com',
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  });

  // A year of rosters starting four weeks ago.
  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);
  let rosterCount = 0;
  for (const s of services) {
    const start = new Date(today.getTime() - 28 * 86400e3);
    const weekday = start.getUTCDay() === 0 ? 7 : start.getUTCDay();
    let day = new Date(start.getTime() + ((s.weekday - weekday + 7) % 7) * 86400e3);
    for (let week = 0; week < 52; week++, day = new Date(day.getTime() + 7 * 86400e3)) {
      const duties = s.duties.map((duty, k) => {
        const pool = members.filter((m) => m.zones.some((z) => z.serviceType === s.id && z.duties.includes(duty)));
        if (pool.length === 0) return { role: duty, people: [], uids: {} };
        const picks = [...new Set([pool[(week + k) % pool.length], ...(duty === '招待' || duty === '敬拜主領' ? [pool[(week + k + 1) % pool.length]] : [])])];
        return {
          role: duty,
          people: picks.map((p) => p.name),
          uids: Object.fromEntries(picks.map((p) => [p.name, p.uid])),
        };
      });
      const key = dateKey(day);
      void writer.set(db.doc(`churches/${cid}/rosters/${key}_${s.id}`), {
        type: s.id,
        dateKey: key,
        duties,
        events: week % 4 === 0 && s.events.length > 0 ? [s.events[0]] : [],
        updatedAt: Timestamp.now(),
      });
      rosterCount++;
    }
    void writer.set(db.doc(`churches/${cid}/staff_orders/${s.id}`), {
      roles: Object.fromEntries(
        s.duties.map((duty) => [
          duty,
          members.filter((m) => m.zones.some((z) => z.serviceType === s.id && z.duties.includes(duty))).map((m) => m.name),
        ]),
      ),
    });
  }
  await writer.close();
  console.log(`Seeded churches/${cid}: ${members.length} members, ${rosterCount} rosters (project ${projectId}).`);
}

await main();
