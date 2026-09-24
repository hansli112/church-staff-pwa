import assert from 'node:assert/strict';
import test from 'node:test';
import { bootstrap, buildAdminProfile, enabledServiceIds, parseArgs } from './bootstrap-admin.mjs';
import defaultConfig from '../worker/generated_config.js';
import { validateChurchConfig } from '../worker/church_config.js';

const service = (id, enabled = true) => ({ id, label: id, name: id, weekday: 1, enabled });
const configWithServices = (services) => ({ ...defaultConfig, services });

const args = ['--project', 'demo-church-staff', '--uid', 'owner-uid', '--name', '測試管理員'];
const options = () => parseArgs([...args, '--apply', '--confirm-project', 'demo-church-staff', '--confirm-uid', 'owner-uid']);
const auth = { localId: 'owner-uid', email: 'owner@example.invalid' };
const response = (status, body) => new Response(body === undefined ? null : JSON.stringify(body), { status });
const silent = () => {};

function fakeApi(responses) {
  const calls = [];
  return {
    calls,
    fetchImpl: async (url, init) => {
      calls.push({ url, ...init, body: init.body && JSON.parse(init.body) });
      assert.ok(responses.length, '不應多送請求');
      return responses.shift();
    },
    getAccessToken: () => 'fake-token',
    log: silent,
  };
}

test('dry-run is fully offline, including token acquisition', async () => {
  const result = await bootstrap(parseArgs(args), {
    fetchImpl: () => assert.fail('不得呼叫 API'),
    getAccessToken: () => assert.fail('不得讀取憑證'),
    log: silent,
  });
  assert.equal(result.applied, false);
});

test('apply requires explicit project and UID confirmation before any network access', async () => {
  assert.throws(() => parseArgs([...args, '--apply']), /confirm-project/);
  assert.throws(() => parseArgs([...args, '--apply', '--confirm-project', 'other-project', '--confirm-uid', 'owner-uid']), /confirm-project/);
  assert.throws(() => parseArgs([...args, '--apply', '--confirm-project', 'demo-church-staff', '--confirm-uid', 'wrong-uid']), /不一致/);
  await assert.rejects(bootstrap({ ...parseArgs(args), apply: true }, {
    fetchImpl: () => assert.fail('不得呼叫 API'), getAccessToken: () => assert.fail('不得讀取憑證'), log: silent,
  }), /confirm-project/);
});

test('CLI rejects missing identity, project, name and unknown options', () => {
  assert.throws(() => parseArgs([]), /project/);
  assert.throws(() => parseArgs(['--project', 'demo-church-staff', '--name', 'test']), /uid/);
  assert.throws(() => parseArgs(['--project', 'demo-church-staff', '--uid', 'x']), /name/);
  assert.throws(() => parseArgs([...args, '--password', 'not-accepted']), /不支援/);
  assert.throws(() => parseArgs([...args, '--project', 'demo-other']), /重複/);
});

test('profile matches required User fields, with zones and zoneTypes derived together', () => {
  const ids = enabledServiceIds(configWithServices([service('sundayService'), service('archived', false)]));
  const profile = buildAdminProfile(options(), auth, ids);
  assert.deepEqual(profile, {
    id: 'owner-uid', email: 'owner@example.invalid', name: '測試管理員', username: '測試管理員', role: 'admin',
    groups: [], zones: [{ serviceType: 'sundayService', smallGroups: [], ministries: [] }], zoneTypes: ['sundayService'],
  });
  assert.throws(() => enabledServiceIds(configWithServices([service('same'), service('same', false)])), /duplicate service id/);
  assert.throws(() => enabledServiceIds(configWithServices([service('bad/id')])), /service.id/);
  assert.throws(() => enabledServiceIds(configWithServices([service('constructor')])), /service.id/);
  assert.deepEqual(enabledServiceIds(configWithServices([service('SundayService')])), ['SundayService']);
});

test('bootstrap uses the deployment schema and service limit before reading credentials', async () => {
  const twenty = configWithServices(Array.from({ length: 20 }, (_, i) => service(`service${i}`)));
  assert.doesNotThrow(() => validateChurchConfig(twenty));
  assert.equal(enabledServiceIds(twenty).length, 20);

  const tooMany = { ...twenty, services: [...twenty.services, service('extra')] };
  assert.throws(() => validateChurchConfig(tooMany), /1 to 20/);
  assert.throws(() => enabledServiceIds(tooMany), /1 to 20/);
  await assert.rejects(bootstrap({ ...options(), config: 'test-church.json' }, {
    readConfig: () => tooMany,
    getAccessToken: () => assert.fail('無效設定不得讀取憑證'),
    fetchImpl: () => assert.fail('無效設定不得呼叫 API'),
    log: silent,
  }), /1 to 20/);
});

test('bootstrap rejects partial or invalid church configuration, matching deployment', () => {
  for (const config of [
    { services: [service('partial')] },
    { ...defaultConfig, timeZone: 'Invalid/Zone' },
    configWithServices([{ ...service('invalidDay'), weekday: 8 }]),
    configWithServices([]),
  ]) {
    assert.throws(() => validateChurchConfig(config));
    assert.throws(() => enabledServiceIds(config));
  }
  assert.deepEqual(enabledServiceIds(undefined), []);
  assert.deepEqual(enabledServiceIds(configWithServices([service('archived', false)])), []);
});

test('only existing, enabled, confirmed Auth identity can be used', () => {
  assert.throws(() => buildAdminProfile(options(), { ...auth, disabled: true }), /停用/);
  assert.throws(() => buildAdminProfile(options(), { ...auth, localId: 'other-uid' }), /不一致/);
  assert.throws(() => buildAdminProfile({ ...options(), email: 'other@example.invalid' }, auth), /email/);
});

test('new profile uses create-only atomic precondition, never writes to Auth', async () => {
  const api = fakeApi([response(200, { users: [auth] }), response(404), response(200, {})]);
  const result = await bootstrap(options(), api);
  assert.equal(result.applied, true);
  assert.match(api.calls[0].url, /projects\/demo-church-staff\/accounts:lookup$/);
  assert.deepEqual(api.calls[0].body, { localId: ['owner-uid'] });
  assert.match(api.calls[1].url, /documents\/users\/owner-uid$/);
  assert.deepEqual(api.calls[2].body.writes[0].currentDocument, { exists: false });
  assert.equal(api.calls[2].body.writes[0].update.fields.role.stringValue, 'admin');
  assert.equal(api.calls[2].body.writes.length, 1);
  assert.ok(api.calls.every((call) => call.redirect === 'error'));
  assert.ok(api.calls.every((call) => call.headers['x-goog-user-project'] === 'demo-church-staff'));
  assert.ok(api.calls.every((call) => call.headers.Authorization === 'Bearer fake-token'));
});

test('email lookup requires Console-confirmed matching UID', async () => {
  const opts = parseArgs(['--project', 'demo-church-staff', '--email', auth.email, '--name', '測試管理員', '--apply', '--confirm-project', 'demo-church-staff', '--confirm-uid', 'wrong-uid']);
  const api = fakeApi([response(200, { users: [auth] })]);
  await assert.rejects(bootstrap(opts, api), /核對過的 UID/);
  assert.deepEqual(api.calls[0].body, { email: [auth.email] });
  assert.equal(api.calls.length, 1);
});

test('existing profile is never overwritten or promoted', async () => {
  const api = fakeApi([response(200, { users: [auth] }), response(200, {})]);
  await assert.rejects(bootstrap(options(), api), /不覆寫、不升權/);
  assert.equal(api.calls.length, 2);
});

test('missing Auth, denied read, and concurrent profile creation all fail closed', async (t) => {
  for (const [label, responses, pattern] of [
    ['missing Auth', [response(200, { users: [] })], /找不到唯一/],
    ['Auth unavailable', [response(403)], /lookup 失敗/],
    ['denied Firestore read', [response(200, { users: [auth] }), response(403)], /無法確認/],
    ['concurrent create', [response(200, { users: [auth] }), response(404), response(409)], /不會覆寫/],
  ]) {
    await t.test(label, async () => {
      const api = fakeApi(responses);
      await assert.rejects(bootstrap(options(), api), pattern);
    });
  }
});
