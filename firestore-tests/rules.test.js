// firestore.rules 的安全規則測試，跑在 Firestore emulator 上。
//
//   cd firestore-tests && npm install && npm test
//
// 規則是唯一擋得住「繞過 App、直接用公開 web SDK 打 Firestore」的東西，
// 所以每一條授權判斷都要有對應的測試。
import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  arrayUnion,
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

// 預設值要跟 firebase.json 的 emulators.firestore.port 一致。`npm test` 走
// emulators:exec 會自己設好 FIRESTORE_EMULATOR_HOST，但手動起 emulator 再跑
// `node --test rules.test.js` 時只剩這個預設值，寫錯 port 會變成連不上的怪錯誤。
const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8181').split(':');

let testEnv;

const ADMIN = 'admin-1';
const MEMBER = 'member-1';
const OTHER = 'member-2';
// 編輯 group。刻意獨立於 OTHER：OTHER 的 role 會被「管理員可以調整別人的
// role」那條測試改掉，借用它會讓這裡的斷言隨執行順序漂移。
//
// 三個人的 role 全都不是 admin，而且 ROSTER_EDITOR 的 role 比 PLAIN_LEADER 還
// 低 —— 這是刻意的，用來釘住「權限看 group 不看 role」。
const ROSTER_EDITOR = 'roster-editor-1'; // 三個牧區都有
// 只屬於青崇與兒主的編輯者。整組「編輯權不等於全部聚會別」的斷言靠他。
const YOUTH_EDITOR = 'youth-editor-1';
// 有 roster-editors 但一個牧區都沒有 —— 也是所有既有帳號（沒有 zoneTypes
// 欄位）的形狀，用來釘住「沒有牧區就什麼都改不動」。
const ZONELESS_EDITOR = 'zoneless-editor-1';
const CALENDAR_EDITOR = 'calendar-editor-1';
const PLAIN_LEADER = 'plain-leader-1'; // 身分是小組長，但沒有任何 group
const GRANTED = 'granted-1'; // 已經有 group，用來測收回
const DELETED = 'deleted-1'; // 有 Auth token，但 users 文件已被管理員刪掉
const LEGACY = 'legacy-1'; // 舊資料：users 文件存在但沒有 role 欄位

function userDoc(id, role, groups, zoneTypes) {
  const document = {
    id,
    name: `姓名-${id}`,
    email: `${id}@example.com`,
    username: id,
    role,
    zones: [],
  };
  // 不傳就完全不寫這個欄位 —— 既有使用者全都是這個形狀，規則必須撐得住。
  if (groups !== undefined) document.groups = groups;
  // zones 攤平出來的投影（見 User.zoneTypes）：規則語言沒有迴圈，讀不出 zones
  // 那個 map list 裡的 serviceType，所以牧區的判斷一律看這個欄位。
  if (zoneTypes !== undefined) document.zoneTypes = zoneTypes;
  return document;
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

  // 一定要先清空：`npm test` 每次都是全新 emulator 所以看不出來，但只要對著
  // 長時間開著的 emulator 重跑，上一輪殘留的 users/new-staff 之類文件就會讓
  // 「建立帳號」的測試變成在打 update 規則，create 那幾條就悄悄失去偵測力。
  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', ADMIN), userDoc(ADMIN, 'admin'));
    await setDoc(doc(db, 'users', MEMBER), userDoc(MEMBER, 'member'));
    await setDoc(doc(db, 'users', OTHER), userDoc(OTHER, 'leader'));
    await setDoc(
      doc(db, 'users', ROSTER_EDITOR),
      userDoc(ROSTER_EDITOR, 'staff', ['roster-editors'], [
        'sundayService',
        'youth',
        'children',
      ]),
    );
    await setDoc(
      doc(db, 'users', YOUTH_EDITOR),
      userDoc(YOUTH_EDITOR, 'staff', ['roster-editors'], ['youth', 'children']),
    );
    // zoneTypes 欄位完全不存在：既有帳號的形狀。
    await setDoc(
      doc(db, 'users', ZONELESS_EDITOR),
      userDoc(ZONELESS_EDITOR, 'staff', ['roster-editors']),
    );
    await setDoc(
      doc(db, 'users', CALENDAR_EDITOR),
      userDoc(CALENDAR_EDITOR, 'staff', ['calendar-editors']),
    );
    await setDoc(
      doc(db, 'users', PLAIN_LEADER),
      userDoc(PLAIN_LEADER, 'leader'),
    );
    // 「管理員可以把 group 收回成空陣列」要更新的對象。在這裡種下去而不是靠
    // 前一條測試留下來的 —— clearFirestore() 只在 before() 跑一次，相依前一條
    // 的話單獨執行那一條會 NOT_FOUND，看起來像 rules 壞了。
    await setDoc(
      doc(db, 'users', GRANTED),
      userDoc(GRANTED, 'member', ['calendar-editors']),
    );
    // 注意：DELETED 刻意沒有 users 文件。
    const legacy = userDoc(LEGACY, 'member');
    delete legacy.role;
    await setDoc(doc(db, 'users', LEGACY), legacy);
    // users 底下不該有任何子集合可讀寫，靠最後的 default deny 擋。
    await setDoc(doc(db, 'users', MEMBER, 'private', 'secret'), { pin: '1234' });
    await setDoc(doc(db, 'rosters', 'r1'), {
      serviceName: '主日崇拜',
      type: 'sundayService',
    });
    // r2 專門給 list 查詢用：r1 會被「管理員可以改服事表」覆寫掉 date 欄位。
    await setDoc(doc(db, 'rosters', 'r2'), {
      serviceName: '青年崇拜',
      type: 'youth',
      date: Timestamp.fromDate(new Date('2030-01-05T00:00:00Z')),
    });
    // 兒主那本，專門留給青崇編輯者寫（不跟 r1/r2 的斷言互相覆寫）。
    await setDoc(doc(db, 'rosters', 'r3'), {
      serviceName: '兒童主日學',
      type: 'children',
    });
    // 沒有 type 欄位的舊資料：規則不該爆掉，而是只有 admin 動得了。
    await setDoc(doc(db, 'rosters', 'legacy'), { serviceName: '沒有 type 的舊資料' });
    // 刪除測試專用，一本一條，避免互相依賴執行順序。
    await setDoc(doc(db, 'rosters', 'doomed-youth'), {
      serviceName: '青年崇拜',
      type: 'youth',
    });
    await setDoc(doc(db, 'rosters', 'doomed-sunday'), {
      serviceName: '主日崇拜',
      type: 'sundayService',
    });
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
const asRosterEditor = () =>
  testEnv.authenticatedContext(ROSTER_EDITOR).firestore();
const asYouthEditor = () =>
  testEnv.authenticatedContext(YOUTH_EDITOR).firestore();
const asZonelessEditor = () =>
  testEnv.authenticatedContext(ZONELESS_EDITOR).firestore();
const asCalendarEditor = () =>
  testEnv.authenticatedContext(CALENDAR_EDITOR).firestore();
const asPlainLeader = () =>
  testEnv.authenticatedContext(PLAIN_LEADER).firestore();
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

  it('未登入讀不到 settings', async () => {
    await assertFails(getDoc(doc(asAnon(), 'settings', 'roster_templates')));
  });

  // App 真正的讀取路徑是 collection query，不是單筆 getDoc
  // （FirestoreRosterRepository.getUpcomingRosters）。只測 getDoc 的話，
  // 把 rules 的 `allow read` 收窄成 `allow get` 也不會被抓到，但整個服事表
  // 畫面會直接 permission-denied。
  it('一般同工可以用 App 的查詢條件列出服事表', async () => {
    const snapshot = await assertSucceeds(
      getDocs(
        query(
          collection(asMember(), 'rosters'),
          where('date', '>=', Timestamp.fromDate(new Date('2020-01-01Z'))),
          orderBy('date'),
        ),
      ),
    );
    // 真的有讀到資料，而不是「查詢通過但結果為空」。
    assert.ok(snapshot.size >= 1, '應該至少讀到一筆有 date 的 roster');
  });

  it('被刪掉的帳號不能列出服事表', async () => {
    await assertFails(getDocs(collection(asDeleted(), 'rosters')));
  });

  it('未登入不能列出服事表', async () => {
    await assertFails(getDocs(collection(asAnon(), 'rosters')));
  });
});

describe('rosters / settings 寫入', () => {
  it('一般同工不能改服事表', async () => {
    await assertFails(
      setDoc(doc(asMember(), 'rosters', 'r1'), {
        serviceName: '亂改',
        type: 'sundayService',
      }),
    );
  });

  it('管理員可以改服事表', async () => {
    await assertSucceeds(
      setDoc(doc(asAdmin(), 'rosters', 'r1'), {
        serviceName: '主日崇拜',
        type: 'sundayService',
      }),
    );
  });

  // role 只有 staff，靠 group 放行。牧區涵蓋主日，所以動得了 r1。
  it('roster-editors 可以改自己牧區的服事表', async () => {
    await assertSucceeds(
      setDoc(doc(asRosterEditor(), 'rosters', 'r1'), {
        serviceName: '主日崇拜',
        type: 'sundayService',
      }),
    );
  });

  // 反過來：身分是小組長但沒有 group，一樣不能改。少了這條，把 inGroup() 誤寫
  // 回看 role 也不會有任何測試變紅。
  it('沒有 group 的小組長不能改服事表', async () => {
    await assertFails(
      setDoc(doc(asPlainLeader(), 'rosters', 'r1'), {
        serviceName: '亂改',
        type: 'sundayService',
      }),
    );
  });

  // 兩個 group 正交：行事曆編輯者碰不到服事表。
  it('calendar-editors 不能改服事表', async () => {
    await assertFails(
      setDoc(doc(asCalendarEditor(), 'rosters', 'r1'), {
        serviceName: '亂改',
        type: 'sundayService',
      }),
    );
  });

  it('一般同工不能改 settings', async () => {
    await assertFails(
      setDoc(doc(asMember(), 'settings', 'roster_templates'), { x: 1 }),
    );
  });

  // 範本是所有服事表的骨架，改壞會影響到每一個人，所以留在 admin。
  it('roster-editors 不能改 settings', async () => {
    await assertFails(
      setDoc(doc(asRosterEditor(), 'settings', 'roster_templates'), { x: 1 }),
    );
  });

  it('被刪掉的帳號不能改服事表', async () => {
    await assertFails(
      setDoc(doc(asDeleted(), 'rosters', 'r1'), {
        serviceName: '亂改',
        type: 'sundayService',
      }),
    );
  });
});

// 編輯權（group）與牧區（zoneTypes）是兩個軸：group 說「可以改服事表」，
// zoneTypes 說「可以改哪一本」。兩個都要過。
//
// 這一組釘住的是實際發生過的問題：只屬於青崇與兒主的人被加進 roster-editors
// 之後，連主日那本都動得了。
describe('rosters 的牧區範圍', () => {
  it('青崇編輯者改得動自己牧區的服事表', async () => {
    await assertSucceeds(
      setDoc(doc(asYouthEditor(), 'rosters', 'r3'), {
        serviceName: '兒童主日學',
        type: 'children',
      }),
    );
  });

  it('青崇編輯者改不動主日的服事表', async () => {
    await assertFails(
      setDoc(doc(asYouthEditor(), 'rosters', 'r1'), {
        serviceName: '亂改',
        type: 'sundayService',
      }),
    );
  });

  // 只檢查寫進去的 type 是不夠的：那樣可以把主日那本「改標成」青崇，一次寫入
  // 就把它整本吃下來。舊的 type 也要在自己的牧區內。
  it('青崇編輯者不能把主日那本改標成青崇', async () => {
    await assertFails(
      setDoc(doc(asYouthEditor(), 'rosters', 'r1'), {
        serviceName: '偷天換日',
        type: 'youth',
      }),
    );
  });

  it('青崇編輯者建得出新的青崇服事表', async () => {
    await assertSucceeds(
      setDoc(doc(asYouthEditor(), 'rosters', 'new-youth'), {
        serviceName: '青年崇拜',
        type: 'youth',
      }),
    );
  });

  it('青崇編輯者建不出新的主日服事表', async () => {
    await assertFails(
      setDoc(doc(asYouthEditor(), 'rosters', 'new-sunday'), {
        serviceName: '主日崇拜',
        type: 'sundayService',
      }),
    );
  });

  it('青崇編輯者刪得掉自己牧區的服事表', async () => {
    await assertSucceeds(deleteDoc(doc(asYouthEditor(), 'rosters', 'doomed-youth')));
  });

  it('青崇編輯者刪不掉主日的服事表', async () => {
    await assertFails(deleteDoc(doc(asYouthEditor(), 'rosters', 'doomed-sunday')));
  });

  // 既有帳號全都是這個形狀（沒有 zoneTypes 欄位）。`data.get('zoneTypes', [])`
  // 讓它們讀成「沒有牧區」而不是規則報錯，結果是什麼都改不動 —— 所以上線前要
  // 先跑 scripts/backfill-user-zone-types.mjs 把欄位補上。
  it('沒有牧區的編輯者什麼都改不動', async () => {
    await assertFails(
      setDoc(doc(asZonelessEditor(), 'rosters', 'r3'), {
        serviceName: '亂改',
        type: 'children',
      }),
    );
  });

  it('編輯者動不了沒有 type 的舊資料', async () => {
    await assertFails(
      setDoc(doc(asRosterEditor(), 'rosters', 'legacy'), { serviceName: '亂改' }),
    );
  });

  // admin 是 root：沒有 type 的舊資料要有人修得動，否則就沒人修得動了。
  it('管理員動得了沒有 type 的舊資料', async () => {
    await assertSucceeds(
      setDoc(doc(asAdmin(), 'rosters', 'legacy'), { serviceName: '補上 type', type: 'youth' }),
    );
  });

  // 一個牧區都沒有的 admin 照樣是 root。
  it('管理員不必有牧區也改得動全部', async () => {
    await assertSucceeds(
      setDoc(doc(asAdmin(), 'rosters', 'r3'), {
        serviceName: '兒童主日學',
        type: 'children',
      }),
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

  it('未登入讀不到任何人的資料', async () => {
    await assertFails(getDoc(doc(asAnon(), 'users', MEMBER)));
  });

  // 以下四條是「users 讀取收窄」真正的重點。收窄前後 getDoc 自己那筆都會成功，
  // 差別只出現在 list：只測 getDoc 的話，有人加一條 `allow list: if isActiveUser()`
  // 就等於把全體同工的 email 與 fcm token 重新對所有登入者開放，而測試全綠。
  it('管理員可以列出整個 users collection（後台人員選擇器走這條）', async () => {
    const snapshot = await assertSucceeds(
      getDocs(collection(asAdmin(), 'users')),
    );
    assert.ok(snapshot.size >= 3, '管理員應該讀得到所有使用者');
  });

  // 服事表的人員選擇器走 getUsers()，所以 roster-editors 必須列得到整個
  // collection。代價是他也看得到所有人的 email 與 fcm token —— Firestore rules
  // 沒有欄位級讀取限制，開這個 group 就是連帶開這些。
  it('roster-editors 可以列出整個 users collection（服事表人員選擇器走這條）', async () => {
    const snapshot = await assertSucceeds(
      getDocs(collection(asRosterEditor(), 'users')),
    );
    assert.ok(snapshot.size >= 3, 'roster-editors 應該讀得到所有使用者');
  });

  it('一般同工不能列出 users collection', async () => {
    await assertFails(getDocs(collection(asMember(), 'users')));
  });

  // 只有行事曆權限的人沒有理由讀通訊錄，所以 users 讀取綁的是 roster-editors
  // 而不是「任何 group」。
  it('calendar-editors 不能列出 users collection', async () => {
    await assertFails(getDocs(collection(asCalendarEditor(), 'users')));
  });

  // 加上 where 條件也不行：rules 不是過濾器，list 一律整批拒絕。
  it('一般同工不能用 where 條件迂迴列出 users', async () => {
    await assertFails(
      getDocs(query(collection(asMember(), 'users'), where('id', '==', MEMBER))),
    );
    await assertFails(
      getDocs(
        query(collection(asMember(), 'users'), where('role', '==', 'admin')),
      ),
    );
  });

  it('被刪掉的帳號不能列出 users collection', async () => {
    await assertFails(getDocs(collection(asDeleted(), 'users')));
  });

  // users/{uid} 的 match 不涵蓋子集合，只靠最後的 default deny 擋。
  it('users 底下的子集合連本人與管理員都讀不到', async () => {
    await assertFails(
      getDoc(doc(asMember(), 'users', MEMBER, 'private', 'secret')),
    );
    await assertFails(
      getDoc(doc(asAdmin(), 'users', MEMBER, 'private', 'secret')),
    );
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

  // group 模型最關鍵的一條：能自己加 group 的話，整個授權模型就等於不存在。
  it('不能把自己加進任何 group', async () => {
    await assertFails(
      updateDoc(doc(asMember(), 'users', MEMBER), {
        groups: ['roster-editors'],
      }),
    );
  });

  // 已經在某個 group 裡的人也不能自己再多拿一個。
  it('group 成員不能自己再加別的 group', async () => {
    await assertFails(
      updateDoc(doc(asCalendarEditor(), 'users', CALENDAR_EDITOR), {
        groups: ['calendar-editors', 'roster-editors'],
      }),
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

  // selfUpdateOnlyTouches 的重點在 hasOnly，不在「有沒有碰到 role」。
  // 只寫 role 的攻擊上面已經測了，但那條測試擋不住 hasOnly 被寫成 hasAny：
  // hasAny 之下「只寫 role」仍然會被拒絕（測試照樣綠），而「fcm + role 一起寫」
  // 就會過關，一次請求把自己升成 admin。這幾條就是補那個洞。
  it('不能把 role 夾帶在合法欄位裡一起寫入', async () => {
    await assertFails(
      setDoc(
        doc(asMember(), 'users', MEMBER),
        { fcm: { webTokens: ['token-evil'] }, role: 'admin' },
        { merge: true },
      ),
    );
    await assertFails(
      setDoc(
        doc(asMember(), 'users', MEMBER),
        { notificationPrefs: { weeklyRosterReminder: true }, role: 'admin' },
        { merge: true },
      ),
    );
  });

  it('不能把姓名夾帶在合法欄位裡一起寫入', async () => {
    await assertFails(
      updateDoc(doc(asMember(), 'users', MEMBER), {
        fcm: { webTokens: ['token-evil'] },
        name: '自己改的',
      }),
    );
  });

  // 同時寫兩個合法欄位要放行：App 的通知開關流程就是先寫 fcm 再寫
  // notificationPrefs，若哪天合併成一次寫入也不該被擋。
  it('可以一次寫入 fcm 與 notificationPrefs', async () => {
    await assertSucceeds(
      setDoc(
        doc(asMember(), 'users', MEMBER),
        {
          fcm: { webTokens: ['token-both'] },
          notificationPrefs: { weeklyRosterReminder: false },
        },
        { merge: true },
      ),
    );
  });

  // PushNotificationService._saveToken 的實際寫法：arrayUnion + serverTimestamp。
  // 上面那條用的是普通陣列，擋不住「未來加了 fcm 欄位型別驗證卻沒考慮
  // sentinel 值」而讓真正的 App 寫入失敗。
  it('可以用 App 實際的 arrayUnion + serverTimestamp 寫法存 fcm token', async () => {
    await assertSucceeds(
      setDoc(
        doc(asMember(), 'users', MEMBER),
        {
          fcm: {
            webTokens: arrayUnion('token-real'),
            lastUpdatedAt: serverTimestamp(),
          },
        },
        { merge: true },
      ),
    );
  });

  // 管理員自己也會跑 _saveToken。這條走的是 update 規則的 isAdmin 分支，
  // 而該分支帶著 hasValidRole()，所以要確認 merge 寫入不會被自己的驗證擋掉。
  it('管理員也可以寫自己的 fcm token', async () => {
    await assertSucceeds(
      setDoc(
        doc(asAdmin(), 'users', ADMIN),
        {
          fcm: {
            webTokens: arrayUnion('admin-token'),
            lastUpdatedAt: serverTimestamp(),
          },
        },
        { merge: true },
      ),
    );
  });

  it('不能整份覆寫自己的文件（set 不帶 merge）', async () => {
    await assertFails(
      setDoc(doc(asMember(), 'users', MEMBER), userDoc(MEMBER, 'admin')),
    );
  });

  // 被刪掉的帳號對自己的文件做 set(merge) 會落在 create 規則（文件不存在），
  // 而 create 只開給管理員 —— 所以無法自己把自己救回來重新取得讀取權。
  it('被刪掉的帳號不能用 set(merge) 把自己的文件寫回來', async () => {
    await assertFails(
      setDoc(
        doc(asDeleted(), 'users', DELETED),
        { fcm: { webTokens: ['revive'] } },
        { merge: true },
      ),
    );
    await assertFails(
      setDoc(doc(asDeleted(), 'users', DELETED), userDoc(DELETED, 'member')),
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

  it('管理員可以授予 group', async () => {
    await assertSucceeds(
      setDoc(
        doc(asAdmin(), 'users', 'granted-new'),
        userDoc('granted-new', 'member', ['calendar-editors']),
      ),
    );
  });

  // 名字打錯會變成一個看起來像授權、實際上什麼都不對應的欄位。
  it('管理員不能寫入不存在的 group 名稱', async () => {
    await assertFails(
      setDoc(
        doc(asAdmin(), 'users', 'granted-bogus'),
        userDoc('granted-bogus', 'member', ['calendar-editor']),
      ),
    );
  });

  it('管理員可以授予牧區', async () => {
    await assertSucceeds(
      setDoc(
        doc(asAdmin(), 'users', 'zoned-new'),
        userDoc('zoned-new', 'member', ['roster-editors'], ['youth']),
      ),
    );
  });

  // 同 group：打錯的聚會別會變成一個看起來像授權、實際上對不到任何服事表的欄位。
  it('管理員不能寫入不存在的聚會別', async () => {
    await assertFails(
      setDoc(
        doc(asAdmin(), 'users', 'zoned-bogus'),
        userDoc('zoned-bogus', 'member', ['roster-editors'], ['sunday']),
      ),
    );
  });

  it('管理員可以把 group 收回成空陣列', async () => {
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'users', GRANTED), { groups: [] }),
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

  // 自己準備要被刪的文件，不要依賴上面「管理員可以用合法 role 建立帳號」
  // 留下來的 new-staff：那種隱性順序相依會讓單獨跑一條測試時整個爆掉。
  it('管理員可以刪帳號', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), 'users', 'doomed-1'),
        userDoc('doomed-1', 'member'),
      );
    });
    await assertSucceeds(deleteDoc(doc(asAdmin(), 'users', 'doomed-1')));
  });

  // 舊資料可能沒有 role 欄位。hasValidRole() 讀的是「寫入後的完整文件」，
  // 所以只改 name 會因為 role 不存在而被擋；管理員必須順手補上 role。
  // 後台的 updateUser 走的是 user.toJson() 全欄位覆寫，一定帶 role，所以
  // 正常操作不受影響 —— 這條是把這個邊界行為釘住，避免有人誤判成 rules 壞了。
  it('沒有 role 欄位的舊資料：只改其他欄位會被擋，補上 role 才能改', async () => {
    await assertFails(
      updateDoc(doc(asAdmin(), 'users', LEGACY), { name: '只改名字' }),
    );
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'users', LEGACY), {
        name: '補上 role',
        role: 'member',
      }),
    );
  });

  // role 欄位不能被刪掉：刪掉之後 hasValidRole() 會直接評估失敗，
  // 該使用者的文件就再也不能用「只改一半欄位」的方式維護了。
  it('管理員不能刪掉 role 欄位', async () => {
    await assertFails(
      updateDoc(doc(asAdmin(), 'users', OTHER), { role: deleteField() }),
    );
  });
});

describe('預設拒絕', () => {
  it('未定義的 collection 一律拒絕，連管理員也是', async () => {
    await assertFails(getDoc(doc(asAdmin(), 'anything', 'x')));
    await assertFails(setDoc(doc(asAdmin(), 'anything', 'x'), { a: 1 }));
  });
});
