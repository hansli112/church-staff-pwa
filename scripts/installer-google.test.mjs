import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { ActionRequired, createGoogleInstaller } from './installer/google.mjs';
import { renderRules } from './prepare-deployment.mjs';
import config from '../worker/generated_config.js';

const steps = ['google-project', 'firebase', 'database', 'auth', 'web-app', 'rules', 'admin', 'auth-domains', 'activation'];
const projectId = 'demo-church-install';
const project = `projects/${projectId}`;
const database = `${project}/databases/(default)`;
const runId = 'test-run-12345678';
const runLabel = createHash('sha256').update(runId).digest('hex').slice(0, 32);
const uid = `install-${createHash('sha256').update(runId).digest('hex').slice(0, 40)}`;
const fixedNow = 1_760_000_000_000;
const closedRules = "rules_version = '2'; service cloud.firestore { match /databases/{database}/documents { match /{document=**} { allow read, write: if false; } } }";
// Real Firestore REST drops empty repeated fields on read ({values: []} comes
// back as {}); store documents the way the service would return them.
const readBack = (value) => JSON.parse(JSON.stringify(value, (key, entry) =>
  (key === 'values' && Array.isArray(entry) && !entry.length) || (key === 'fields' && entry && !Object.keys(entry).length) ? undefined : entry));
const response = (status, body = {}) => new Response(JSON.stringify(body), { status });
const error = (status, message) => response(status, { error: { message } });

async function setup(t, overrides = {}) {
  const runDir = await mkdtemp(path.join(os.tmpdir(), 'installer-google-test-'));
  t.after(() => rm(runDir, { recursive: true, force: true }));
  await mkdir(path.join(runDir, 'deployment'));
  const rules = renderRules(await readFile(new URL('../firestore.rules', import.meta.url), 'utf8'), config);
  await writeFile(path.join(runDir, 'deployment/firestore.rules'), rules);
  const context = {
    plan: { runId, projectId, region: 'asia-east1', pagesProject: 'demo-church-site', googleEmail: 'operator@example.invalid',
      churchConfig: config, admin: { name: '測試管理員', username: '測試', email: 'admin@example.invalid' }, activationEmailConfirmed: true },
    runDir, checkpoint: { resources: { pagesSubdomain: 'demo-church-site.pages.dev' }, intents: {} }, transient: {},
    snapshots: [], events: [],
    save: async (patch) => {
      context.snapshots.push(structuredClone(patch));
      for (const [section, value] of Object.entries(patch)) Object.assign(context.checkpoint[section], value);
    },
    emit: (event) => context.events.push(event),
  };
  const state = {
    project: null, firebase: null, db: null, enabled: new Set(), apps: [], users: [], profile: null,
    collections: [], children: [], release: null, rulesets: new Map(), requests: [], commands: [], delays: [], sent: 0,
    authConfig: { name: `${project}/config`, subtype: 'FIREBASE_AUTH', signIn: { email: { enabled: false, passwordRequired: true }, hashConfig: { key: 'never-persist-auth-hash-key' } },
      authorizedDomains: [`${projectId}.firebaseapp.com`, 'other.example.invalid'] },
  };
  let interceptor;
  let account = 'operator@example.invalid';
  const command = async (file, args) => {
    state.commands.push({ file, args });
    assert.equal(file, 'gcloud');
    if (args[0] === 'config') return { stdout: '{}', stderr: '' };
    if (args[1] === 'list') return { stdout: JSON.stringify([{ account, status: 'ACTIVE' }]), stderr: '' };
    assert.deepEqual(args, ['auth', 'print-access-token', `--account=${account}`, '--quiet']);
    return { stdout: 'never-log-this-google-token\n', stderr: '' };
  };
  const fetchImpl = async (url, init) => {
    assert.equal(init.redirect, 'error');
    assert.equal(init.headers.Authorization, 'Bearer never-log-this-google-token');
    assert.ok(init.signal instanceof AbortSignal);
    const parsed = new URL(url);
    const host = parsed.hostname.split('.')[0];
    if (host === 'identitytoolkit') assert.equal(init.headers['x-goog-user-project'], projectId);
    const pathname = decodeURIComponent(parsed.pathname);
    const body = init.body ? JSON.parse(init.body) : undefined;
    const call = { url, host, pathname, search: parsed.search, method: init.method, body };
    state.requests.push(call);
    const intercepted = await interceptor?.(call, state, context);
    if (intercepted) return intercepted;
    if (host === 'cloudresourcemanager') {
      if (pathname === `/v3/${project}` && init.method === 'GET') return state.project ? response(200, state.project) : response(404);
      if (pathname === '/v3/projects' && init.method === 'POST') {
        assert.ok(context.checkpoint.intents.googleProject, 'intent must be durable before project create');
        assert.deepEqual(body.labels, { 'church-install': runLabel });
        state.project = { ...body, name: 'projects/123456789', state: 'ACTIVE', createTime: new Date(fixedNow).toISOString() };
        return response(200, { name: 'operations/project-1', done: true, response: state.project });
      }
    }
    if (host === 'serviceusage') {
      if (pathname.endsWith('/services:batchEnable')) {
        assert.ok(context.checkpoint.intents.googleServices);
        body.serviceIds.forEach((name) => state.enabled.add(name));
        return response(200, { name: 'operations/services-1', done: true, response: {} });
      }
      return response(200, { state: state.enabled.has(pathname.split('/').at(-1)) ? 'ENABLED' : 'DISABLED' });
    }
    if (host === 'firebase') {
      if (pathname === `/v1beta1/${project}`) return state.firebase ? response(200, state.firebase) : response(404);
      if (pathname.endsWith(':addFirebase')) {
        assert.ok(context.checkpoint.intents.firebase);
        state.firebase = { projectId, projectNumber: '123456789' };
        return response(200, { name: 'operations/firebase-1', done: true, response: state.firebase });
      }
      if (pathname.endsWith('/webApps') && init.method === 'GET') return response(200, { apps: state.apps });
      if (pathname.endsWith('/webApps') && init.method === 'POST') {
        assert.ok(context.checkpoint.intents.webApp);
        state.apps.push({ ...body, name: `${project}/webApps/1:123456789:web:install`, appId: '1:123456789:web:install', projectId, state: 'ACTIVE' });
        return response(200, { name: 'operations/webapp-1', done: true, response: state.apps[0] });
      }
      if (pathname.endsWith('/config')) return response(200, { projectId, appId: state.apps[0].appId,
        authDomain: `${projectId}.firebaseapp.com`, messagingSenderId: '123456789', apiKey: 'never-persist-api-key', storageBucket: `${projectId}.firebasestorage.app` });
    }
    if (host === 'firestore') {
      if (pathname === `/v1/${project}/databases` && init.method === 'GET') return response(200, { databases: state.db ? [state.db] : [] });
      if (pathname === `/v1/${project}/databases` && init.method === 'POST') {
        assert.ok(context.checkpoint.intents.database);
        assert.deepEqual(body, { locationId: 'asia-east1', type: 'FIRESTORE_NATIVE', databaseEdition: 'STANDARD' });
        state.db = { ...body, name: database, uid: 'database-unique-id' };
        return response(200, { name: `${database}/operations/db-1`, done: true, response: state.db });
      }
      if (pathname === `/v1/${database}`) return response(200, state.db);
      if (pathname.endsWith(':listCollectionIds')) return response(200, {
        collectionIds: pathname.includes('/users/') ? state.children : [...state.collections, ...(state.profile ? ['users'] : [])],
      });
      if (pathname.endsWith('/documents/users') && init.method === 'GET') return response(200, { documents: state.profile ? [state.profile] : [] });
      if (pathname.endsWith(`/documents/users/${uid}`)) return state.profile ? response(200, state.profile) : response(404);
      if (pathname.endsWith('/documents:commit')) {
        assert.ok(context.checkpoint.intents.adminProfile);
        assert.deepEqual(context.checkpoint.intents.adminProfile.before, { exists: false, checkedAt: new Date(fixedNow).toISOString() });
        assert.equal(body.writes.length, 1);
        assert.deepEqual(body.writes[0].currentDocument, { exists: false });
        assert.equal(state.profile, null, 'never overwrite existing profile');
        state.profile = { ...readBack(body.writes[0].update), updateTime: new Date(fixedNow).toISOString() };
        return response(200, { writeResults: [{}] });
      }
    }
    if (host === 'identitytoolkit') {
      if (pathname === `/admin/v2/${project}/config`) {
        if (init.method === 'PATCH') {
          if (body.signIn) {
            assert.ok(context.checkpoint.intents.auth);
            state.authConfig.signIn.email = body.signIn.email;
          }
          if (body.authorizedDomains) {
            assert.ok(context.checkpoint.intents.authDomains);
            state.authConfig.authorizedDomains = body.authorizedDomains;
          }
        }
        return response(200, state.authConfig);
      }
      if (pathname.endsWith('/accounts:batchGet')) return response(200, { users: state.users });
      if (pathname.endsWith('/accounts:lookup')) return response(200, { users: state.users.filter((user) => body.localId.includes(user.localId)) });
      if (pathname.endsWith('/accounts') && init.method === 'POST') {
        assert.ok(context.checkpoint.intents.adminAuth);
        assert.equal(body.emailVerified, false);
        assert.equal(body.password, undefined);
        state.users.push({ ...body, createdAt: String(fixedNow), passwordHash: 'never-persist-user-hash', salt: 'never-persist-user-salt' });
        return response(200, { localId: body.localId });
      }
      if (pathname.endsWith('/accounts:sendOobCode')) {
        assert.ok(context.checkpoint.intents.activation);
        assert.equal(body.requestType, 'PASSWORD_RESET');
        assert.equal(body.returnOobLink, false);
        assert.equal(body.email, 'admin@example.invalid');
        state.sent++;
        return response(200, { email: body.email, oobCode: 'unexpected-provider-secret-do-not-store' });
      }
    }
    if (host === 'firebaserules') {
      if (pathname.endsWith('/releases/cloud.firestore')) {
        if (init.method === 'PATCH') {
          assert.ok(context.checkpoint.intents.rules.before);
          assert.equal(body.updateTime, undefined);
          state.release = { ...body.release, updateTime: 'rules-time-2' };
        }
        return state.release ? response(200, state.release) : response(404);
      }
      if (pathname.endsWith('/releases') && init.method === 'POST') {
        assert.ok(context.checkpoint.intents.rules);
        state.release = { ...body, updateTime: 'rules-time-1' };
        return response(200, state.release);
      }
      if (pathname.endsWith('/rulesets') && init.method === 'POST') {
        assert.ok(context.checkpoint.intents.rules);
        const value = { name: `${project}/rulesets/ruleset-${state.rulesets.size + 1}`, ...body,
          source: { files: body.source.files.map((file) => ({ ...file, fingerprint: 'provider-file-fingerprint' })) } };
        state.rulesets.set(value.name, value);
        return response(200, value);
      }
      if (pathname.includes('/rulesets/')) return state.rulesets.has(pathname.slice(4)) ? response(200, state.rulesets.get(pathname.slice(4))) : response(404);
    }
    assert.fail(`Unexpected offline API call: ${init.method} ${host}${pathname}`);
  };
  const adapter = createGoogleInstaller({ fetchImpl, command, delay: async (ms) => state.delays.push(ms), now: () => fixedNow, ...overrides });
  return { adapter, context, state, setInterceptor: (fn) => { interceptor = fn; }, setAccount: (value) => { account = value; },
    through: async (last) => { for (const step of steps.slice(0, steps.indexOf(last) + 1)) await adapter.execute(step, context); } };
}

const rejectsCode = async (promise, code) => assert.rejects(promise, (err) => {
  assert.ok(err instanceof ActionRequired);
  assert.equal(err.code, code);
  assert.equal(err.safeToDisplay, true);
  return true;
});

test('construction and invalid plans never read credentials or contact Google', async () => {
  const adapter = createGoogleInstaller({ command: () => assert.fail('no credentials'), fetchImpl: () => assert.fail('no network') });
  await rejectsCode(adapter.execute('google-project', { plan: {} }), 'GOOGLE_INVALID_PLAN');
});

test('fresh installation exercises every real execute step without passwords, paid APIs or secret persistence', async (t) => {
  const h = await setup(t);
  await h.through('activation');
  assert.deepEqual(h.state.profile.fields.role, { stringValue: 'admin' });
  assert.equal(h.context.checkpoint.resources.admin.uid, uid);
  assert.equal(h.state.sent, 1);
  assert.equal(h.context.transient.firebaseConfig.apiKey, 'never-persist-api-key');
  assert.deepEqual(h.state.authConfig.authorizedDomains, [`${projectId}.firebaseapp.com`, 'other.example.invalid', 'demo-church-site.pages.dev']);
  const persisted = JSON.stringify([h.context.snapshots, h.context.checkpoint, h.context.events]);
  for (const secret of ['never-log-this-google-token', 'never-persist-api-key', 'unexpected-provider-secret-do-not-store',
    'never-persist-auth-hash-key', 'never-persist-user-hash', 'never-persist-user-salt']) assert.equal(persisted.includes(secret), false);
  assert.ok(h.state.requests.every((call) => !/billing|initializeAuth|initializeProject|upgrade|identityplatform|sms/i.test(call.url)));
  assert.ok(h.state.commands.every((call) => !call.args.includes('application-default')));
  assert.ok(h.context.checkpoint.intents.rules.before);
});

test('resume verifies every live resource, refetches web config and does not create or mail twice', async (t) => {
  const h = await setup(t);
  await h.through('activation');
  const writes = () => h.state.requests.filter((call) => ['POST', 'PATCH'].includes(call.method) && !/:listCollectionIds|:lookup/.test(call.pathname));
  const before = writes().length;
  h.context.transient = {};
  await h.through('activation');
  assert.equal(writes().length, before);
  assert.equal(h.state.sent, 1);
  assert.equal(h.context.transient.firebaseConfig.apiKey, 'never-persist-api-key');
});

test('already existing projects cannot be adopted even with the expected name or label', async (t) => {
  const h = await setup(t);
  h.state.project = { name: 'projects/123456789', projectId, state: 'ACTIVE', labels: { 'church-install': runLabel } };
  await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_RESOURCE_CONFLICT');
  assert.equal(h.state.requests.length, 1);
});

test('every step rejects a changed Google account and project ownership before mutation', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  h.setAccount('other@example.invalid');
  const before = h.state.requests.length;
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_ACCOUNT_CHANGED');
  assert.equal(h.state.requests.length, before);
  h.setAccount('operator@example.invalid');
  h.state.project.labels['church-install'] = 'other-install';
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_RESOURCE_CONFLICT');
  assert.equal(h.state.requests.at(-1).method, 'GET');
});

test('provider permissions, terms, billing and setup errors have actionable safe messages', async (t) => {
  for (const [status, message, code] of [
    [403, 'PERMISSION_DENIED token=should-not-appear', 'GOOGLE_PERMISSION_REQUIRED'],
    [400, 'TERMS_OF_SERVICE_NOT_ACCEPTED private-stuff', 'GOOGLE_TERMS_REQUIRED'],
    [400, 'BILLING_REQUIRED private-stuff', 'GOOGLE_FREE_TIER_REQUIRED'],
    [401, 'private-stuff', 'GOOGLE_AUTH_REQUIRED'],
  ]) await t.test(code, async (t) => {
    const h = await setup(t);
    h.setInterceptor(() => error(status, message));
    await rejectsCode(h.adapter.execute('google-project', h.context), code);
    assert.equal(JSON.stringify(h.context.events).includes('private-stuff'), false);
  });
  await t.test('one official Get started action, not a paid setup endpoint', async (t) => {
    const h = await setup(t);
    await h.through('database');
    h.setInterceptor((call) => call.pathname === `/admin/v2/${project}/config` ? error(404, 'CONFIGURATION_NOT_FOUND') : undefined);
    await rejectsCode(h.adapter.execute('auth', h.context), 'AUTH_SETUP_REQUIRED');
    assert.ok(h.state.requests.every((call) => !call.pathname.includes(':initialize')));
    h.setInterceptor(undefined);
    await h.adapter.execute('auth', h.context);
    assert.equal(h.state.authConfig.signIn.email.enabled, true);
  });
});

test('existing database, data, Auth users and profile are never adopted or promoted', async (t) => {
  await t.test('database without create evidence', async (t) => {
    const h = await setup(t);
    await h.through('firebase');
    h.state.db = { name: database, uid: 'foreign-db', type: 'FIRESTORE_NATIVE', locationId: 'asia-east1' };
    await rejectsCode(h.adapter.execute('database', h.context), 'GOOGLE_RESOURCE_CONFLICT');
  });
  await t.test('existing collection', async (t) => {
    const h = await setup(t);
    await h.through('database');
    h.state.collections = ['rosters'];
    await rejectsCode(h.adapter.execute('database', h.context), 'GOOGLE_RESOURCE_CONFLICT');
  });
  await t.test('Auth account with matching email but foreign UID', async (t) => {
    const h = await setup(t);
    await h.through('database');
    h.state.users.push({ localId: 'foreign', email: h.context.plan.admin.email });
    await rejectsCode(h.adapter.execute('auth', h.context), 'GOOGLE_RESOURCE_CONFLICT');
  });
  await t.test('profile collision remains create-only', async (t) => {
    const h = await setup(t);
    await h.through('rules');
    h.setInterceptor((call) => {
      if (call.pathname.endsWith('/documents:commit')) return error(409, 'ALREADY_EXISTS');
    });
    await rejectsCode(h.adapter.execute('admin', h.context), 'GOOGLE_RESOURCE_CONFLICT');
    const commit = h.state.requests.find((call) => call.pathname.endsWith('/documents:commit'));
    assert.deepEqual(commit.body.writes[0].currentDocument, { exists: false });
    assert.equal(h.state.profile, null);
  });
});

test('project creation crash resumes from its run-specific label, not another project', async (t) => {
  const h = await setup(t);
  const save = h.context.save;
  h.context.save = async (patch) => {
    if (patch.intents?.googleProject?.operation) throw new Error('simulated disk interruption');
    return save(patch);
  };
  await assert.rejects(h.adapter.execute('google-project', h.context), /disk interruption/);
  h.context.save = save;
  await h.adapter.execute('google-project', h.context);
  assert.equal(h.state.requests.filter((call) => call.pathname === '/v3/projects').length, 1);
});

test('Auth creation and profile commit crash recover only exact deterministic records', async (t) => {
  for (const phase of ['auth', 'profile']) await t.test(phase, async (t) => {
    const h = await setup(t);
    await h.through('rules');
    let crashed = false;
    h.setInterceptor((call) => {
      if (phase === 'auth' && !crashed && call.pathname.endsWith('/accounts') && call.method === 'POST') {
        h.state.users.push(call.body); crashed = true; throw new Error('response lost token=should-not-log');
      }
      if (phase === 'profile' && !crashed && call.pathname.endsWith('/documents:commit')) {
        h.state.profile = readBack(call.body.writes[0].update); crashed = true; throw new Error('response lost');
      }
    });
    await rejectsCode(h.adapter.execute('admin', h.context), 'GOOGLE_CONNECTION_INTERRUPTED');
    h.setInterceptor(undefined);
    await h.adapter.execute('admin', h.context);
    assert.equal(h.state.users.length, 1);
    assert.equal(h.state.profile.fields.role.stringValue, 'admin');
    assert.equal(h.state.requests.filter((call) => call.pathname.endsWith('/accounts') && call.method === 'POST').length, 1);
    if (phase === 'profile') assert.equal(h.state.requests.filter((call) => call.pathname.endsWith('/documents:commit')).length, 1);
  });
});

test('initial deny-all rules are backed up, but unknown or concurrently changed rules stop', async (t) => {
  await t.test('closed initial rules', async (t) => {
    const h = await setup(t);
    await h.through('web-app');
    const name = `${project}/rulesets/initial`;
    h.state.rulesets.set(name, { name, source: { files: [{ name: 'firestore.rules', content: closedRules }] } });
    h.state.release = { name: `${project}/releases/cloud.firestore`, rulesetName: name, updateTime: 'initial' };
    await h.adapter.execute('rules', h.context);
    assert.equal(h.context.checkpoint.intents.rules.before.ruleset.source.files[0].content, closedRules);
    assert.ok(h.state.requests.some((call) => call.host === 'firebaserules' && call.method === 'PATCH'));
  });
  await t.test('unknown rules', async (t) => {
    const h = await setup(t);
    await h.through('web-app');
    const name = `${project}/rulesets/foreign`;
    h.state.rulesets.set(name, { name, source: { files: [{ name: 'firestore.rules', content: closedRules.replace('false', 'true') }] } });
    h.state.release = { name: `${project}/releases/cloud.firestore`, rulesetName: name };
    await rejectsCode(h.adapter.execute('rules', h.context), 'GOOGLE_RESOURCE_CONFLICT');
    assert.ok(!h.state.requests.some((call) => call.host === 'firebaserules' && call.method !== 'GET'));
  });
  await t.test('changed between backup and write', async (t) => {
    const h = await setup(t);
    await h.through('web-app');
    h.setInterceptor((call) => {
      if (call.pathname.endsWith('/rulesets') && call.method === 'POST') {
        const name = `${project}/rulesets/foreign`;
        h.state.rulesets.set(name, { name, source: { files: [{ name: 'firestore.rules', content: closedRules }] } });
        h.state.release = { name: `${project}/releases/cloud.firestore`, rulesetName: name };
      }
    });
    await rejectsCode(h.adapter.execute('rules', h.context), 'GOOGLE_RESOURCE_CONFLICT');
    assert.ok(!h.state.requests.some((call) => call.pathname.endsWith('/releases') && call.method === 'POST'));
  });
});

test('activation needs explicit consent and ambiguous delivery never auto-resends', async (t) => {
  const h = await setup(t);
  await h.through('auth-domains');
  h.context.plan.activationEmailConfirmed = false;
  await rejectsCode(h.adapter.execute('activation', h.context), 'ACTIVATION_CONFIRMATION_REQUIRED');
  assert.equal(h.state.sent, 0);
  h.context.plan.activationEmailConfirmed = true;
  h.setInterceptor((call) => {
    if (call.pathname.endsWith(':sendOobCode')) { h.state.sent++; throw new Error('delivery response lost'); }
  });
  await rejectsCode(h.adapter.execute('activation', h.context), 'GOOGLE_CONNECTION_INTERRUPTED');
  h.setInterceptor(undefined);
  await assert.rejects(h.adapter.execute('activation', h.context), (err) => {
    assert.equal(err.code, 'ACTIVATION_DELIVERY_UNKNOWN');
    assert.equal(err.helpUrl, `https://console.firebase.google.com/project/${projectId}/authentication/users`);
    assert.match(err.message, /Authentication → Users/);
    assert.doesNotMatch(err.message, /忘記密碼/);
    return true;
  });
  assert.equal(h.state.sent, 1);
});

test('long operations have bounded backoff, persist their ID and map provider failures safely', async (t) => {
  await t.test('pending operation timeout', async (t) => {
    const h = await setup(t);
    h.setInterceptor((call) => {
      if (call.pathname === '/v3/projects' || call.pathname === '/v3/operations/pending') return response(200, { name: 'operations/pending', done: false });
    });
    await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_OPERATION_PENDING');
    assert.equal(h.context.checkpoint.intents.googleProject.operation, 'operations/pending');
    assert.equal(h.state.delays.length, 45);
    assert.ok(h.state.delays.every((ms) => ms <= 8000));
    const before = h.state.requests.filter((call) => call.pathname === '/v3/projects').length;
    await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_OPERATION_PENDING');
    assert.equal(h.state.requests.filter((call) => call.pathname === '/v3/projects').length, before);
  });
  await t.test('operation permission error', async (t) => {
    const h = await setup(t);
    h.setInterceptor((call) => call.pathname === '/v3/projects'
      ? response(200, { done: true, error: { code: 7, message: 'do-not-display-provider-details' } }) : undefined);
    await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_PERMISSION_REQUIRED');
  });
  await t.test('untrusted operation URL cannot change API host', async (t) => {
    const h = await setup(t);
    h.setInterceptor((call) => call.pathname === '/v3/projects'
      ? response(200, { name: 'https://attacker.invalid/token', done: false }) : undefined);
    await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_INVALID_RESPONSE');
    assert.equal(h.state.requests.length, 2);
  });
});

test('database operation response and rules release response can be recovered after interruption', async (t) => {
  await t.test('database UID recovered from saved operation', async (t) => {
    const h = await setup(t);
    await h.through('firebase');
    const save = h.context.save;
    h.context.save = async (patch) => {
      if (patch.intents?.database?.uid) throw new Error('disk interrupted before UID saved');
      return save(patch);
    };
    await assert.rejects(h.adapter.execute('database', h.context), /disk interrupted/);
    h.context.save = save;
    h.setInterceptor((call) => call.pathname.endsWith('/operations/db-1')
      ? response(200, { name: `${database}/operations/db-1`, done: true, response: h.state.db }) : undefined);
    await h.adapter.execute('database', h.context);
    assert.equal(h.context.checkpoint.resources.database.uid, 'database-unique-id');
    assert.equal(h.state.requests.filter((call) => call.method === 'POST' && call.pathname.endsWith('/databases')).length, 1);
  });
  await t.test('rules publish response lost', async (t) => {
    const h = await setup(t);
    await h.through('web-app');
    h.setInterceptor((call) => {
      if (call.pathname.endsWith('/releases') && call.method === 'POST') {
        h.state.release = { ...call.body, updateTime: 'one-release' };
        throw new Error('response lost');
      }
    });
    await rejectsCode(h.adapter.execute('rules', h.context), 'GOOGLE_CONNECTION_INTERRUPTED');
    h.setInterceptor(undefined);
    await h.adapter.execute('rules', h.context);
    assert.equal(h.state.requests.filter((call) => call.method === 'POST' && call.pathname.endsWith('/releases')).length, 1);
  });
});

test('resume refuses deleted admin, altered profile, subcollections and foreign web app', async (t) => {
  for (const kind of ['deleted', 'altered', 'child', 'web', 'database']) await t.test(kind, async (t) => {
    const h = await setup(t);
    await h.through('auth-domains');
    if (kind === 'deleted') h.state.profile = null;
    if (kind === 'altered') h.state.profile.fields.role.stringValue = 'member';
    if (kind === 'child') h.state.children = ['private-records'];
    if (kind === 'web') h.state.apps[0].displayName = 'Unrelated production';
    if (kind === 'database') h.state.db.uid = 'replacement-database';
    await rejectsCode(h.adapter.execute(kind === 'web' ? 'web-app' : 'activation', h.context), 'GOOGLE_RESOURCE_CONFLICT');
    assert.equal(h.state.sent, 0);
  });
});

test('rejected operation can be retried after a verified terminal failure', async (t) => {
  const h = await setup(t);
  h.setInterceptor((call) => call.pathname === '/v3/projects'
    ? response(200, { name: 'operations/failed', done: true, error: { code: 8, message: 'QUOTA' } }) : undefined);
  await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_QUOTA_REQUIRED');
  assert.equal(h.context.checkpoint.intents.googleProject.operation, undefined);
  assert.equal(h.context.checkpoint.intents.googleProject.lastOperationFailed, true);
  h.setInterceptor(undefined);
  await h.adapter.execute('google-project', h.context);
  assert.ok(h.context.checkpoint.resources.googleProject);
});

test('Auth domain changes are backed up and concurrent writes are not overwritten', async (t) => {
  const h = await setup(t);
  await h.through('admin');
  let reads = 0;
  h.setInterceptor((call) => {
    if (call.pathname === `/admin/v2/${project}/config` && call.method === 'GET' && ++reads === 2) {
      h.state.authConfig.authorizedDomains.push('changed.example.invalid');
    }
  });
  await rejectsCode(h.adapter.execute('auth-domains', h.context), 'GOOGLE_RESOURCE_CONFLICT');
  assert.deepEqual(h.context.checkpoint.intents.authDomains.before.authorizedDomains,
    [`${projectId}.firebaseapp.com`, 'other.example.invalid']);
  assert.ok(!h.state.requests.some((call) => call.method === 'PATCH' && call.search.includes('authorizedDomains')));
});

test('identity inspection refuses impersonation and never reveals command errors', async () => {
  const injected = createGoogleInstaller({ command: async (_, args) => ({ stdout: args[0] === 'config'
    ? JSON.stringify({ auth: { impersonate_service_account: 'service@example.invalid' } })
    : JSON.stringify([{ account: 'operator@example.invalid', status: 'ACTIVE' }]) }) });
  await rejectsCode(injected.inspectIdentity(), 'GOOGLE_AUTH_REQUIRED');
  const broken = createGoogleInstaller({ command: async () => { throw new Error('access_token=private-secret'); } });
  await assert.rejects(broken.inspectIdentity(), (err) => {
    assert.equal(err.code, 'GOOGLE_AUTH_REQUIRED');
    assert.equal(err.message.includes('private-secret'), false);
    return true;
  });
});

test('read requests retry 429/5xx finitely, mutation failures are never blindly replayed', async (t) => {
  await t.test('GET retry eventually succeeds', async (t) => {
    const h = await setup(t);
    let failures = 0;
    h.setInterceptor((call) => call.method === 'GET' && call.host === 'cloudresourcemanager' && failures++ < 2 ? error(503, 'unavailable') : undefined);
    await h.adapter.execute('google-project', h.context);
    assert.deepEqual(h.state.delays, [500, 1000]);
  });
  await t.test('quota limit', async (t) => {
    const h = await setup(t);
    h.setInterceptor(() => error(429, 'RESOURCE_EXHAUSTED'));
    await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_QUOTA_REQUIRED');
    assert.equal(h.state.requests.length, 4);
  });
  await t.test('uncertain POST', async (t) => {
    const h = await setup(t);
    h.setInterceptor((call) => call.method === 'POST' ? error(503, 'unavailable') : undefined);
    await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_API_FAILED');
    assert.equal(h.state.requests.filter((call) => call.method === 'POST').length, 1);
  });
});
