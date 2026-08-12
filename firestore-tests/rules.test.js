// firestore.rules 的安全規則測試，跑在 Firestore emulator 上。
//
//   cd firestore-tests && npm install && npm test
//
// 規則是唯一擋得住「繞過 App、直接用公開 web SDK 打 Firestore」的東西，
// 所以每一條授權判斷都要有對應的測試。
import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');

let testEnv;

const ADMIN = 'admin-1';
const MEMBER = 'member-1';
const OTHER = 'member-2';
const DELETED = 'deleted-1'; // 有 Auth token，但 users 文件已被管理員刪掉

function userDoc(id, role) {
  return {
    id,
    name: `姓名-${id}`,
    email: `${id}@example.com`,
    username: id,
    role,
    zones: [],
  };
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-church-staff',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host,
      port: Number(port),
    },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', ADMIN), userDoc(ADMIN, 'admin'));
    await setDoc(doc(db, 'users', MEMBER), userDoc(MEMBER, 'member'));
    await setDoc(doc(db, 'users', OTHER), userDoc(OTHER, 'leader'));
    // 注意：DELETED 刻意沒有 users 文件。
    await setDoc(doc(db, 'rosters', 'r1'), { serviceName: '主日崇拜' });
    await setDoc(doc(db, 'settings', 'roster_templates'), {
      sundayService: ['領會'],
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

const asAdmin = () => testEnv.authenticatedContext(ADMIN).firestore();
const asMember = () => testEnv.authenticatedContext(MEMBER).firestore();
const asDeleted = () => testEnv.authenticatedContext(DELETED).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

describe('rosters / settings 讀取', () => {
  it('一般同工讀得到服事表', async () => {
    await assertSucceeds(getDoc(doc(asMember(), 'rosters', 'r1')));
  });

  it('一般同工讀得到 settings', async () => {
    await assertSucceeds(
      getDoc(doc(asMember(), 'settings', 'roster_templates')),
    );
  });

  // 這是 isActiveUser() 存在的理由：後台刪帳號只刪 Firestore 文件，
  // Firebase Auth 帳號還活著，token 仍然有效。
  it('被刪掉的帳號讀不到服事表', async () => {
    await assertFails(getDoc(doc(asDeleted(), 'rosters', 'r1')));
  });

  it('被刪掉的帳號讀不到 settings', async () => {
    await assertFails(
      getDoc(doc(asDeleted(), 'settings', 'roster_templates')),
    );
  });

  it('未登入讀不到服事表', async () => {
    await assertFails(getDoc(doc(asAnon(), 'rosters', 'r1')));
  });
});

describe('rosters / settings 寫入', () => {
  it('一般同工不能改服事表', async () => {
    await assertFails(
      setDoc(doc(asMember(), 'rosters', 'r1'), { serviceName: '亂改' }),
    );
  });

  it('管理員可以改服事表', async () => {
    await assertSucceeds(
      setDoc(doc(asAdmin(), 'rosters', 'r1'), { serviceName: '主日崇拜' }),
    );
  });

  it('一般同工不能改 settings', async () => {
    await assertFails(
      setDoc(doc(asMember(), 'settings', 'roster_templates'), { x: 1 }),
    );
  });

  it('被刪掉的帳號不能改服事表', async () => {
    await assertFails(
      setDoc(doc(asDeleted(), 'rosters', 'r1'), { serviceName: '亂改' }),
    );
  });
});

describe('users 讀取', () => {
  it('讀得到自己的資料', async () => {
    await assertSucceeds(getDoc(doc(asMember(), 'users', MEMBER)));
  });

  // 收窄前：任何登入者都讀得到全部人的 email 與 fcm token。
  it('一般同工讀不到別人的資料', async () => {
    await assertFails(getDoc(doc(asMember(), 'users', OTHER)));
  });

  it('管理員讀得到別人的資料', async () => {
    await assertSucceeds(getDoc(doc(asAdmin(), 'users', OTHER)));
  });

  it('被刪掉的帳號讀不到別人的資料', async () => {
    await assertFails(getDoc(doc(asDeleted(), 'users', MEMBER)));
  });
});

describe('users 自我更新', () => {
  // PushNotificationService._saveToken 走的就是這條（set + merge）。
  it('可以寫自己的 fcm token', async () => {
    await assertSucceeds(
      setDoc(
        doc(asMember(), 'users', MEMBER),
        { fcm: { webTokens: ['token-abc'] } },
        { merge: true },
      ),
    );
  });

  it('可以寫自己的 notificationPrefs', async () => {
    await assertSucceeds(
      setDoc(
        doc(asMember(), 'users', MEMBER),
        { notificationPrefs: { weeklyRosterReminder: true } },
        { merge: true },
      ),
    );
  });

  it('不能把自己升成管理員', async () => {
    await assertFails(
      updateDoc(doc(asMember(), 'users', MEMBER), { role: 'admin' }),
    );
  });

  it('不能改自己的姓名或 zones（要透過管理員）', async () => {
    await assertFails(
      updateDoc(doc(asMember(), 'users', MEMBER), { name: '自己改的' }),
    );
    await assertFails(
      updateDoc(doc(asMember(), 'users', MEMBER), {
        zones: [{ serviceType: 'sundayService', ministries: [], smallGroups: [] }],
      }),
    );
  });

  it('不能改別人的 fcm', async () => {
    await assertFails(
      setDoc(
        doc(asMember(), 'users', OTHER),
        { fcm: { webTokens: ['token-xyz'] } },
        { merge: true },
      ),
    );
  });
});

describe('users 管理員操作與 role 驗證', () => {
  it('管理員可以用合法 role 建立帳號', async () => {
    await assertSucceeds(
      setDoc(doc(asAdmin(), 'users', 'new-staff'), userDoc('new-staff', 'staff')),
    );
  });

  it('管理員不能寫入不合法的 role', async () => {
    await assertFails(
      setDoc(
        doc(asAdmin(), 'users', 'new-bogus'),
        userDoc('new-bogus', 'superuser'),
      ),
    );
  });

  it('管理員不能把既有帳號改成不合法的 role', async () => {
    await assertFails(
      updateDoc(doc(asAdmin(), 'users', OTHER), { role: 'root' }),
    );
  });

  it('管理員可以調整別人的 role', async () => {
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'users', OTHER), { role: 'staff' }),
    );
  });

  it('一般同工不能建立帳號', async () => {
    await assertFails(
      setDoc(doc(asMember(), 'users', 'sneaky'), userDoc('sneaky', 'admin')),
    );
  });

  it('一般同工不能刪帳號', async () => {
    await assertFails(deleteDoc(doc(asMember(), 'users', OTHER)));
  });

  it('管理員可以刪帳號', async () => {
    await assertSucceeds(deleteDoc(doc(asAdmin(), 'users', 'new-staff')));
  });
});

describe('預設拒絕', () => {
  it('未定義的 collection 一律拒絕，連管理員也是', async () => {
    await assertFails(getDoc(doc(asAdmin(), 'anything', 'x')));
    await assertFails(setDoc(doc(asAdmin(), 'anything', 'x'), { a: 1 }));
  });
});
