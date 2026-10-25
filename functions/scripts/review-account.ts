// Sets up, or puts back, a store reviewer's demo account: an email account
// that is the only admin of a sample church, on its next eight Sundays'
// rosters (everyone else is a name without an account). Reviewers try
// 刪除帳號, which takes the church with it (Google Play's did, 2026-10-22,
// and App Review then could not sign in), so each store has its own account
// and running this again brings one back: the account is made anew, the
// church reopened and the rosters written from this week on.
//
//   REVIEW_PASSWORD=… scripts/as-owner.sh marthasit-dev npx tsx functions/scripts/review-account.ts \
//     --project marthasit-dev --email apple-review@marthasit.com --name 'App Store 審查' --church 'App Store 審查用教會'
//
// The prod project also needs --really. The accounts and passwords are in
// pass, martha/apple-review and martha/play-review.
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

import { openChurch } from '../src/church.js';
import { PROD_PROJECT, serverTime } from '../src/common.js';
import { nameKey } from '../src/text.js';

const args = process.argv.slice(2);
const flag = (name: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};
const project = flag('project');
const email = flag('email');
const name = flag('name');
const churchName = flag('church');
const password = process.env.REVIEW_PASSWORD;
if (!project || !email || !name || !churchName) throw new Error('Usage: --project <id> --email <e> --name <n> --church <c>');
if (!password || password.length < 8) throw new Error('Set REVIEW_PASSWORD (8 characters or more)');
if (project === PROD_PROJECT && !args.includes('--really')) throw new Error(`Refusing to write to ${project} without --really`);

initializeApp({ projectId: project });
const auth = getAuth();
const db = getFirestore();

const DUTIES = ['司會', '敬拜', '司琴', '音控', '投影', '招待'];
const SERVICES = {
  services: [
    {
      id: 'sunday',
      name: '主日崇拜',
      weekday: 7,
      enabled: true,
      duties: DUTIES,
      events: [
        { name: '聖餐', color: 0 },
        { name: '浸禮', color: 4 },
      ],
    },
  ],
  ids: ['sunday'],
};
const PEOPLE = ['陳以琳', '林家豪', '王美玲', '張志明', '李恩慈', '黃俊傑', '吳佩珊', '劉建宏', '周雅婷', '許文彬'];
/** Where the reviewer serves on their weeks (every other one): 招待, 司會, 投影 by turns. */
const THEIR_SLOTS = [5, 0, 4];
const THEIR_DUTIES = ['招待', '司會', '投影'];

// The account: made anew, or its password set back.
const user = await auth.getUserByEmail(email).then(
  (u) => auth.updateUser(u.uid, { password, emailVerified: true, disabled: false, displayName: name }),
  async (e: { code?: string }) => {
    if (e.code !== 'auth/user-not-found') throw e;
    return auth.createUser({ email, password, emailVerified: true, displayName: name });
  },
);
const uid = user.uid;
await db.doc(`users/${uid}`).set(
  { name, email, appLocale: 'zh-Hant', createdAt: serverTime(), updatedAt: serverTime() },
  { merge: true },
);

// The church: reopened when its name is still taken, else made.
const member = {
  uid,
  name,
  email,
  role: 'admin',
  identities: [{ kind: 'admin' }],
  groups: [],
  zones: [{ serviceType: 'sunday', duties: THEIR_DUTIES, smallGroups: [] }],
  zoneTypes: ['sunday'],
};
const reserved = await db.doc(`churchNames/${nameKey(churchName)}`).get();
let cid: string;
if (reserved.exists) {
  cid = reserved.get('cid') as string;
  await db.doc(`churches/${cid}`).update({ status: 'active', deletedAt: null });
  await db.doc(`churches/${cid}/members/${uid}`).set({ ...member, joinedAt: serverTime() });
  await db.doc(`churches/${cid}/settings/services`).set({ ...SERVICES, updatedAt: serverTime() });
} else {
  cid = await openChurch(
    { db, now: () => new Date(), fetch },
    { uid, email, emailVerified: true, name, operator: false },
    churchName,
    { services: SERVICES, admin: { name, zones: member.zones, zoneTypes: member.zoneTypes }, timeZone: 'Asia/Taipei' },
  );
  await db.doc(`churches/${cid}/members/${uid}`).update({ identities: member.identities });
}

// Eight Sundays from this week's, in Taipei.
const today = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Taipei' }));
const sunday = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate() + ((7 - today.getDay()) % 7)));
const batch = db.batch();
for (let w = 0; w < 8; w++) {
  const dateKey = new Date(sunday.getTime() + w * 7 * 86_400_000).toISOString().slice(0, 10);
  const slots = Array.from({ length: 7 }, (_, i) => PEOPLE[(w * 3 + i) % PEOPLE.length]);
  if (w % 2 === 0) slots[THEIR_SLOTS[(w / 2) % THEIR_SLOTS.length]] = name;
  const duties = DUTIES.map((role, i) => {
    const people = role === '招待' ? slots.slice(5) : [slots[i]];
    return { role, people, uids: people.includes(name) ? { [name]: uid } : {} };
  });
  batch.set(db.doc(`churches/${cid}/rosters/${dateKey}_sunday`), { type: 'sunday', dateKey, duties, events: [] });
}
await batch.commit();

console.log(`${email} (${uid}) is the admin of ${churchName} (${cid}) in ${project}, rosters from ${sunday.toISOString().slice(0, 10)}.`);
