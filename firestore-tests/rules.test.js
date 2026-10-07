// firestore.rules 的安全規則測試，跑在 Firestore emulator 上。
//
//   cd firestore-tests && npm install && npm test
//
// 所有教會共用同一個 project，路徑裡的 cid 就是唯一的隔離邊界。最重要的
// 一組是「跨教會隔離」：A 教會的管理員在 B 教會什麼都不能做。
import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  serverTimestamp,
  Timestamp,
  where,
} from 'firebase/firestore';

// 預設值要跟 firebase.json 的 emulators.firestore.port 一致。
const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8181').split(':');

let testEnv;

const A = 'church-a';
const B = 'church-b';
const SUSPENDED = 'church-s';

const ADMIN_A = 'admin-a';
const MEMBER_A = 'member-a';
const EDITOR_A = 'editor-a'; // roster-editors，只有 sunday 牧區
const ADMIN_B = 'admin-b';
const MEMBER_S = 'member-s'; // 停用教會的同工
const STRANGER = 'stranger'; // 有登入，但不屬於任何教會

function memberDoc(uid, role, groups, zoneTypes) {
  const document = { uid, name: `姓名-${uid}`, email: `${uid}@example.com`, role, zones: [] };
  if (groups !== undefined) document.groups = groups;
  if (zoneTypes !== undefined) document.zoneTypes = zoneTypes;
  return document;
}

function services(ids) {
  return { services: ids.map((id) => ({ id, name: id })), ids };
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-martha',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host,
      port: Number(port),
    },
  });
  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const put = (path, data) => setDoc(doc(db, path), data);

    await put(`churches/${A}`, { name: '恩典堂', nameKey: '恩典堂', status: 'active' });
    await put(`churches/${B}`, { name: '活水堂', nameKey: '活水堂', status: 'active' });
    await put(`churches/${SUSPENDED}`, { name: '停用堂', nameKey: '停用堂', status: 'suspended' });

    // 兩間教會都有 sunday —— 同名的聚會別 ID 不能讓權限跨教會生效。
    await put(`churches/${A}/settings/services`, services(['sunday', 'youth']));
    await put(`churches/${B}/settings/services`, services(['sunday', 'kids']));
    await put(`churches/${SUSPENDED}/settings/services`, services(['sunday']));
    await put(`churches/${A}/settings/roster_templates`, { sunday: ['領會'] });
    await put(`churches/${B}/settings/roster_templates`, { sunday: ['司琴'] });

    await put(`churches/${A}/members/${ADMIN_A}`, memberDoc(ADMIN_A, 'admin'));
    await put(`churches/${A}/members/${MEMBER_A}`, memberDoc(MEMBER_A, 'member'));
    await put(
      `churches/${A}/members/${EDITOR_A}`,
      memberDoc(EDITOR_A, 'staff', ['roster-editors'], ['sunday']),
    );
    await put(`churches/${B}/members/${ADMIN_B}`, memberDoc(ADMIN_B, 'admin'));
    await put(`churches/${SUSPENDED}/members/${MEMBER_S}`, memberDoc(MEMBER_S, 'admin'));

    await put(`churches/${A}/rosters/r-sunday`, { type: 'sunday', serviceName: '主日' });
    await put(`churches/${A}/rosters/r-youth`, { type: 'youth', serviceName: '青崇' });
    await put(`churches/${B}/rosters/r-sunday`, { type: 'sunday', serviceName: '主日' });
    await put(`churches/${SUSPENDED}/rosters/r-sunday`, { type: 'sunday' });
    await put(`churches/${A}/staff_orders/sunday`, { order: [] });

    await put(`users/${MEMBER_A}`, { name: '甲', email: `${MEMBER_A}@example.com` });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

// 每條會寫入的測試都用自己的文件，避免互相依賴執行順序。
async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled((context) =>
    setDoc(doc(context.firestore(), path), data),
  );
}

describe('跨教會隔離', () => {
  it('B 的管理員讀不到 A 的教會、服事表、同工、設定', async () => {
    const db = as(ADMIN_B);
    await assertFails(getDoc(doc(db, `churches/${A}`)));
    await assertFails(getDoc(doc(db, `churches/${A}/rosters/r-sunday`)));
    await assertFails(getDocs(collection(db, `churches/${A}/rosters`)));
    await assertFails(getDocs(collection(db, `churches/${A}/members`)));
    await assertFails(getDoc(doc(db, `churches/${A}/members/${ADMIN_A}`)));
    await assertFails(getDoc(doc(db, `churches/${A}/settings/roster_templates`)));
    await assertFails(getDoc(doc(db, `churches/${A}/staff_orders/sunday`)));
  });

  it('B 的管理員寫不了 A 的任何東西', async () => {
    const db = as(ADMIN_B);
    await assertFails(setDoc(doc(db, `churches/${A}/rosters/from-b`), { type: 'sunday' }));
    await assertFails(updateDoc(doc(db, `churches/${A}/rosters/r-sunday`), { note: 'x' }));
    await assertFails(deleteDoc(doc(db, `churches/${A}/rosters/r-youth`)));
    await assertFails(setDoc(doc(db, `churches/${A}/staff_orders/sunday`), { order: [] }));
    await assertFails(setDoc(doc(db, `churches/${A}/settings/roster_templates`), {}));
    await assertFails(updateDoc(doc(db, `churches/${A}/members/${MEMBER_A}`), { role: 'staff' }));
    await assertFails(deleteDoc(doc(db, `churches/${A}/members/${MEMBER_A}`)));
  });

  it('B 的管理員不能把自己加進 A', async () => {
    await assertFails(
      setDoc(doc(as(ADMIN_B), `churches/${A}/members/${ADMIN_B}`), memberDoc(ADMIN_B, 'admin')),
    );
  });

  it('A 的 sunday 編輯者動不了 B 的 sunday 服事表', async () => {
    const db = as(EDITOR_A);
    await assertSucceeds(updateDoc(doc(db, `churches/${A}/rosters/r-sunday`), { note: 'ok' }));
    await assertFails(updateDoc(doc(db, `churches/${B}/rosters/r-sunday`), { note: 'x' }));
    await assertFails(setDoc(doc(db, `churches/${B}/rosters/new`), { type: 'sunday' }));
  });

  it('A 的管理員不能把只存在於 B 的聚會別塞進 A 的牧區', async () => {
    await assertFails(
      updateDoc(doc(as(ADMIN_A), `churches/${A}/members/${MEMBER_A}`), { zoneTypes: ['kids'] }),
    );
  });

  it('沒有人能跨教會查服事表（collection group）', async () => {
    await assertFails(getDocs(collectionGroup(as(ADMIN_A), 'rosters')));
    await assertFails(
      getDocs(query(collectionGroup(as(ADMIN_A), 'rosters'), where('type', '==', 'sunday'))),
    );
  });

  it('沒有人能列出所有教會', async () => {
    await assertFails(getDocs(collection(as(ADMIN_A), 'churches')));
    await assertFails(getDocs(collection(as(STRANGER), 'churches')));
  });

  it('不屬於任何教會的人什麼都讀不到', async () => {
    const db = as(STRANGER);
    await assertFails(getDoc(doc(db, `churches/${A}`)));
    await assertFails(getDoc(doc(db, `churches/${A}/rosters/r-sunday`)));
    await assertFails(getDoc(doc(db, `churches/${A}/settings/services`)));
  });

  it('未登入什麼都讀不到', async () => {
    const db = asAnon();
    await assertFails(getDoc(doc(db, `churches/${A}`)));
    await assertFails(getDoc(doc(db, `churches/${A}/rosters/r-sunday`)));
    await assertFails(getDocs(collectionGroup(db, 'members')));
  });
});

describe('教會切換：查自己的 membership', () => {
  it('用 uid == 自己做 collection group 查詢，只拿到自己的', async () => {
    const snap = await assertSucceeds(
      getDocs(query(collectionGroup(as(MEMBER_A), 'members'), where('uid', '==', MEMBER_A))),
    );
    assert.deepStrictEqual(
      snap.docs.map((d) => d.ref.path),
      [`churches/${A}/members/${MEMBER_A}`],
    );
  });

  it('不帶條件、或查別人的 uid，都不行', async () => {
    const db = as(MEMBER_A);
    await assertFails(getDocs(collectionGroup(db, 'members')));
    await assertFails(getDocs(query(collectionGroup(db, 'members'), where('uid', '==', ADMIN_B))));
  });

  it('停用教會的同工還查得到自己的 membership 跟教會狀態', async () => {
    const db = as(MEMBER_S);
    await assertSucceeds(
      getDocs(query(collectionGroup(db, 'members'), where('uid', '==', MEMBER_S))),
    );
    const church = await assertSucceeds(getDoc(doc(db, `churches/${SUSPENDED}`)));
    assert.strictEqual(church.data().status, 'suspended');
  });
});

describe('教會本身', () => {
  it('同工讀得到自己的教會', async () => {
    await assertSucceeds(getDoc(doc(as(MEMBER_A), `churches/${A}`)));
  });

  it('客戶端不能建立、改名、改狀態、刪除教會（交給 Cloud Functions）', async () => {
    await assertFails(
      setDoc(doc(as(STRANGER), 'churches/new-church'), { name: '新教會', status: 'active' }),
    );
    await assertFails(updateDoc(doc(as(ADMIN_A), `churches/${A}`), { name: '改名' }));
    await assertFails(updateDoc(doc(as(MEMBER_S), `churches/${SUSPENDED}`), { status: 'active' }));
    await assertFails(deleteDoc(doc(as(ADMIN_A), `churches/${A}`)));
  });

  // 字數上限（8 個字）由 App 把關；規則的 size() 算 UTF-16 code unit，
  // 只擋濫用：上限 × 4 = 32。
  it('主畫面名稱：只有該教會的管理員能設定，最多 32 個 UTF-16 單位，也能拿掉', async () => {
    await seed(`churches/home-name`, { name: '台北靈糧堂民生分堂', nameKey: 'x', status: 'active' });
    await seed(`churches/home-name/members/${ADMIN_A}`, memberDoc(ADMIN_A, 'admin'));
    await seed(`churches/home-name/members/${MEMBER_A}`, memberDoc(MEMBER_A, 'member'));
    const ref = (uid) => doc(as(uid), 'churches/home-name');
    await assertSucceeds(updateDoc(ref(ADMIN_A), { homeName: '民生靈糧堂' }));
    await assertSucceeds(updateDoc(ref(ADMIN_A), { homeName: '一二三四五六七八' }));
    await assertSucceeds(updateDoc(ref(ADMIN_A), { homeName: '👍🏽'.repeat(8) }), '8 characters, 32 units');
    await assertSucceeds(updateDoc(ref(ADMIN_A), { homeName: 'A'.repeat(32) }), 'over 8 characters: the app’s to stop');
    await assertFails(updateDoc(ref(ADMIN_A), { homeName: 'A'.repeat(33) }));
    await assertFails(updateDoc(ref(ADMIN_A), { homeName: '🙏'.repeat(16) + 'A' }), '33 units');
    await assertFails(updateDoc(ref(ADMIN_A), { homeName: '' }));
    await assertFails(updateDoc(ref(ADMIN_A), { homeName: 8 }));
    await assertFails(updateDoc(ref(ADMIN_A), { homeName: '民生', name: '改名' }));
    await assertFails(updateDoc(ref(MEMBER_A), { homeName: '民生' }));
    await assertFails(updateDoc(ref(ADMIN_B), { homeName: '民生' }), 'another church’s admin');
    await assertSucceeds(updateDoc(ref(ADMIN_A), { homeName: deleteField() }));
    await assertFails(updateDoc(doc(as(MEMBER_S), `churches/${SUSPENDED}`), { homeName: '停用' }));
  });

  it('停用的教會：連管理員都讀寫不了裡面的東西', async () => {
    const db = as(MEMBER_S);
    await assertFails(getDoc(doc(db, `churches/${SUSPENDED}/rosters/r-sunday`)));
    await assertFails(setDoc(doc(db, `churches/${SUSPENDED}/rosters/new`), { type: 'sunday' }));
    await assertFails(getDoc(doc(db, `churches/${SUSPENDED}/settings/services`)));
  });
});

describe('同工 (members)', () => {
  it('讀得到自己，讀不到別人；roster-editors 和管理員可以列出全部', async () => {
    await assertSucceeds(getDoc(doc(as(MEMBER_A), `churches/${A}/members/${MEMBER_A}`)));
    await assertFails(getDoc(doc(as(MEMBER_A), `churches/${A}/members/${ADMIN_A}`)));
    await assertFails(getDocs(collection(as(MEMBER_A), `churches/${A}/members`)));
    await assertSucceeds(getDocs(collection(as(EDITOR_A), `churches/${A}/members`)));
    await assertSucceeds(getDocs(collection(as(ADMIN_A), `churches/${A}/members`)));
  });

  it('自己只能改 notificationPrefs', async () => {
    const ref = (db) => doc(db, `churches/${A}/members/${MEMBER_A}`);
    await assertSucceeds(updateDoc(ref(as(MEMBER_A)), { notificationPrefs: { roster: true } }));
    await assertFails(updateDoc(ref(as(MEMBER_A)), { role: 'admin' }));
    await assertFails(updateDoc(ref(as(MEMBER_A)), { groups: ['roster-editors'] }));
    await assertFails(updateDoc(ref(as(MEMBER_A)), { zoneTypes: ['sunday'] }));
  });

  it('客戶端不能自己加入教會（邀請走 Cloud Functions）', async () => {
    await assertFails(
      setDoc(doc(as(STRANGER), `churches/${A}/members/${STRANGER}`), memberDoc(STRANGER, 'member')),
    );
    await assertFails(
      setDoc(doc(as(ADMIN_A), `churches/${A}/members/${STRANGER}`), memberDoc(STRANGER, 'member')),
    );
  });

  it('管理員可以調整別人的角色、群組、牧區', async () => {
    const uid = 'promote-me';
    await seed(`churches/${A}/members/${uid}`, memberDoc(uid, 'member'));
    await assertSucceeds(
      updateDoc(doc(as(ADMIN_A), `churches/${A}/members/${uid}`), {
        role: 'staff',
        groups: ['roster-editors'],
        zoneTypes: ['youth'],
      }),
    );
  });

  it('管理員不能寫不存在的角色、群組、牧區，也不能改 uid', async () => {
    const ref = doc(as(ADMIN_A), `churches/${A}/members/${MEMBER_A}`);
    await assertFails(updateDoc(ref, { role: 'owner' }));
    await assertFails(updateDoc(ref, { groups: ['typo-editors'] }));
    await assertFails(updateDoc(ref, { zoneTypes: ['nope'] }));
    await assertFails(updateDoc(ref, { uid: ADMIN_B }));
    await assertSucceeds(updateDoc(ref, { name: 'A'.repeat(160) }), '40 characters × 4 units');
    await assertFails(updateDoc(ref, { name: 'A'.repeat(161) }));
    await assertFails(updateDoc(ref, { name: 40 }));
  });

  it('管理員不能把自己降級', async () => {
    await assertFails(
      updateDoc(doc(as(ADMIN_A), `churches/${A}/members/${ADMIN_A}`), { role: 'staff' }),
    );
  });

  it('非管理員可以自己退出；管理員不行', async () => {
    const uid = 'leaver';
    await seed(`churches/${A}/members/${uid}`, memberDoc(uid, 'staff'));
    await assertSucceeds(deleteDoc(doc(as(uid), `churches/${A}/members/${uid}`)));
    await assertFails(deleteDoc(doc(as(ADMIN_A), `churches/${A}/members/${ADMIN_A}`)));
  });

  it('管理員可以移除別人，一般同工不行', async () => {
    const uid = 'removed';
    await seed(`churches/${A}/members/${uid}`, memberDoc(uid, 'member'));
    await assertFails(deleteDoc(doc(as(MEMBER_A), `churches/${A}/members/${uid}`)));
    await assertSucceeds(deleteDoc(doc(as(ADMIN_A), `churches/${A}/members/${uid}`)));
  });

  it('被移除的人，舊 token 什麼都讀不到', async () => {
    const uid = 'kicked';
    await seed(`churches/${A}/members/${uid}`, memberDoc(uid, 'member'));
    await assertSucceeds(getDoc(doc(as(uid), `churches/${A}/rosters/r-sunday`)));
    await deleteDoc(doc(as(ADMIN_A), `churches/${A}/members/${uid}`));
    await assertFails(getDoc(doc(as(uid), `churches/${A}/rosters/r-sunday`)));
  });
});

describe('服事表 (rosters)', () => {
  it('同工讀得到，也列得出來', async () => {
    await assertSucceeds(getDoc(doc(as(MEMBER_A), `churches/${A}/rosters/r-sunday`)));
    await assertSucceeds(getDocs(collection(as(MEMBER_A), `churches/${A}/rosters`)));
  });

  it('一般同工寫不了', async () => {
    await assertFails(setDoc(doc(as(MEMBER_A), `churches/${A}/rosters/m1`), { type: 'sunday' }));
  });

  it('編輯者只能寫自己牧區的聚會別', async () => {
    const db = as(EDITOR_A);
    await assertSucceeds(setDoc(doc(db, `churches/${A}/rosters/e1`), { type: 'sunday' }));
    await assertFails(setDoc(doc(db, `churches/${A}/rosters/e2`), { type: 'youth' }));
    await assertFails(updateDoc(doc(db, `churches/${A}/rosters/r-youth`), { note: 'x' }));
  });

  it('編輯者不能把別的牧區的服事表搬進自己的牧區', async () => {
    await seed(`churches/${A}/rosters/move-me`, { type: 'youth' });
    await assertFails(
      updateDoc(doc(as(EDITOR_A), `churches/${A}/rosters/move-me`), { type: 'sunday' }),
    );
  });

  it('管理員可以寫任何已設定的聚會別，但不能寫未知的', async () => {
    const db = as(ADMIN_A);
    await assertSucceeds(setDoc(doc(db, `churches/${A}/rosters/a1`), { type: 'youth' }));
    await assertFails(setDoc(doc(db, `churches/${A}/rosters/a2`), { type: 'kids' }));
    await assertFails(setDoc(doc(db, `churches/${A}/rosters/a3`), {}));
  });

  it('dateKey 格式錯就擋', async () => {
    const ref = doc(as(ADMIN_A), `churches/${A}/rosters/dk`);
    await assertSucceeds(setDoc(ref, { type: 'sunday', dateKey: '2030-01-05' }));
    await assertFails(setDoc(ref, { type: 'sunday', dateKey: '2030-13-05' }));
  });

  it('編輯者可以刪自己牧區的，不能刪別人的', async () => {
    await seed(`churches/${A}/rosters/del-sunday`, { type: 'sunday' });
    await seed(`churches/${A}/rosters/del-youth`, { type: 'youth' });
    await assertSucceeds(deleteDoc(doc(as(EDITOR_A), `churches/${A}/rosters/del-sunday`)));
    await assertFails(deleteDoc(doc(as(EDITOR_A), `churches/${A}/rosters/del-youth`)));
  });
});

describe('同工排序 (staff_orders)', () => {
  it('跟服事表同樣的牧區權限', async () => {
    await assertSucceeds(getDoc(doc(as(MEMBER_A), `churches/${A}/staff_orders/sunday`)));
    await assertSucceeds(
      setDoc(doc(as(EDITOR_A), `churches/${A}/staff_orders/sunday`), { order: ['x'] }),
    );
    await assertFails(
      setDoc(doc(as(EDITOR_A), `churches/${A}/staff_orders/youth`), { order: ['x'] }),
    );
    await assertFails(
      setDoc(doc(as(MEMBER_A), `churches/${A}/staff_orders/sunday`), { order: [] }),
    );
  });
});

describe('設定 (settings)', () => {
  it('同工讀得到，只有管理員寫得了', async () => {
    await assertSucceeds(getDoc(doc(as(MEMBER_A), `churches/${A}/settings/roster_templates`)));
    await assertFails(setDoc(doc(as(EDITOR_A), `churches/${A}/settings/roster_templates`), {}));
    await assertSucceeds(
      setDoc(doc(as(ADMIN_A), `churches/${A}/settings/roster_templates`), { sunday: ['領會', '司琴'] }),
    );
  });

  it('services 的 ids 只能增加，不能刪除整份', async () => {
    const ref = doc(as(ADMIN_A), `churches/${A}/settings/services`);
    await assertFails(setDoc(ref, services(['sunday'])));
    await assertSucceeds(setDoc(ref, services(['sunday', 'youth', 'prayer'])));
    await assertFails(deleteDoc(ref));
  });

  it('services 不能夾帶其他欄位', async () => {
    await assertFails(
      setDoc(doc(as(ADMIN_A), `churches/${A}/settings/services`), {
        ...services(['sunday', 'youth', 'prayer']),
        extra: true,
      }),
    );
  });
});

describe('教會連結 (settings/link)', () => {
  const link = { title: '主日奉獻', body: '線上奉獻', url: 'https://grace.example/give' };

  it('只有管理員能寫，同工讀得到，其他教會讀寫不了', async () => {
    const path = `churches/${A}/settings/link`;
    await assertSucceeds(setDoc(doc(as(ADMIN_A), path), link));
    await assertSucceeds(getDoc(doc(as(MEMBER_A), path)));
    await assertFails(setDoc(doc(as(MEMBER_A), path), link));
    await assertFails(setDoc(doc(as(EDITOR_A), path), link));
    await assertFails(getDoc(doc(as(ADMIN_B), path)));
    await assertFails(setDoc(doc(as(ADMIN_B), path), link));
    await assertSucceeds(deleteDoc(doc(as(ADMIN_A), path)));
  });

  // 標題 30 字、敘述 120 字由 App 把關；規則只擋超過上限 × 4 個 UTF-16 單位。
  it('標題必填、最多 120 個 UTF-16 單位，敘述最多 480，連結限 https', async () => {
    const ref = doc(as(ADMIN_A), `churches/${A}/settings/link`);
    await assertFails(setDoc(ref, { ...link, title: '' }));
    await assertSucceeds(setDoc(ref, { ...link, title: '👍🏽'.repeat(30), body: '👍🏽'.repeat(120) }), 'limits in 4-unit emoji');
    await assertSucceeds(setDoc(ref, { ...link, title: '字'.repeat(120), body: '字'.repeat(480) }));
    await assertFails(setDoc(ref, { ...link, title: '字'.repeat(121) }));
    await assertFails(setDoc(ref, { ...link, body: '字'.repeat(481) }));
    await assertFails(setDoc(ref, { ...link, title: '🙏'.repeat(61) }), '122 units');
    await assertFails(setDoc(ref, { ...link, url: 'http://grace.example' }));
    await assertFails(setDoc(ref, { ...link, url: 'javascript:alert(1)' }));
    await assertFails(setDoc(ref, { ...link, extra: true }));
    await assertSucceeds(setDoc(ref, { title: '只有標題', url: 'https://grace.example' }));
  });

  it('內容來源和抓取時間只能經由後端設定，改標題時保留', async () => {
    const path = `churches/${A}/settings/link`;
    await assertFails(setDoc(doc(as(ADMIN_A), path), { ...link, source: 'https://feed.example' }));
    await seed(path, { ...link, source: 'https://feed.example', fetchMinute: 270 });
    await assertSucceeds(setDoc(doc(as(ADMIN_A), path), { title: '新標題', body: '', url: link.url }, { merge: true }));
    await assertFails(updateDoc(doc(as(ADMIN_A), path), { fetchMinute: 300 }));
    await assertFails(setDoc(doc(as(ADMIN_A), path), link), '整份覆寫會拿掉來源');
    await seed(`linkSources/${A}`, { source: 'https://feed.example' });
    await assertFails(getDoc(doc(as(ADMIN_A), `linkSources/${A}`)));
    await assertFails(setDoc(doc(as(ADMIN_A), `linkSources/${A}`), { source: 'x' }));
  });

  it('後端寫的設定（行事曆、教會連結內容、外部通知）管理員也寫不了', async () => {
    for (const name of ['calendar', 'linkContent', 'webhook']) {
      await assertFails(setDoc(doc(as(ADMIN_A), `churches/${A}/settings/${name}`), { x: 1 }));
    }
    await seed(`churches/${A}/settings/linkContent`, { title: 'x' });
    await assertFails(deleteDoc(doc(as(ADMIN_A), `churches/${A}/settings/linkContent`)));
    await assertSucceeds(getDoc(doc(as(MEMBER_A), `churches/${A}/settings/linkContent`)));
  });
});

describe('外部通知 (webhook)', () => {
  it('管理員讀得到設定但不能寫；同工、其他教會讀不到', async () => {
    const path = `churches/${A}/settings/webhook`;
    await seed(path, { url: 'https://n8n.example/hook', events: { calendar: true, roster: false } });
    await assertSucceeds(getDoc(doc(as(ADMIN_A), path)));
    await assertFails(setDoc(doc(as(ADMIN_A), path), { url: 'https://evil.example' }));
    await assertFails(updateDoc(doc(as(ADMIN_A), path), { 'events.roster': true }));
    await assertFails(deleteDoc(doc(as(ADMIN_A), path)));
    await assertFails(getDoc(doc(as(MEMBER_A), path)));
    await assertFails(getDoc(doc(as(EDITOR_A), path)));
    await assertFails(getDoc(doc(as(ADMIN_B), path)));
  });

  it('密鑰任何 client 都不能讀寫', async () => {
    await seed(`webhookSecrets/${A}`, { secret: 'sealed' });
    for (const uid of [ADMIN_A, MEMBER_A, ADMIN_B]) {
      await assertFails(getDoc(doc(as(uid), `webhookSecrets/${A}`)));
      await assertFails(setDoc(doc(as(uid), `webhookSecrets/${A}`), { secret: 'x' }));
    }
    await assertFails(getDoc(doc(asAnon(), `webhookSecrets/${A}`)));
  });

  it('服事表異動的待送區任何 client 都不能讀寫', async () => {
    const path = `webhookOutbox/${A}/rosterChanges/ev1`;
    await seed(path, { date: '2026-10-04' });
    for (const uid of [ADMIN_A, EDITOR_A, ADMIN_B]) {
      await assertFails(getDoc(doc(as(uid), path)));
      await assertFails(getDocs(collection(as(uid), `webhookOutbox/${A}/rosterChanges`)));
      await assertFails(setDoc(doc(as(uid), `webhookOutbox/${A}/rosterChanges/fake`), { date: 'x' }));
    }
    await assertFails(getDocs(collectionGroup(as(ADMIN_A), 'rosterChanges')));
  });
});

describe('待認領的同工 (pendingMembers) 與索引', () => {
  it('管理員和 roster-editors 讀得到，只有管理員能刪；沒有人能建立或修改', async () => {
    const path = `churches/${A}/pendingMembers/old-1`;
    await seed(path, { name: '舊同工', email: 'old@example.com', role: 'staff' });
    await assertSucceeds(getDoc(doc(as(ADMIN_A), path)));
    await assertSucceeds(getDocs(collection(as(EDITOR_A), `churches/${A}/pendingMembers`)));
    await assertFails(getDoc(doc(as(MEMBER_A), path)));
    await assertFails(getDoc(doc(as(ADMIN_B), path)));
    await assertFails(setDoc(doc(as(ADMIN_A), `churches/${A}/pendingMembers/new`), { name: 'x' }));
    await assertFails(updateDoc(doc(as(ADMIN_A), path), { role: 'admin' }));
    await assertFails(deleteDoc(doc(as(EDITOR_A), path)));
    await assertFails(deleteDoc(doc(as(ADMIN_B), path)));
    await assertSucceeds(deleteDoc(doc(as(ADMIN_A), path)));
  });

  it('待認領索引任何 client 都不能讀寫', async () => {
    await seed('pendingIndex/abc', { churches: { [A]: 'old-1' } });
    for (const uid of [ADMIN_A, MEMBER_A, STRANGER]) {
      await assertFails(getDoc(doc(as(uid), 'pendingIndex/abc')));
      await assertFails(setDoc(doc(as(uid), 'pendingIndex/abc'), { churches: {} }));
    }
    await assertFails(getDocs(collection(as(ADMIN_A), 'pendingIndex')));
  });
});

describe('全域個資 (users)', () => {
  it('只有本人讀得到', async () => {
    await assertSucceeds(getDoc(doc(as(MEMBER_A), `users/${MEMBER_A}`)));
    await assertFails(getDoc(doc(as(ADMIN_A), `users/${MEMBER_A}`)));
    await assertFails(getDocs(collection(as(ADMIN_A), 'users')));
  });

  it('本人可以建立、更新允許的欄位', async () => {
    const ref = doc(as(STRANGER), `users/${STRANGER}`);
    await assertSucceeds(setDoc(ref, { name: '新人', email: 's@example.com', locale: 'zh-TW' }));
    await assertSucceeds(updateDoc(ref, { fcm: { 'device-1': 'token' } }));
    await assertSucceeds(updateDoc(ref, { name: '🙏'.repeat(40) }), '40 characters, 80 units');
    await assertSucceeds(updateDoc(ref, { name: 'A'.repeat(160) }), 'over 40 characters: the app’s to stop');
    await assertFails(updateDoc(ref, { name: 'A'.repeat(161) }));
    await assertFails(updateDoc(ref, { name: 40 }));
  });

  it('不能夾帶權限欄位、不能寫別人的、不能自己刪（帳號刪除走 Cloud Functions）', async () => {
    await assertFails(setDoc(doc(as(MEMBER_A), `users/${MEMBER_A}`), { name: '甲', role: 'admin' }));
    await assertFails(setDoc(doc(as(MEMBER_A), `users/${ADMIN_A}`), { name: '冒充' }));
    await assertFails(deleteDoc(doc(as(MEMBER_A), `users/${MEMBER_A}`)));
  });
});

describe('邀請 (invites)', () => {
  const inFuture = (days) => Timestamp.fromMillis(Date.now() + days * 86400e3);
  const invite = (cid, by, extra = {}) => ({
    cid,
    churchName: cid,
    expiresAt: inFuture(7),
    revoked: false,
    createdBy: by,
    createdAt: serverTimestamp(),
    ...extra,
  });

  it('管理員可以建立、列出、撤回自己教會的邀請', async () => {
    const db = as(ADMIN_A);
    await assertSucceeds(setDoc(doc(db, 'invites/AAAA1111'), invite(A, ADMIN_A)));
    await assertSucceeds(getDocs(query(collection(db, 'invites'), where('cid', '==', A))));
    await assertSucceeds(updateDoc(doc(db, 'invites/AAAA1111'), { revoked: true }));
  });

  it('撤回後不能恢復，也不能改成別的教會或延長期限', async () => {
    await seed('invites/AAAA2222', { ...invite(A, ADMIN_A), expiresAt: inFuture(7) });
    const db = as(ADMIN_A);
    await assertFails(updateDoc(doc(db, 'invites/AAAA2222'), { cid: B }));
    await assertFails(updateDoc(doc(db, 'invites/AAAA2222'), { expiresAt: inFuture(20) }));
    await assertSucceeds(updateDoc(doc(db, 'invites/AAAA2222'), { revoked: true }));
    await assertFails(updateDoc(doc(db, 'invites/AAAA2222'), { revoked: false }));
  });

  it('跨教會：B 的管理員不能建立、讀取、撤回 A 的邀請', async () => {
    await seed('invites/AAAA3333', invite(A, ADMIN_A));
    const db = as(ADMIN_B);
    await assertFails(setDoc(doc(db, 'invites/BBBB1111'), invite(A, ADMIN_B)));
    await assertFails(getDoc(doc(db, 'invites/AAAA3333')));
    await assertFails(getDocs(query(collection(db, 'invites'), where('cid', '==', A))));
    await assertFails(updateDoc(doc(db, 'invites/AAAA3333'), { revoked: true }));
  });

  it('一般同工、roster editor、陌生人都不能建立或讀取', async () => {
    await seed('invites/AAAA4444', invite(A, ADMIN_A));
    for (const uid of [MEMBER_A, EDITOR_A, STRANGER]) {
      await assertFails(setDoc(doc(as(uid), 'invites/CCCC1111'), invite(A, uid)));
      await assertFails(getDoc(doc(as(uid), 'invites/AAAA4444')));
    }
    await assertFails(getDoc(doc(asAnon(), 'invites/AAAA4444')));
  });

  it('不能建立超過 31 天、已撤回、冒名或格式不對的邀請', async () => {
    const db = as(ADMIN_A);
    await assertFails(setDoc(doc(db, 'invites/DDDD1111'), invite(A, ADMIN_A, { expiresAt: inFuture(40) })));
    await assertFails(setDoc(doc(db, 'invites/DDDD2222'), invite(A, ADMIN_A, { revoked: true })));
    await assertFails(setDoc(doc(db, 'invites/DDDD3333'), invite(A, MEMBER_A)));
    await assertFails(setDoc(doc(db, 'invites/short'), invite(A, ADMIN_A)));
    await assertFails(setDoc(doc(db, 'invites/DDDD4444'), invite(A, ADMIN_A, { role: 'admin' })));
  });

  it('停用中教會的管理員不能建立邀請', async () => {
    await assertFails(setDoc(doc(as(MEMBER_S), 'invites/SSSS1111'), invite(SUSPENDED, MEMBER_S)));
  });
});

describe('平台統計與名稱保留', () => {
  it('stats 只有營運者讀得到，沒有人能寫', async () => {
    await seed('stats/2026-10-01', { date: '2026-10-01', users: 3 });
    const op = testEnv.authenticatedContext('hans', { operator: true }).firestore();
    await assertSucceeds(getDoc(doc(op, 'stats/2026-10-01')));
    await assertFails(setDoc(doc(op, 'stats/2026-10-02'), { users: 1 }));
    await assertFails(getDoc(doc(as(ADMIN_A), 'stats/2026-10-01')));
  });

  it('雲端費用進度：誰都讀得到摘要（網站的支持頁不用登入），費用清單、每月與每筆收入只有後端碰', async () => {
    await seed('platform/funding', { month: '2026-10', target: 500, received: 120 });
    await seed('platform/fundingCosts', { items: [] });
    await seed('fundingMonths/2026-10', { received: 120, target: 500 });
    await seed('fundingPayments/apple_1', { amountTwd: 120 });
    await assertSucceeds(getDoc(doc(as(STRANGER), 'platform/funding')));
    await assertSucceeds(getDoc(doc(testEnv.unauthenticatedContext().firestore(), 'platform/funding')));
    await assertFails(setDoc(doc(testEnv.unauthenticatedContext().firestore(), 'platform/funding'), { received: 1 }));
    const op = testEnv.authenticatedContext('hans', { operator: true }).firestore();
    await assertFails(setDoc(doc(op, 'platform/funding'), { received: 99999 }));
    await assertFails(getDoc(doc(as(STRANGER), 'platform/fundingCosts')));
    await assertFails(getDoc(doc(as(STRANGER), 'fundingMonths/2026-10')));
    await assertFails(getDoc(doc(as(STRANGER), 'fundingPayments/apple_1')));
  });

  it('線上支持（藍新）的訂單和每小時計數只有後端碰：沒登入、同工、營運者都不能讀寫', async () => {
    await seed('newebpayOrders/20261007a1b2c3d4e5f6', { amount: 300, status: 'pending' });
    await seed('platform/newebpayRate', { hour: '2026-10-07T01', count: 1 });
    await seed('fundingPayments/newebpay_20261007a1b2c3d4e5f6', { amountTwd: 291 });
    const op = testEnv.authenticatedContext('hans', { operator: true }).firestore();
    for (const db of [testEnv.unauthenticatedContext().firestore(), as(STRANGER), as(ADMIN_A), op]) {
      await assertFails(getDoc(doc(db, 'newebpayOrders/20261007a1b2c3d4e5f6')));
      await assertFails(getDocs(collection(db, 'newebpayOrders')));
      await assertFails(setDoc(doc(db, 'newebpayOrders/20261007ffffffffffff'), { amount: 30, status: 'pending' }));
      await assertFails(setDoc(doc(db, 'newebpayOrders/20261007a1b2c3d4e5f6'), { amount: 300, status: 'paid' }));
      await assertFails(deleteDoc(doc(db, 'newebpayOrders/20261007a1b2c3d4e5f6')));
      await assertFails(getDoc(doc(db, 'platform/newebpayRate')));
      await assertFails(setDoc(doc(db, 'platform/newebpayRate'), { hour: '2026-10-07T01', count: 0 }));
      await assertFails(getDoc(doc(db, 'fundingPayments/newebpay_20261007a1b2c3d4e5f6')));
      await assertFails(setDoc(doc(db, 'fundingPayments/newebpay_x'), { amountTwd: 1 }));
    }
  });

  it('churchNames 不能讀寫（只有建立教會的 function 用）', async () => {
    await seed('churchNames/恩典堂', { cid: A });
    await assertFails(getDoc(doc(as(ADMIN_A), 'churchNames/恩典堂')));
    await assertFails(setDoc(doc(as(STRANGER), 'churchNames/搶註'), { cid: 'x' }));
  });
});

describe('行事曆的授權', () => {
  it('refresh token、OAuth state、快取都只有後端能碰（管理員也不行）', async () => {
    await seed(`calendarTokens/${A}`, { token: 'sealed' });
    await seed('calendarStates/abc', { cid: A });
    await seed(`calendarCache/${A}_2026-10`, { cid: A, events: [] });
    for (const path of [`calendarTokens/${A}`, 'calendarStates/abc', `calendarCache/${A}_2026-10`]) {
      await assertFails(getDoc(doc(as(ADMIN_A), path)));
      await assertFails(setDoc(doc(as(ADMIN_A), path), { x: 1 }));
    }
  });

  it('同工讀得到自己教會的行事曆設定，其他教會讀不到', async () => {
    await seed(`churches/${A}/settings/calendar`, { connected: true, calendarName: '教會' });
    await assertSucceeds(getDoc(doc(as(MEMBER_A), `churches/${A}/settings/calendar`)));
    await assertFails(getDoc(doc(as(ADMIN_B), `churches/${A}/settings/calendar`)));
  });
});
