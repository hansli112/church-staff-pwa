import assert from 'node:assert/strict';
import test from 'node:test';
import { exportMove, parseArgs, plain } from './export-move.mjs';

const json = (body, status = 200) => new Response(JSON.stringify(body), { status });
const silent = () => {};
const now = () => new Date('2026-11-05T00:00:00Z');
const firestore = (project) => `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;

function fakeApi(routes) {
  const calls = [];
  return {
    calls,
    fetchImpl: async (url, init) => {
      calls.push({ url, auth: init.headers.Authorization });
      const route = routes[url];
      assert.ok(route !== undefined, `不應讀 ${url}`);
      return typeof route === 'number' ? json({}, route) : json(route);
    },
    getAccessToken: () => 'fake-token',
  };
}

const user = (id, name, email) => ({
  name: `projects/p/databases/(default)/documents/users/${id}`,
  fields: { name: { stringValue: name }, ...(email ? { email: { stringValue: email } } : {}) },
});
const emptyCollections = (project, except = {}) => Object.fromEntries(['users', 'settings', 'rosters', 'staff_orders']
  .map((c) => [`${firestore(project)}/${c}?pageSize=300`, except[c] ?? {}]));

test('Firestore 的值照搬家檔的寫法：時間是 __time__，參照是路徑', () => {
  assert.deepEqual(plain({ mapValue: { fields: {
    date: { timestampValue: '2026-10-03T16:00:00Z' },
    count: { integerValue: '3' },
    ratio: { doubleValue: 0.5 },
    ok: { booleanValue: true },
    none: { nullValue: null },
    who: { referenceValue: 'projects/p/databases/(default)/documents/users/u1' },
    duties: { arrayValue: { values: [{ mapValue: { fields: { role: { stringValue: '司琴' } } } }] } },
    empty: { arrayValue: {} },
    nothing: { mapValue: {} },
  } } }), {
    date: { __time__: '2026-10-03T16:00:00.000Z' },
    count: 3, ratio: 0.5, ok: true, none: null,
    who: 'users/u1',
    duties: [{ role: '司琴' }],
    empty: [],
    nothing: {},
  });
});

test('讀四個集合、接著下一頁，寫成搬家檔', async () => {
  const api = fakeApi({
    ...emptyCollections('grace', {
      users: { documents: [user('u1', '王牧師', 'pastor@example.invalid')], nextPageToken: 'next' },
      rosters: { documents: [{ name: 'projects/grace/databases/(default)/documents/rosters/20261004_sunday', fields: { type: { stringValue: 'sunday' } } }] },
    }),
    [`${firestore('grace')}/users?pageSize=300&pageToken=next`]: { documents: [user('u2', '李美玉')] },
  });
  const file = await exportMove({ project: 'grace', ...api, now, log: silent });
  assert.deepEqual(file, {
    format: 'church-staff-pwa-move', version: 1, project: 'grace', exportedAt: '2026-11-05T00:00:00.000Z',
    users: [{ id: 'u1', data: { name: '王牧師', email: 'pastor@example.invalid' } }, { id: 'u2', data: { name: '李美玉' } }],
    settings: [],
    rosters: [{ id: '20261004_sunday', data: { type: 'sunday' } }],
    staffOrders: [],
  });
  assert.ok(api.calls.every((c) => c.auth === 'Bearer fake-token'));
});

test('沒有 --project 時，用有服事表或服事項目設定的那一個專案', async () => {
  const api = fakeApi({
    'https://cloudresourcemanager.googleapis.com/v1/projects?filter=lifecycleState:ACTIVE&pageSize=200': { projects: [{ projectId: 'other' }, { projectId: 'grace' }] },
    [`${firestore('other')}/rosters?pageSize=1`]: {},
    [`${firestore('other')}/settings/roster_templates`]: 404,
    [`${firestore('grace')}/rosters?pageSize=1`]: { documents: [{ name: 'r/20261004_sunday', fields: {} }] },
    ...emptyCollections('grace', { users: { documents: [user('u1', '王牧師')] } }),
  });
  const file = await exportMove({ ...api, now, log: silent });
  assert.equal(file.project, 'grace');
});

test('找到好幾個或一個都沒有，請他用 --project 選', async () => {
  const list = 'https://cloudresourcemanager.googleapis.com/v1/projects?filter=lifecycleState:ACTIVE&pageSize=200';
  const two = fakeApi({
    [list]: { projects: [{ projectId: 'grace' }, { projectId: 'hope' }] },
    [`${firestore('grace')}/rosters?pageSize=1`]: {},
    [`${firestore('grace')}/settings/roster_templates`]: { fields: {} },
    [`${firestore('hope')}/rosters?pageSize=1`]: { documents: [{ name: 'r/x', fields: {} }] },
  });
  await assert.rejects(exportMove({ ...two, now, log: silent }), /grace、hope.*--project/);
  const none = fakeApi({ [list]: { projects: [{ projectId: 'other' }] }, [`${firestore('other')}/rosters?pageSize=1`]: 403 });
  await assert.rejects(exportMove({ ...none, now, log: silent }), /找不到同工助手的專案/);
});

test('沒有讀取權限時說要用建立專案的帳號；空的專案不寫檔', async () => {
  await assert.rejects(
    exportMove({ project: 'grace', ...fakeApi({ [`${firestore('grace')}/users?pageSize=300`]: 403 }), now, log: silent }),
    /沒有讀取權限/,
  );
  await assert.rejects(exportMove({ project: 'grace', ...fakeApi(emptyCollections('grace')), now, log: silent }), /沒有同工也沒有服事表/);
});

test('參數', () => {
  assert.deepEqual(parseArgs([]), { out: 'move.json' });
  assert.deepEqual(parseArgs(['--project', 'church-abc123', '--out', 'x.json']), { out: 'x.json', project: 'church-abc123' });
  assert.throws(() => parseArgs(['--project']), /要接值/);
  assert.throws(() => parseArgs(['--apply']), /不認得/);
  assert.throws(() => parseArgs(['--project', 'Bad_Id']), /格式不對/);
});
