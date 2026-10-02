// storage.rules 的測試：教會 logo 只有該教會的管理員能上傳。
// Storage rules 讀 Firestore 判斷成員與角色，所以兩個 emulator 都要開。
import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

let testEnv;
const [fsHost, fsPort] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8181').split(':');
const [stHost, stPort] = (process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '127.0.0.1:9299').split(':');

const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
const image = { contentType: 'image/png' };

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-martha',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: fsHost,
      port: Number(fsPort),
    },
    storage: {
      rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8'),
      host: stHost,
      port: Number(stPort),
    },
  });
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'churches/A'), { name: 'A', status: 'active' });
    await setDoc(doc(db, 'churches/B'), { name: 'B', status: 'active' });
    await setDoc(doc(db, 'churches/S'), { name: 'S', status: 'suspended' });
    await setDoc(doc(db, 'churches/A/members/admin-a'), { uid: 'admin-a', role: 'admin' });
    await setDoc(doc(db, 'churches/A/members/staff-a'), { uid: 'staff-a', role: 'staff' });
    await setDoc(doc(db, 'churches/B/members/admin-b'), { uid: 'admin-b', role: 'admin' });
    await setDoc(doc(db, 'churches/S/members/admin-s'), { uid: 'admin-s', role: 'admin' });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

const storageAs = (uid) => testEnv.authenticatedContext(uid).storage();

describe('教會 logo', () => {
  it('該教會的管理員可以上傳，同工可以讀', async () => {
    await assertSucceeds(uploadBytes(ref(storageAs('admin-a'), 'churches/A/logo.png'), png, image));
    await assertSucceeds(getBytes(ref(storageAs('staff-a'), 'churches/A/logo.png')));
  });

  it('同工、其他教會的管理員、陌生人都不能上傳', async () => {
    await assertFails(uploadBytes(ref(storageAs('staff-a'), 'churches/A/logo.png'), png, image));
    await assertFails(uploadBytes(ref(storageAs('admin-b'), 'churches/A/logo.png'), png, image));
    await assertFails(uploadBytes(ref(storageAs('stranger'), 'churches/A/logo.png'), png, image));
  });

  it('其他教會的人讀不到', async () => {
    await assertFails(getBytes(ref(storageAs('admin-b'), 'churches/A/logo.png')));
  });

  it('超過 1MB 或不是圖片會被擋', async () => {
    const big = new Uint8Array(1024 * 1024 + 1);
    await assertFails(uploadBytes(ref(storageAs('admin-a'), 'churches/A/logo.png'), big, image));
    await assertFails(
      uploadBytes(ref(storageAs('admin-a'), 'churches/A/logo.png'), png, { contentType: 'text/html' }),
    );
  });

  it('停用中的教會不能上傳；其他路徑一律不行', async () => {
    await assertFails(uploadBytes(ref(storageAs('admin-s'), 'churches/S/logo.png'), png, image));
    await assertFails(uploadBytes(ref(storageAs('admin-a'), 'churches/A/other.png'), png, image));
    await assertFails(uploadBytes(ref(storageAs('admin-a'), 'anything.png'), png, image));
  });
});
