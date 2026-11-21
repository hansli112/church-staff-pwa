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
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';

let testEnv;
const [fsHost, fsPort] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8181').split(':');
const [stHost, stPort] = (process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '127.0.0.1:9399').split(':');

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
    await setDoc(doc(db, 'churches/A/members/lead-a'), { uid: 'lead-a', role: 'staff', leadMinistries: ['worship'] });
    await setDoc(doc(db, 'churches/A/members/office-a'), { uid: 'office-a', role: 'staff', groups: ['roster-editors'] });
    await setDoc(doc(db, 'churches/A/members/sunday-lead-a'), { uid: 'sunday-lead-a', role: 'staff', leadTypes: ['sunday'] });
    await setDoc(doc(db, 'churches/A/members/group-lead-a'), { uid: 'group-lead-a', role: 'staff', leadSmallGroups: ['g1'] });
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

describe('搬家檔', () => {
  const json = new TextEncoder().encode('{"format":"church-staff-pwa-move"}');
  const meta = { contentType: 'application/json' };

  it('只有上傳者本人能讀寫', async () => {
    await assertSucceeds(uploadBytes(ref(storageAs('mover'), 'moves/mover/f1.json'), json, meta));
    await assertSucceeds(getBytes(ref(storageAs('mover'), 'moves/mover/f1.json')));
    await assertFails(getBytes(ref(storageAs('admin-a'), 'moves/mover/f1.json')));
    await assertFails(uploadBytes(ref(storageAs('admin-a'), 'moves/mover/f2.json'), json, meta));
    await assertFails(getBytes(ref(testEnv.unauthenticatedContext().storage(), 'moves/mover/f1.json')));
  });

  it('最大 20MB', async () => {
    const big = new Uint8Array(20 * 1024 * 1024 + 1);
    await assertFails(uploadBytes(ref(storageAs('mover'), 'moves/mover/big.json'), big, meta));
  });
});

describe('備註的檔案', () => {
  const path = (id) => `churches/A/rosterNotes/2030-12-22_sunday/${id}`;
  const pdf = (uid) => ({ contentType: 'application/pdf', customMetadata: { uploader: uid } });

  it('管理員、行政、負責人上傳什麼檔案都可以，教會的人讀得到', async () => {
    await assertSucceeds(uploadBytes(ref(storageAs('admin-a'), path('a')), png, pdf('admin-a')));
    await assertSucceeds(uploadBytes(ref(storageAs('office-a'), path('b')), png, { contentType: 'image/jpeg', customMetadata: { uploader: 'office-a' } }));
    await assertSucceeds(uploadBytes(ref(storageAs('lead-a'), path('c')), png, { contentType: 'audio/mp4', customMetadata: { uploader: 'lead-a' } }));
    await assertSucceeds(uploadBytes(ref(storageAs('lead-a'), path('w')), png, { contentType: 'application/vnd.ms-powerpoint', contentDisposition: 'attachment', customMetadata: { uploader: 'lead-a' } }));
    await assertSucceeds(getBytes(ref(storageAs('staff-a'), path('a'))));
    await assertFails(getBytes(ref(storageAs('admin-b'), path('a'))));
  });

  it('一般同工、別的教會不能上傳；超過 20MB、沒說是誰傳的都不行', async () => {
    await assertFails(uploadBytes(ref(storageAs('staff-a'), path('d')), png, pdf('staff-a')));
    await assertFails(uploadBytes(ref(storageAs('admin-b'), path('d')), png, pdf('admin-b')));
    await assertFails(uploadBytes(ref(storageAs('admin-a'), path('d')), png, { contentType: 'application/pdf' }));
    await assertFails(uploadBytes(ref(storageAs('admin-a'), path('d')), png, pdf('lead-a')));
    await assertFails(uploadBytes(ref(storageAs('admin-a'), path('d')), new Uint8Array(20 * 1024 * 1024 + 1), pdf('admin-a')));
  });

  it('瀏覽器會直接打開的只有 PDF、圖片、聲音、影片、純文字；其他都要下載', async () => {
    const as = (contentType, contentDisposition) => ({ contentType, contentDisposition, customMetadata: { uploader: 'lead-a' } });
    await assertSucceeds(uploadBytes(ref(storageAs('lead-a'), path('i1')), png, as('application/pdf', 'inline')));
    await assertSucceeds(uploadBytes(ref(storageAs('lead-a'), path('i2')), png, as('text/html', "attachment; filename*=UTF-8''a.html")));
    await assertFails(uploadBytes(ref(storageAs('lead-a'), path('i3')), png, as('text/html', 'inline')));
    await assertFails(uploadBytes(ref(storageAs('lead-a'), path('i4')), png, { contentType: 'text/html', customMetadata: { uploader: 'lead-a' } }));
    await assertFails(uploadBytes(ref(storageAs('lead-a'), path('i5')), png, as('image/svg+xml', 'inline')));
  });

  it('聚會負責人、小組長也能上傳', async () => {
    await assertSucceeds(uploadBytes(ref(storageAs('sunday-lead-a'), path('t')), png, pdf('sunday-lead-a')));
    await assertSucceeds(uploadBytes(ref(storageAs('group-lead-a'), path('g')), png, pdf('group-lead-a')));
  });

  it('傳上去的檔案不能被換掉，連上傳的人也不行', async () => {
    await assertSucceeds(uploadBytes(ref(storageAs('lead-a'), path('r')), png, pdf('lead-a')));
    await assertFails(uploadBytes(ref(storageAs('lead-a'), path('r')), png, pdf('lead-a')));
    await assertFails(uploadBytes(ref(storageAs('admin-a'), path('r')), png, pdf('admin-a')));
  });

  it('上傳的人可以收回自己傳的，別人不行', async () => {
    await assertSucceeds(uploadBytes(ref(storageAs('lead-a'), path('e')), png, pdf('lead-a')));
    await assertFails(deleteObject(ref(storageAs('admin-a'), path('e'))));
    await assertSucceeds(deleteObject(ref(storageAs('lead-a'), path('e'))));
  });
});
