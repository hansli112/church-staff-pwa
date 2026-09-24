// Policy suite for worker/authorize.js — who may do what, asked the way the
// handlers ask it. The handler tests keep only a case or two proving each
// route actually asks; everything about the answer lives here.

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { authorize } from '../worker/authorize.js';
import {
  ADMIN_NAME,
  ADMIN_UID,
  CALENDAR_EDITOR_NAME,
  CALENDAR_EDITOR_UID,
  MEMBER_UID,
  ROSTER_EDITOR_UID,
  fakeFetch,
  idToken,
  muteConsoleError,
  request,
  testEnv,
} from './helpers.js';

const CALENDAR = { edit: 'calendar' };
const ROSTER = { edit: 'roster' };

const YOUTH_EDITOR_UID = 'youth-editor-uid';
/// 有青崇的牧區，卻不在 roster-editors：牧區本身不是授權。
const ZONE_ONLY_UID = 'zone-only-uid';

/// helpers.js 的預設名單，加上兩個跟牧區有關的人。admin 刻意不給 zoneTypes：
/// firestore.rules 的 canEditRosterType() 說 admin 不必持有牧區。
const USERS = {
  [ADMIN_UID]: { role: 'admin', name: ADMIN_NAME },
  [MEMBER_UID]: { role: 'member', name: '路人' },
  [CALENDAR_EDITOR_UID]: {
    role: 'staff',
    groups: ['calendar-editors'],
    name: CALENDAR_EDITOR_NAME,
  },
  [ROSTER_EDITOR_UID]: { role: 'staff', groups: ['roster-editors'], name: '服事表同工' },
  [YOUTH_EDITOR_UID]: {
    role: 'staff',
    groups: ['roster-editors'],
    zoneTypes: ['youth'],
    name: '青崇同工',
  },
  [ZONE_ONLY_UID]: { role: 'staff', groups: [], zoneTypes: ['youth'], name: '青崇會友' },
};

/// 服事表分兩段：先過 group，再用 forRosterType 問哪一個崇拜。回傳的是 token。
async function rosterTokenAs(uid, type, options) {
  return (await authorizeAs(uid, ROSTER, options)).forRosterType(type);
}

async function authorizeAs(uid, action, { users = USERS, fetchImpl, env } = {}) {
  return authorize(
    request('POST', { token: idToken(uid) }),
    env ?? (await testEnv()),
    action,
    fetchImpl ?? fakeFetch({ users }),
  );
}

describe('authorize — 誰在呼叫', () => {
  test('沒有 Authorization header 是 401，而且不查 Firestore', async () => {
    const fetchImpl = fakeFetch();
    await assert.rejects(
      authorize(request('POST', { token: null }), await testEnv(), CALENDAR, fetchImpl),
      { status: 401, message: '請先登入' },
    );
    assert.equal(fetchImpl.calls.length, 0);
  });

  test('空白的 bearer token 是 401', async () => {
    await assert.rejects(
      authorize(request('POST', { token: '  ' }), await testEnv(), CALENDAR, fakeFetch()),
      { status: 401 },
    );
  });

  // 從 app 移除的人還拿著有效的 Firebase token，但 users/{uid} 已經不在了。
  test('登入了卻沒有使用者文件是 403', async () => {
    await assert.rejects(authorizeAs('ghost', CALENDAR), {
      status: 403,
      message: '這個帳號沒有權限',
    });
  });

  test('Firestore 拒絕 token 時請人重新登入', async () => {
    const fetchImpl = async () => new Response('{}', { status: 401 });
    await assert.rejects(authorizeAs(ADMIN_UID, CALENDAR, { fetchImpl }), {
      status: 401,
      message: '登入狀態已過期，請重新登入',
    });
  });

  test('Firestore 掛了是 502，請人稍後再試', async () => {
    const restore = muteConsoleError();
    try {
      const fetchImpl = async () => new Response('boom', { status: 500 });
      await assert.rejects(authorizeAs(ADMIN_UID, CALENDAR, { fetchImpl }), { status: 502 });
    } finally {
      restore();
    }
  });

  test('沒設 project id 時一律拒絕', async () => {
    const restore = muteConsoleError();
    try {
      const env = await testEnv({ FIREBASE_PROJECT_ID: '' });
      await assert.rejects(authorizeAs(ADMIN_UID, CALENDAR, { env }), { status: 500 });
    } finally {
      restore();
    }
  });

  test('通過時回傳 uid、名字與呼叫者自己的 token', async () => {
    assert.deepEqual(await authorizeAs(ADMIN_UID, CALENDAR), {
      uid: ADMIN_UID,
      name: ADMIN_NAME,
      token: idToken(ADMIN_UID),
    });
  });

  // 沒有 name 的舊帳號照樣能用 —— 名字只影響通知長什麼樣。
  test('沒有名字或名字只有空白時 name 是 null', async () => {
    for (const profile of [{ role: 'admin' }, { role: 'admin', name: '   ' }]) {
      const result = await authorizeAs(ADMIN_UID, CALENDAR, { users: { [ADMIN_UID]: profile } });
      assert.equal(result.name, null);
    }
  });

  // 遮罩少一個欄位就等於沒讀：名字拿不到通知就是匿名的，牧區拿不到就誰都過不了。
  test('向 Firestore 要的欄位包含 name 與 zoneTypes', async () => {
    const fetchImpl = fakeFetch({ users: USERS });
    await authorizeAs(ADMIN_UID, CALENDAR, { fetchImpl });
    const [lookup] = fetchImpl.calls;
    assert.match(lookup.url, /mask\.fieldPaths=name/);
    assert.match(lookup.url, /mask\.fieldPaths=zoneTypes/);
  });

  test('不認得的 action 是程式錯誤，不是 403', async () => {
    await assert.rejects(authorizeAs(ADMIN_UID, { edit: 'settings' }), (error) => {
      assert.equal(error.status, undefined);
      return true;
    });
  });
});

describe('authorize — 編輯行事曆', () => {
  test('admin 可以（admin 是 root）', async () => {
    assert.equal((await authorizeAs(ADMIN_UID, CALENDAR)).uid, ADMIN_UID);
  });

  // 權限看 group，不看 role：這個人的 role 只是 staff。
  test('calendar-editors 可以，不管 role 是什麼', async () => {
    const result = await authorizeAs(CALENDAR_EDITOR_UID, CALENDAR);
    assert.deepEqual(result, {
      uid: CALENDAR_EDITOR_UID,
      name: CALENDAR_EDITOR_NAME,
      token: idToken(CALENDAR_EDITOR_UID),
    });
  });

  // 兩個 group 正交：服事表編輯者碰不到行事曆。
  test('只有 roster-editors 的人被擋，訊息講的是行事曆', async () => {
    await assert.rejects(authorizeAs(ROSTER_EDITOR_UID, CALENDAR), {
      status: 403,
      message: '沒有編輯行事曆的權限',
    });
  });

  test('一般會眾被擋', async () => {
    await assert.rejects(authorizeAs(MEMBER_UID, CALENDAR), {
      status: 403,
      message: '沒有編輯行事曆的權限',
    });
  });

  const shapes = [
    // 沒有 groups 欄位的舊帳號 —— 全部既有使用者都是這個形狀。
    ['沒有 groups 欄位', { role: 'leader' }],
    // Firestore 對空陣列回的是 { arrayValue: {} }，沒有 values。
    ['groups 是空陣列', { role: 'staff', groups: [] }],
    // 名字打錯不能當成某種權限放行。
    ['group 名字打錯', { role: 'staff', groups: ['calendar-editor'] }],
    ['文件一個欄位都沒有', null],
  ];
  for (const [name, profile] of shapes) {
    test(`${name}時被擋`, async () => {
      await assert.rejects(
        authorizeAs(MEMBER_UID, CALENDAR, { users: { [MEMBER_UID]: profile } }),
        { status: 403 },
      );
    });
  }
});

describe('authorize — 編輯服事表', () => {
  for (const type of ['sundayService', 'youth', 'children']) {
    test(`admin 不必持有牧區也能編 ${type}`, async () => {
      assert.equal(await rosterTokenAs(ADMIN_UID, type), idToken(ADMIN_UID));
    });
  }

  test('有編輯權又有那個牧區的可以，拿到的是自己的 token', async () => {
    assert.equal(await rosterTokenAs(YOUTH_EDITOR_UID, 'youth'), idToken(YOUTH_EDITOR_UID));
  });

  // token 只能從 forRosterType 拿：handler 要讀 Firestore 就一定得先問過牧區。
  test('通過 group 只拿到 uid 與名字，沒有 token', async () => {
    const permit = await authorizeAs(YOUTH_EDITOR_UID, ROSTER);
    assert.equal(permit.uid, YOUTH_EDITOR_UID);
    assert.equal(permit.name, '青崇同工');
    assert.equal('token' in permit, false);
  });

  // group 說「可以改服事表」，zone 說「哪一個」—— 跟 canEditRosterType() 同一套。
  test('有編輯權但不是那個牧區的被擋，訊息講的是這個崇拜', async () => {
    await assert.rejects(rosterTokenAs(YOUTH_EDITOR_UID, 'sundayService'), {
      status: 403,
      message: '沒有編輯這個崇拜服事表的權限',
    });
  });

  test('zoneTypes 欄位不存在時當作沒有牧區', async () => {
    await assert.rejects(rosterTokenAs(ROSTER_EDITOR_UID, 'youth'), {
      status: 403,
      message: '沒有編輯這個崇拜服事表的權限',
    });
  });

  test('zoneTypes 是空陣列時當作沒有牧區', async () => {
    const users = { [YOUTH_EDITOR_UID]: { ...USERS[YOUTH_EDITOR_UID], zoneTypes: [] } };
    await assert.rejects(rosterTokenAs(YOUTH_EDITOR_UID, 'youth', { users }), { status: 403 });
  });

  // group 在讀 body 之前就擋：不在 roster-editors 的人連哪一個崇拜都不必問。
  test('有牧區但不在 roster-editors 的被擋，訊息講的是服事表', async () => {
    await assert.rejects(authorizeAs(ZONE_ONLY_UID, ROSTER), {
      status: 403,
      message: '沒有編輯服事表的權限',
    });
  });

  test('只有 calendar-editors 的人被擋', async () => {
    await assert.rejects(authorizeAs(CALENDAR_EDITOR_UID, ROSTER), {
      status: 403,
      message: '沒有編輯服事表的權限',
    });
  });

  test('一般會眾被擋', async () => {
    await assert.rejects(authorizeAs(MEMBER_UID, ROSTER), { status: 403 });
  });

  // 不存在的崇拜誰都不能編，admin 也一樣；問牧區不會再查一次 Firestore。
  for (const [name, type] of [
    ['不認得的崇拜', 'wedding'],
    ['沒有 type', undefined],
    ['type 不是字串', 7],
  ]) {
    test(`${name}是 400，連 admin 也一樣`, async () => {
      const fetchImpl = fakeFetch({ users: USERS });
      const permit = await authorizeAs(ADMIN_UID, ROSTER, { fetchImpl });
      const lookups = fetchImpl.calls.length;
      assert.throws(() => permit.forRosterType(type), {
        status: 400,
        message: '不知道這是哪一個崇拜的服事表',
      });
      assert.equal(fetchImpl.calls.length, lookups);
    });
  }

  // 沒有牧區的人送不存在的崇拜，說的是「不知道是哪一個」而不是「沒有權限」。
  test('不認得的崇拜比牧區先檢查', async () => {
    const permit = await authorizeAs(YOUTH_EDITOR_UID, ROSTER);
    assert.throws(() => permit.forRosterType('wedding'), { status: 400 });
  });
});
