import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { onRequestPost } from '../functions/api/accounts.js';
import { onRequestDelete } from '../functions/api/accounts/[uid].js';
import { resetServiceAccountTokens } from '../worker/service_account.js';
import {
  ADMIN_NAME,
  ADMIN_UID,
  CALENDAR_EDITOR_UID,
  MEMBER_UID,
  fakeFetch,
  idToken,
  muteConsoleError,
  request,
  serviceAccountJson,
  testEnv,
  withFetch,
} from './helpers.js';

const AUTH_API = 'https://identitytoolkit.googleapis.com/v1/projects/demo-church-staff/accounts';
const ACCOUNTS_EMAIL = 'church-accounts@demo.iam.gserviceaccount.com';
const ORPHAN_UID = 'orphanUid0123456789abcdefghij';
const NEW_UID = 'newUid0123456789abcdefghijkl';

beforeEach(() => resetServiceAccountTokens());

async function accountsEnv(overrides = {}) {
  const key = { ...JSON.parse(await serviceAccountJson()), client_email: ACCOUNTS_EMAIL };
  return testEnv({ ACCOUNT_ADMIN_KEY: JSON.stringify(key), ...overrides });
}

/// helpers.js 的 fakeFetch，再加上 Firebase Auth 的管理 API。[signIns] 是
/// email → uid，代表 Auth 裡已經有的登入帳號；[auth] 可以整個換掉回應。
function authFetch({ signIns = {}, auth, users } = {}) {
  const base = fakeFetch(users ? { users } : {});
  const accounts = new Map(Object.entries(signIns));
  const impl = async (url, init = {}) => {
    const target = String(url);
    if (!target.startsWith(AUTH_API)) return base(url, init);
    const body = JSON.parse(init.body);
    base.calls.push({ url: target, method: init.method, body, init });
    const action = target.slice(AUTH_API.length);
    if (auth) {
      const answer = await auth(action, body);
      if (answer) return answer;
    }
    if (action === '') {
      if (accounts.has(body.email)) return authError('EMAIL_EXISTS');
      accounts.set(body.email, NEW_UID);
      return Response.json({ localId: NEW_UID, email: body.email });
    }
    if (action === ':lookup') {
      const uid = accounts.get(body.email[0]);
      return Response.json(uid ? { users: [{ localId: uid, email: body.email[0] }] } : {});
    }
    if (action === ':update') return Response.json({ localId: body.localId });
    if (action === ':delete') {
      if (![...accounts.values()].includes(body.localId)) return authError('USER_NOT_FOUND');
      return Response.json({});
    }
    throw new Error(`unexpected auth action ${action}`);
  };
  impl.calls = base.calls;
  impl.authCalls = () => base.calls.filter((call) => call.url.startsWith(AUTH_API));
  return impl;
}

function authError(message, status = 400) {
  return Response.json({ error: { code: status, message } }, { status });
}

function decodeAssertion(body) {
  const assertion = new URLSearchParams(body).get('assertion');
  const payload = assertion.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
  return JSON.parse(atob(payload));
}

async function create(fetchImpl, body, { token = idToken(ADMIN_UID), env } = {}) {
  return withFetch(fetchImpl, async () =>
    onRequestPost({
      request: request('POST', { token, body, path: '/api/accounts' }),
      env: env ?? (await accountsEnv()),
    }),
  );
}

async function remove(fetchImpl, uid, { token = idToken(ADMIN_UID), env } = {}) {
  return withFetch(fetchImpl, async () =>
    onRequestDelete({
      request: request('DELETE', { token, path: `/api/accounts/${uid}` }),
      env: env ?? (await accountsEnv()),
      params: { uid },
    }),
  );
}

const NEW_STAFF = { email: 'new@example.org', password: 'secret1', name: '新同工' };

describe('POST /api/accounts', () => {
  test('建立新的登入帳號，回傳 uid', async () => {
    const fetchImpl = authFetch();
    const response = await create(fetchImpl, NEW_STAFF);
    assert.equal(response.status, 201);
    assert.deepEqual(await response.json(), { uid: NEW_UID, reused: false });
    const [call] = fetchImpl.authCalls();
    assert.deepEqual(call.body, { email: 'new@example.org', password: 'secret1', displayName: '新同工' });
    assert.equal(call.init.headers.Authorization, 'Bearer test-access-token');
  });

  // 用的是帳號管理那把金鑰，不是行事曆那把：兩個服務帳號、兩份權限。
  test('用 ACCOUNT_ADMIN_KEY 的服務帳號換 token', async () => {
    const fetchImpl = authFetch();
    await create(fetchImpl, NEW_STAFF);
    const exchange = fetchImpl.calls.find((call) => call.url.startsWith('https://oauth2.googleapis.com/token'));
    assert.equal(decodeAssertion(exchange.body).iss, ACCOUNTS_EMAIL);
  });

  test('Email 前後的空白會去掉', async () => {
    const fetchImpl = authFetch();
    await create(fetchImpl, { ...NEW_STAFF, email: '  new@example.org ' });
    assert.equal(fetchImpl.authCalls()[0].body.email, 'new@example.org');
  });

  test('沒設定金鑰的網站回 501，app 會改用舊做法', async () => {
    const fetchImpl = authFetch();
    const response = await create(fetchImpl, NEW_STAFF, { env: await testEnv() });
    assert.equal(response.status, 501);
    assert.equal(fetchImpl.authCalls().length, 0);
  });

  test('不是管理員是 403，不會碰到 Auth', async () => {
    for (const uid of [CALENDAR_EDITOR_UID, MEMBER_UID]) {
      const fetchImpl = authFetch();
      const response = await create(fetchImpl, NEW_STAFF, { token: idToken(uid) });
      assert.equal(response.status, 403);
      assert.equal(fetchImpl.authCalls().length, 0);
    }
  });

  test('Email 或密碼不對，先擋下不送 Google', async () => {
    for (const [body, message] of [
      [{ ...NEW_STAFF, email: 'not-an-email' }, 'Email 格式不正確'],
      [{ ...NEW_STAFF, password: '12345' }, '密碼至少要 6 個字元'],
      [{ ...NEW_STAFF, password: 'x'.repeat(129) }, '密碼太長了，請少於 128 個字元'],
      [{ email: 'new@example.org' }, '密碼至少要 6 個字元'],
      [[], '資料格式不正確'],
    ]) {
      const fetchImpl = authFetch();
      const response = await create(fetchImpl, body);
      assert.equal(response.status, 400);
      assert.equal((await response.json()).error, message);
      assert.equal(fetchImpl.authCalls().length, 0);
    }
  });

  test('Google 說密碼太弱時照樣是 400', async () => {
    const fetchImpl = authFetch({
      auth: (action) => (action === '' ? authError('WEAK_PASSWORD : Password should be at least 6 characters') : null),
    });
    const response = await create(fetchImpl, NEW_STAFF);
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error, '密碼至少要 6 個字元');
  });

  // 以前刪同工只刪資料、登入帳號留著，同一個 Email 就再也加不回來。
  test('Email 已有登入帳號但沒有同工在用：沿用它、換成新密碼、登出舊的連線', async () => {
    const fetchImpl = authFetch({ signIns: { 'new@example.org': ORPHAN_UID } });
    const before = Math.floor(Date.now() / 1000);
    const response = await create(fetchImpl, NEW_STAFF);
    assert.equal(response.status, 201);
    assert.deepEqual(await response.json(), { uid: ORPHAN_UID, reused: true });

    const profileRead = fetchImpl.calls.find((call) => call.url.includes(`/documents/users/${ORPHAN_UID}`));
    assert.equal(profileRead.init.headers.Authorization, `Bearer ${idToken(ADMIN_UID)}`);
    const update = fetchImpl.authCalls().find((call) => call.url.endsWith(':update'));
    assert.equal(update.body.localId, ORPHAN_UID);
    assert.equal(update.body.password, 'secret1');
    assert.equal(update.body.disableUser, false);
    assert.ok(Number(update.body.validSince) >= before);
  });

  test('Email 已經是別的同工的帳號：409，不改他的密碼', async () => {
    const fetchImpl = authFetch({ signIns: { 'admin@example.org': ADMIN_UID } });
    const response = await create(fetchImpl, { ...NEW_STAFF, email: 'admin@example.org' });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error, `這個 Email 已經是「${ADMIN_NAME}」的帳號`);
    assert.ok(!fetchImpl.authCalls().some((call) => call.url.endsWith(':update')));
  });

  test('金鑰被撤銷或失去權限：500，請管理者重跑精靈', async () => {
    const restore = muteConsoleError();
    try {
      const fetchImpl = authFetch({ auth: () => authError('PERMISSION_DENIED', 403) });
      const response = await create(fetchImpl, NEW_STAFF);
      assert.equal(response.status, 500);
      assert.match((await response.json()).error, /安裝精靈/);
    } finally {
      restore();
    }
  });

  test('其他 Google 錯誤是 502', async () => {
    const restore = muteConsoleError();
    try {
      const fetchImpl = authFetch({ auth: () => authError('INTERNAL_ERROR', 500) });
      const response = await create(fetchImpl, NEW_STAFF);
      assert.equal(response.status, 502);
    } finally {
      restore();
    }
  });
});

describe('DELETE /api/accounts/:uid', () => {
  test('刪掉登入帳號', async () => {
    const fetchImpl = authFetch({ signIns: { 'old@example.org': ORPHAN_UID } });
    const response = await remove(fetchImpl, ORPHAN_UID);
    assert.equal(response.status, 204);
    assert.deepEqual(fetchImpl.authCalls().map((call) => [call.url.slice(AUTH_API.length), call.body]), [
      [':delete', { localId: ORPHAN_UID }],
    ]);
  });

  // 上次刪到一半（登入帳號刪了、資料沒刪）時，管理員再按一次要能完成。
  test('登入帳號本來就不在了也算成功', async () => {
    const response = await remove(authFetch(), ORPHAN_UID);
    assert.equal(response.status, 204);
  });

  test('不能刪自己', async () => {
    const fetchImpl = authFetch();
    const response = await remove(fetchImpl, ADMIN_UID);
    assert.equal(response.status, 403);
    assert.equal(fetchImpl.authCalls().length, 0);
  });

  test('不是管理員是 403', async () => {
    const fetchImpl = authFetch();
    const response = await remove(fetchImpl, ORPHAN_UID, { token: idToken(CALENDAR_EDITOR_UID) });
    assert.equal(response.status, 403);
    assert.equal(fetchImpl.authCalls().length, 0);
  });

  test('看起來不像 uid 的不送 Google', async () => {
    for (const uid of ['a/b', '', 'x'.repeat(129), '../users']) {
      const fetchImpl = authFetch();
      const response = await remove(fetchImpl, uid);
      assert.equal(response.status, 400);
      assert.equal(fetchImpl.authCalls().length, 0);
    }
  });

  test('沒設定金鑰的網站回 501', async () => {
    const fetchImpl = authFetch();
    const response = await remove(fetchImpl, ORPHAN_UID, { env: await testEnv() });
    assert.equal(response.status, 501);
    assert.equal(fetchImpl.authCalls().length, 0);
  });
});
