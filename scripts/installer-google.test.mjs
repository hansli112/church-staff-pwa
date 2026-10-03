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
    if (['firebase', 'firestore', 'identitytoolkit', 'firebaserules', 'iam'].includes(host)) {
      assert.equal(init.headers['x-goog-user-project'], projectId);
    } else assert.equal(init.headers['x-goog-user-project'], undefined);
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
        return response(200, { name: 'operations/workflows/ZmIyMjgwYWUtMzM0Mi00NmI0LTkzYjctNjQwMjM3MzFiNjQy', done: true, response: state.firebase });
      }
      if (pathname.endsWith('/webApps') && init.method === 'GET') return response(200, { apps: state.apps });
      if (pathname.endsWith('/webApps') && init.method === 'POST') {
        assert.ok(context.checkpoint.intents.webApp);
        state.apps.push({ ...body, name: `${project}/webApps/1:123456789:web:install`, appId: '1:123456789:web:install', projectId, state: 'ACTIVE' });
        return response(200, { name: 'operations/workflows/YjM5MDBkNGEtZTYwNi00YWFhLWE5YzQtNzU2YTY5YWI2ZTBh', done: true, response: state.apps[0] });
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
          if (body.notification) {
            assert.equal(parsed.search, '?updateMask=notification.sendEmail.resetPasswordTemplate.senderDisplayName');
            state.authConfig.notification = body.notification;
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
        assert.equal(init.headers['X-Firebase-Locale'], 'zh-TW', 'the password mail is sent in Chinese');
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

test('a new project ID can be created when Google returns 403 for its first GET', async (t) => {
  const h = await setup(t);
  h.setInterceptor((call, state) => call.host === 'cloudresourcemanager' && call.pathname === `/v3/${project}` &&
    call.method === 'GET' && !state.project ? response(403, { error: { status: 'PERMISSION_DENIED', details: [{ reason: 'IAM_PERMISSION_DENIED' }] } }) : undefined);
  await h.adapter.execute('google-project', h.context);
  assert.deepEqual(h.state.requests.slice(0, 2).map(({ method, pathname }) => [method, pathname]),
    [['GET', `/v3/${project}`], ['POST', '/v3/projects']]);
  assert.equal(h.context.checkpoint.resources.googleProject.projectId, projectId);
});

test('an inaccessible existing project ID is not adopted after a 403 GET', async (t) => {
  const h = await setup(t);
  let createCalls = 0;
  h.setInterceptor((call) => {
    if (call.host !== 'cloudresourcemanager') return undefined;
    if (call.pathname === `/v3/${project}` && call.method === 'GET') return error(403, 'PERMISSION_DENIED');
    if (call.pathname === '/v3/projects' && call.method === 'POST') {
      createCalls++;
      assert.deepEqual(call.body.labels, { 'church-install': runLabel });
      return error(409, 'ALREADY_EXISTS');
    }
  });
  await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_RESOURCE_CONFLICT');
  assert.equal(createCalls, 1);
  assert.equal(h.context.checkpoint.resources.googleProject, undefined);
  h.setInterceptor(undefined);
  h.state.project = { name: 'projects/987654321', projectId, state: 'ACTIVE', labels: { 'church-install': runLabel } };
  const before = h.state.requests.length;
  await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_RESOURCE_CONFLICT');
  assert.deepEqual(h.state.requests.slice(before).map(({ method, pathname }) => [method, pathname]), [['GET', `/v3/${project}`]]);
  assert.equal(h.context.checkpoint.resources.googleProject, undefined);
});

test('a 403 after a prior create intent never resends an unverified POST', async (t) => {
  const h = await setup(t);
  h.context.checkpoint.intents.googleProject = { projectId, runLabel, at: new Date(fixedNow).toISOString() };
  h.setInterceptor((call) => {
    if (call.pathname === `/v3/${project}` && call.method === 'GET') return error(403, 'PERMISSION_DENIED');
    if (call.pathname === '/v3/projects' && call.method === 'POST') assert.fail('must not repeat create');
  });
  await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_PERMISSION_REQUIRED');
});

test('an unacknowledged project create is not replayed after a 404', async (t) => {
  const h = await setup(t);
  h.context.checkpoint.intents.googleProject = { projectId, runLabel, at: new Date(fixedNow).toISOString() };
  h.setInterceptor((call) => {
    if (call.pathname === '/v3/projects' && call.method === 'POST') assert.fail('must not repeat unacknowledged create');
  });
  await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_RESOURCE_CONFLICT');
  assert.equal(h.context.checkpoint.resources.googleProject, undefined);
});

const creates = (h, suffix) => h.state.requests.filter((call) => call.method === 'POST' && call.pathname.endsWith(suffix)).length;

test('Firebase workflow operations are saved and polled on the Firebase host only', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  const name = 'operations/workflows/ZmIyMjgwYWUtMzM0Mi00NmI0LTkzYjctNjQwMjM3MzFiNjQy';
  let polls = 0;
  h.setInterceptor((call, state) => {
    if (call.pathname.endsWith(':addFirebase')) return response(200, { name, done: false });
    if (call.host === 'firebase' && call.pathname === `/v1beta1/${name}`) {
      polls++;
      state.firebase = { projectId, projectNumber: '123456789' };
      return response(200, { name, done: true, response: state.firebase });
    }
  });
  await h.adapter.execute('firebase', h.context);
  assert.equal(polls, 1);
  assert.equal(h.context.checkpoint.intents.firebase.operation, name);
  assert.equal(h.context.checkpoint.resources.firebase.projectId, projectId);
});

test('operation names outside the expected shape or project stop before any poll', async (t) => {
  for (const [label, reply, code] of [
    ['path traversal', { name: 'operations/workflows/../../v1/projects/other', done: false }, 'GOOGLE_INVALID_RESPONSE'],
    ['other resource path', { name: 'projects/other-project/operations/x', done: false }, 'GOOGLE_INVALID_RESPONSE'],
    ['finished for another project', { name: 'operations/workflows/abc', done: true, response: { projectId: 'other-project' } }, 'GOOGLE_RESOURCE_CONFLICT'],
  ]) await t.test(label, async (t) => {
    const h = await setup(t);
    await h.through('google-project');
    h.setInterceptor((call) => call.pathname.endsWith(':addFirebase') ? response(200, reply) : undefined);
    await rejectsCode(h.adapter.execute('firebase', h.context), code);
    assert.ok(h.state.requests.every((call) => !call.pathname.includes('/operations/')));
    assert.equal(h.context.checkpoint.resources.firebase, undefined);
    if (code !== 'GOOGLE_INVALID_RESPONSE') return;
    // The POST may have been accepted: a resume must read back, never resend.
    h.setInterceptor(undefined);
    await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_REQUEST_UNCONFIRMED');
    assert.equal(creates(h, ':addFirebase'), 1);
  });
});

test('an addFirebase whose reply was lost is never resent; resume adopts it once readable', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  h.setInterceptor((call, state) => {
    if (call.pathname.endsWith(':addFirebase')) {
      state.firebase = { projectId, projectNumber: '123456789' };
      throw new TypeError('socket hang up');
    }
  });
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_CONNECTION_INTERRUPTED');
  assert.equal(h.context.checkpoint.intents.firebase.requested, true);
  h.setInterceptor((call) => call.pathname === `/v1beta1/${project}` ? response(404) : undefined);
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_REQUEST_UNCONFIRMED');
  h.setInterceptor(undefined);
  await h.adapter.execute('firebase', h.context);
  assert.equal(creates(h, ':addFirebase'), 1);
  assert.equal(h.context.checkpoint.resources.firebase.projectId, projectId);
});

test('a Web App create whose reply was lost is adopted from the list, never created twice', async (t) => {
  const h = await setup(t);
  await h.through('auth');
  let dropped = false;
  h.setInterceptor((call, state) => {
    if (call.host === 'firebase' && call.method === 'POST' && call.pathname.endsWith('/webApps') && !dropped) {
      dropped = true;
      state.apps.push({ ...call.body, name: `${project}/webApps/1:123456789:web:install`, appId: '1:123456789:web:install', projectId, state: 'ACTIVE' });
      throw new TypeError('socket hang up');
    }
  });
  await rejectsCode(h.adapter.execute('web-app', h.context), 'GOOGLE_CONNECTION_INTERRUPTED');
  await h.adapter.execute('web-app', h.context);
  assert.equal(h.state.apps.length, 1);
  assert.equal(creates(h, '/webApps'), 1);
  assert.equal(h.context.checkpoint.resources.webApp.appId, '1:123456789:web:install');
});

test('a definite 4xx refusal lets the same create be retried after the person fixes it', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  h.setInterceptor((call) => call.pathname.endsWith(':addFirebase') ? error(400, 'TERMS_OF_SERVICE_NOT_ACCEPTED') : undefined);
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_TERMS_REQUIRED');
  assert.equal(h.context.checkpoint.intents.firebase.requested, undefined);
  assert.equal(h.context.checkpoint.intents.firebase.lastRequestRejected, true);
  h.setInterceptor(undefined);
  await h.adapter.execute('firebase', h.context);
  assert.equal(creates(h, ':addFirebase'), 2);
});

test('Firebase added in the console before the installer asked is adopted on this run\'s project', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  // The console enables the APIs and adds Firebase in one go.
  ['firebase.googleapis.com', 'firestore.googleapis.com', 'identitytoolkit.googleapis.com', 'firebaserules.googleapis.com']
    .forEach((service) => h.state.enabled.add(service));
  h.state.firebase = { projectId, projectNumber: '123456789' };
  await h.adapter.execute('firebase', h.context);
  assert.equal(creates(h, ':addFirebase'), 0);
  assert.equal(h.context.checkpoint.intents.firebase.addedInConsole, true);
  assert.deepEqual(h.context.checkpoint.resources.firebase, { projectId });
});

test('Firebase on a project with another project number is still refused', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  h.state.firebase = { projectId, projectNumber: '999999999' };
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_RESOURCE_CONFLICT');
});

test('a bare addFirebase 403 is not retried: the next resume sends it again once the project settles', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  let denied = 0;
  h.setInterceptor((call) => call.pathname.endsWith(':addFirebase') && denied++ < 1 ? error(403, 'PERMISSION_DENIED') : undefined);
  await assert.rejects(h.adapter.execute('firebase', h.context), (err) => err.code === 'GOOGLE_TERMS_REQUIRED' && err.message.includes('以前就用過 Firebase'));
  assert.equal(creates(h, ':addFirebase'), 1);
  assert.deepEqual(h.state.delays, []);
  await h.adapter.execute('firebase', h.context);
  assert.equal(creates(h, ':addFirebase'), 2);
  assert.deepEqual(h.context.checkpoint.resources.firebase, { projectId });
});

test('a rate-limited addFirebase asks to resume in a minute, not to raise a quota', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  h.setInterceptor((call) => call.pathname.endsWith(':addFirebase') ? response(429, { error: { status: 'RESOURCE_EXHAUSTED',
    message: 'Quota exceeded', details: [{ reason: 'RATE_LIMIT_EXCEEDED' }] } }) : undefined);
  await assert.rejects(h.adapter.execute('firebase', h.context), (err) =>
    err.code === 'GOOGLE_RATE_LIMITED' && !err.helpUrl && err.message.endsWith('〔技術代碼：firebase 429 RESOURCE_EXHAUSTED RATE_LIMIT_EXCEEDED〕'));
  assert.equal(h.context.checkpoint.intents.firebase.requested, undefined);
  h.setInterceptor(undefined);
  await h.adapter.execute('firebase', h.context);
  assert.equal(creates(h, ':addFirebase'), 2);
});

test('an account that never accepted the Firebase terms is sent to the console, then resumes', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  h.setInterceptor((call) => call.pathname.endsWith(':addFirebase') ? error(403, 'PERMISSION_DENIED') : undefined);
  await assert.rejects(h.adapter.execute('firebase', h.context), (err) =>
    err.code === 'GOOGLE_TERMS_REQUIRED' && err.helpUrl === 'https://console.firebase.google.com/' && err.message.includes(projectId) &&
    err.message.endsWith('〔技術代碼：firebase 403〕'));
  assert.equal(creates(h, ':addFirebase'), 1);
  // The person adds Firebase in the console; the resume adopts it without another create.
  h.setInterceptor(undefined);
  h.state.firebase = { projectId, projectNumber: '123456789' };
  await h.adapter.execute('firebase', h.context);
  assert.equal(creates(h, ':addFirebase'), 1);
  assert.deepEqual(h.context.checkpoint.resources.firebase, { projectId });
});

test('an addFirebase refused with "Firebase Tos Not Accepted" asks for the console at once', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  h.setInterceptor((call) => call.pathname.endsWith(':addFirebase') ? response(403, { error: { status: 'PERMISSION_DENIED',
    message: 'The caller does not have permission', details: [{ detail: '[ORIGINAL ERROR] generic::permission_denied: Firebase Tos Not Accepted' }] } }) : undefined);
  await assert.rejects(h.adapter.execute('firebase', h.context), (err) =>
    err.code === 'GOOGLE_TERMS_REQUIRED' && err.message.includes('將 Firebase 新增到 Google Cloud 專案') && err.message.includes(projectId) &&
    err.message.endsWith('〔技術代碼：firebase 403 PERMISSION_DENIED〕'));
  assert.equal(creates(h, ':addFirebase'), 1);
  assert.deepEqual(h.state.delays, []);
  h.setInterceptor(undefined);
  h.state.firebase = { projectId, projectNumber: '123456789' };
  await h.adapter.execute('firebase', h.context);
  assert.equal(creates(h, ':addFirebase'), 1);
});

test('an addFirebase operation that fails with permission denied is also treated as the terms step', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  h.setInterceptor((call) => call.pathname.endsWith(':addFirebase')
    ? response(200, { name: 'operations/workflows/ZmFpbGVk', done: true, error: { code: 7, message: 'The caller does not have permission' } }) : undefined);
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_TERMS_REQUIRED');
  h.setInterceptor(undefined);
  await h.adapter.execute('firebase', h.context);
  assert.equal(creates(h, ':addFirebase'), 2);
});

test('a server error on create is treated as possibly accepted', async (t) => {
  const h = await setup(t);
  await h.through('google-project');
  h.setInterceptor((call) => call.pathname.endsWith(':addFirebase') ? error(503, 'backend unavailable') : undefined);
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_API_FAILED');
  h.setInterceptor(undefined);
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_REQUEST_UNCONFIRMED');
  assert.equal(creates(h, ':addFirebase'), 1);
});

test('a create stopped before it is sent (expired sign-in) stays retryable', async (t) => {
  let clock = fixedNow;
  let tokenFails = false;
  const h = await setup(t, {
    now: () => (clock += 61_000),
    command: async (file, args) => {
      if (args[0] === 'config') return { stdout: '{}' };
      if (args[1] === 'list') return { stdout: JSON.stringify([{ account: 'operator@example.invalid', status: 'ACTIVE' }]) };
      if (tokenFails) throw new Error('reauth required');
      return { stdout: 'never-log-this-google-token\n' };
    },
  });
  await h.through('google-project');
  h.setInterceptor((call) => {
    if (call.pathname === `/v1beta1/${project}` && call.method === 'GET') tokenFails = true;
  });
  await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_AUTH_REQUIRED');
  assert.equal(creates(h, ':addFirebase'), 0);
  assert.equal(h.context.checkpoint.intents.firebase.requested, undefined);
  h.setInterceptor(undefined);
  tokenFails = false;
  await h.adapter.execute('firebase', h.context);
  assert.equal(creates(h, ':addFirebase'), 1);
});

test('a 408 or 499 on create is treated as possibly accepted', async (t) => {
  for (const status of [408, 499]) await t.test(String(status), async (t) => {
    const h = await setup(t);
    await h.through('google-project');
    h.setInterceptor((call) => call.pathname.endsWith(':addFirebase') ? error(status, 'timeout') : undefined);
    await assert.rejects(h.adapter.execute('firebase', h.context));
    assert.equal(h.context.checkpoint.intents.firebase.requested, true);
    h.setInterceptor(undefined);
    await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_REQUEST_UNCONFIRMED');
    assert.equal(creates(h, ':addFirebase'), 1);
  });
});

test('a project whose create reply was lost is adopted only by its private run label', async (t) => {
  const h = await setup(t);
  h.setInterceptor((call, state) => {
    if (call.pathname === '/v3/projects' && call.method === 'POST') {
      state.project = { ...call.body, name: 'projects/123456789', state: 'ACTIVE', createTime: new Date(fixedNow + 1000).toISOString() };
      return error(503, 'backend unavailable');
    }
  });
  await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_API_FAILED');
  // Not visible yet: wait, never resend.
  const project404 = (call) => call.pathname === `/v3/${project}` && call.method === 'GET' ? error(403, 'PERMISSION_DENIED') : undefined;
  h.setInterceptor(project404);
  await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_REQUEST_UNCONFIRMED');
  h.setInterceptor(undefined);
  await h.adapter.execute('google-project', h.context);
  assert.equal(creates(h, '/v3/projects'), 1);
  assert.equal(h.context.checkpoint.resources.googleProject.projectNumber, '123456789');
  await h.through('firebase');
});

test('a lost create reply never adopts a project with another label or an older creation time', async (t) => {
  for (const [label, change] of [
    ['other label', (p) => { p.labels = { 'church-install': 'someone-else' }; }],
    ['created before our request', (p) => { p.createTime = new Date(fixedNow - 60 * 60_000).toISOString(); }],
  ]) await t.test(label, async (t) => {
    const h = await setup(t);
    h.setInterceptor((call, state) => {
      if (call.pathname === '/v3/projects' && call.method === 'POST') {
        state.project = { ...call.body, name: 'projects/123456789', state: 'ACTIVE', createTime: new Date(fixedNow).toISOString() };
        change(state.project);
        return error(503, 'backend unavailable');
      }
    });
    await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_API_FAILED');
    h.setInterceptor(undefined);
    await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_RESOURCE_CONFLICT');
    assert.equal(h.context.checkpoint.resources.googleProject, undefined);
  });
});

test('a just-enabled API answering SERVICE_DISABLED is waited out, not reported as a permission problem', async (t) => {
  const h = await setup(t);
  await h.through('firebase');
  let refusals = 0;
  const disabled = () => response(403, { error: { status: 'PERMISSION_DENIED', message: 'Cloud Firestore API has not been used in project before or it is disabled.',
    details: [{ reason: 'SERVICE_DISABLED' }] } });
  h.setInterceptor((call) => {
    if (call.host === 'firestore' && call.method === 'GET' && refusals < 2) { refusals++; return disabled(); }
  });
  await h.adapter.execute('database', h.context);
  assert.equal(refusals, 2);
  assert.ok(h.state.delays.includes(5000) && h.state.delays.includes(10000));
  h.setInterceptor((call) => call.host === 'firestore' && call.method === 'GET' ? disabled() : undefined);
  await assert.rejects(h.adapter.execute('rules', h.context), (err) => err.code === 'GOOGLE_API_PROPAGATING' &&
    err.message.includes('〔技術代碼：firestore 403 PERMISSION_DENIED SERVICE_DISABLED〕') && !/http|googleapis|Bearer/.test(err.message));
});

test('a project create refused with 403 can be retried; it is still never adopted', async (t) => {
  const h = await setup(t);
  let posts = 0;
  h.setInterceptor((call) => {
    if (call.pathname === `/v3/${project}` && call.method === 'GET' && !h.state.project) return error(403, 'PERMISSION_DENIED');
    if (call.pathname === '/v3/projects' && posts++ === 0) return error(403, 'PERMISSION_DENIED');
  });
  await rejectsCode(h.adapter.execute('google-project', h.context), 'GOOGLE_PERMISSION_REQUIRED');
  assert.equal(h.context.checkpoint.intents.googleProject.lastRequestRejected, true);
  await h.adapter.execute('google-project', h.context);
  assert.equal(posts, 2);
  assert.equal(h.context.checkpoint.resources.googleProject.projectId, projectId);
});

test('connecting Google asks Cloud Shell to authorize the wizard configuration once', async () => {
  const calls = [];
  let authorized = false;
  const adapter = createGoogleInstaller({
    fetchImpl: () => assert.fail('no network'),
    command: async (file, args, options) => {
      calls.push({ args, timeoutMs: options?.timeoutMs });
      if (args[0] === 'config') return { stdout: '{}' };
      if (args[1] === 'list') return { stdout: JSON.stringify(authorized ? [{ account: 'Person@Example.invalid', status: 'ACTIVE' }] : []) };
      assert.deepEqual(args, ['auth', 'print-access-token', '--quiet']);
      authorized = true;
      return { stdout: 'discarded-token\n' };
    },
    authorizeTimeoutMs: 1234,
  });
  assert.deepEqual(await adapter.authorize(), { email: 'person@example.invalid' });
  assert.equal(calls.filter((call) => call.args[1] === 'print-access-token').length, 1);
  assert.equal(calls.find((call) => call.args[1] === 'print-access-token').timeoutMs, 1234);
  calls.length = 0;
  assert.deepEqual(await adapter.authorize(), { email: 'person@example.invalid' });
  assert.equal(calls.some((call) => call.args[1] === 'print-access-token'), false);
});

test('an untrusted (ephemeral) Cloud Shell explains how to leave ephemeral mode', async (t) => {
  const previous = process.env.TRUSTED_ENVIRONMENT;
  process.env.TRUSTED_ENVIRONMENT = 'false';
  t.after(() => { if (previous === undefined) delete process.env.TRUSTED_ENVIRONMENT; else process.env.TRUSTED_ENVIRONMENT = previous; });
  const adapter = createGoogleInstaller({
    fetchImpl: () => assert.fail('no network'),
    command: async (file, args) => {
      if (args[0] === 'config') return { stdout: '{}' };
      if (args[1] === 'list') return { stdout: '[]' };
      assert.fail('no token request in an untrusted Cloud Shell');
    },
  });
  await assert.rejects(adapter.authorize(), (err) => err.code === 'GOOGLE_AUTH_REQUIRED' && /暫時模式.*停用/.test(err.message));
});

test('a declined Cloud Shell authorization explains how to retry', async () => {
  const adapter = createGoogleInstaller({
    fetchImpl: () => assert.fail('no network'),
    command: async (file, args) => {
      if (args[0] === 'config') return { stdout: '{}' };
      if (args[1] === 'list') return { stdout: '[]' };
      throw new Error('declined');
    },
  });
  await assert.rejects(adapter.authorize(), (err) => err.code === 'GOOGLE_AUTH_REQUIRED' && /Authorize/.test(err.message));
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

test('project creation without a saved operation adopts only its matching run label, without resending', async (t) => {
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
  assert.equal(h.context.checkpoint.resources.googleProject.projectNumber, '123456789');
  assert.equal(h.context.checkpoint.intents.googleProject.adoptedByLabel, true);
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
    // The site is published before this step, so its login page already
    // offers 忘記密碼 — simpler than the Firebase console, and no link needed.
    assert.equal(err.helpUrl, undefined);
    assert.match(err.message, /忘記密碼/);
    assert.doesNotMatch(err.message, /Authentication → Users/);
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
  for (const phase of ['googleServices', 'firebase']) {
    await t.test(`pending ${phase} operation reports progress and resumes without another write`, async (t) => {
      let clock = fixedNow;
      let completed = false;
      const h = await setup(t, { now: () => clock, delay: async (ms) => { h.state.delays.push(ms); clock += ms; } });
      await h.through('google-project');
      const services = ['firebase.googleapis.com', 'firestore.googleapis.com', 'identitytoolkit.googleapis.com', 'firebaserules.googleapis.com'];
      if (phase === 'firebase') services.forEach((service) => h.state.enabled.add(service));
      const operationName = phase === 'googleServices' ? 'operations/services-pending' : 'operations/firebase-pending';
      const createPath = phase === 'googleServices' ? '/services:batchEnable' : ':addFirebase';
      h.setInterceptor((call) => {
        if (call.method === 'POST' && call.pathname.endsWith(createPath)) return response(200, { name: operationName, done: false });
        if (call.pathname === `/v1/${operationName}` || call.pathname === `/v1beta1/${operationName}`) {
          if (completed) {
            if (phase === 'googleServices') services.forEach((service) => h.state.enabled.add(service));
            else h.state.firebase = { projectId, projectNumber: '123456789' };
            return response(200, { name: operationName, done: true, response: {} });
          }
          return response(200, { name: operationName, done: false });
        }
      });
      await rejectsCode(h.adapter.execute('firebase', h.context), 'GOOGLE_OPERATION_PENDING');
      assert.equal(h.context.checkpoint.intents[phase].operation, operationName);
      assert.ok(clock - fixedNow >= 180_000);
      assert.ok(h.state.delays.every((ms) => ms <= 8000));
      const messages = h.context.events.map((event) => event.message);
      assert.ok(messages.some((message) => message.includes('正在核對 Firebase 所需')));
      assert.ok(messages.some((message) => message.includes('已等待') && /[1-9]\d* 秒/.test(message)));
      assert.doesNotMatch(JSON.stringify(messages), /never-log-this-google-token|never-persist-api-key|services-pending|firebase-pending/);
      completed = true;
      await h.adapter.execute('firebase', h.context);
      assert.equal(h.context.checkpoint.resources.firebase.projectId, projectId);
      assert.equal(h.state.requests.filter((call) => call.method === 'POST' && call.pathname.endsWith(createPath)).length, 1);
    });
  }
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

// ---------------------------------------------------------------------------
// Update mode
// ---------------------------------------------------------------------------

test('update reads back the web config and replaces only this install\'s rules, only when they change', async (t) => {
  const { adapter, context, state, through } = await setup(t);
  await through('activation');
  context.transient = {};
  assert.deepEqual(await adapter.update('inspect', context), { region: 'asia-east1' });
  assert.equal(context.transient.firebaseConfig.projectId, projectId);
  assert.equal(context.transient.firebaseConfig.apiKey, 'never-persist-api-key');

  const rulesetsBefore = state.rulesets.size;
  assert.deepEqual(await adapter.update('rules', context), { rules: { unchanged: true } });
  assert.equal(state.rulesets.size, rulesetsBefore, 'identical rules are not republished');

  // A new service changes the generated rules; the update releases them.
  context.plan.churchConfig = { ...config, services: [...config.services, { id: 'service9', label: '禱告', name: '禱告會', weekday: 3, enabled: true }] };
  const changed = renderRules(await readFile(new URL('../firestore.rules', import.meta.url), 'utf8'), context.plan.churchConfig);
  await writeFile(path.join(context.runDir, 'deployment/firestore.rules'), changed);
  assert.deepEqual(await adapter.update('rules', context), { rules: { unchanged: false } });
  const live = state.rulesets.get(state.release.rulesetName).source.files[0].content;
  assert.ok(live.startsWith(`// church-install: ${runLabel}\n`));
  assert.ok(live.includes("'service9'") || live.includes('"service9"'));
  // Nothing else is written by an update: no user, profile or mail.
  assert.equal(state.users.length, 1);
  assert.equal(state.sent, 1);
});

test('update refuses a Google project that does not carry this install\'s label', async (t) => {
  const { adapter, context, state, through } = await setup(t);
  await through('activation');
  state.project = { ...state.project, labels: { 'church-install': 'someone-else' } };
  await rejectsCode(adapter.update('inspect', context), 'GOOGLE_RESOURCE_CONFLICT');
  await rejectsCode(adapter.update('rules', context), 'GOOGLE_RESOURCE_CONFLICT');
});

test('update never overwrites rules someone edited by hand', async (t) => {
  const { adapter, context, state, through } = await setup(t);
  await through('activation');
  const name = state.release.rulesetName;
  const edited = structuredClone(state.rulesets.get(name));
  edited.source.files[0].content = edited.source.files[0].content.replace(/^\/\/ church-install: [^\n]+\n/, '');
  state.rulesets.set(name, edited);
  const before = state.rulesets.size;
  await rejectsCode(adapter.update('rules', context), 'GOOGLE_RESOURCE_CONFLICT');
  assert.equal(state.rulesets.size, before);
});

test('update adds the custom domain to Firebase Auth once and keeps every existing domain', async (t) => {
  const { adapter, context, state, through } = await setup(t);
  await through('activation');
  const before = [...state.authConfig.authorizedDomains];
  context.plan = { ...context.plan, customDomain: 'staff.hope-church.org' };
  await adapter.update('domain', context);
  assert.deepEqual(state.authConfig.authorizedDomains, [...before, 'staff.hope-church.org']);
  const patches = state.requests.filter((call) => call.method === 'PATCH' && call.pathname.endsWith('/config')).length;
  await adapter.update('domain', context);
  assert.equal(state.requests.filter((call) => call.method === 'PATCH' && call.pathname.endsWith('/config')).length, patches);
});

test('a new project whose Firestore IAM is still propagating waits and retries instead of blaming permissions', async (t) => {
  const { adapter, context, state, setInterceptor, through } = await setup(t);
  await through('firebase');
  let denied = 0;
  setInterceptor((call) => {
    if (call.host === 'firestore' && denied < 2) { denied++; return error(403, 'PERMISSION_DENIED'); }
  });
  await adapter.execute('database', context);
  assert.equal(denied, 2);
  assert.ok(state.db, 'database created after the retries');
  assert.equal(state.delays.filter((ms) => ms === 15_000).length, 2);
  assert.ok(context.events.some((event) => event.message?.includes('自動重試')));
});

test('a 403 that outlasts the grace retries says to resume later, not to ask an administrator', async (t) => {
  const { adapter, context, setInterceptor, through } = await setup(t);
  await through('firebase');
  setInterceptor((call) => call.host === 'firestore' ? error(403, 'PERMISSION_DENIED') : undefined);
  await rejectsCode(adapter.execute('database', context), 'GOOGLE_API_PROPAGATING');
});

test('an old project answering 403 still reports a real permission problem', async (t) => {
  const { adapter, context, setInterceptor, through } = await setup(t);
  await through('firebase');
  context.checkpoint.resources.googleProject.createTime = new Date(fixedNow - 60 * 60_000).toISOString();
  setInterceptor((call) => call.host === 'firestore' ? error(403, 'PERMISSION_DENIED') : undefined);
  await rejectsCode(adapter.execute('database', context), 'GOOGLE_PERMISSION_REQUIRED');
});

test('the password mail names the church as its sender, and a refusal does not stop the install', async (t) => {
  const named = await setup(t);
  await named.through('activation');
  assert.equal(named.state.authConfig.notification.sendEmail.resetPasswordTemplate.senderDisplayName, config.appName);
  const refused = await setup(t);
  refused.setInterceptor((call) => call.method === 'PATCH' && call.body?.notification ? error(400, 'INVALID_CONFIG') : undefined);
  await refused.through('activation');
  assert.equal(refused.state.sent, 1);
  assert.ok(refused.context.events.some((event) => event.message?.includes('寄件者名稱沒有設定成功')));
});

// ---------------------------------------------------------------------------
// Account management (both modes)
// ---------------------------------------------------------------------------

const accountEmail = `church-accounts@${projectId}.iam.gserviceaccount.com`;
const accountPath = `/v1/projects/${projectId}/serviceAccounts/${accountEmail}`;
const PRIVATE_KEY = '-----BEGIN PRIVATE KEY-----never-persist-account-key-----END PRIVATE KEY-----';

// IAM, the project policy and enabling the IAM API, on top of setup()'s fakes.
function fakeIam(h, { keys = [], account, bindings = [{ role: 'roles/owner', members: ['user:operator@example.invalid'] }], refuseKeys } = {}) {
  const iam = { account, keys: [...keys], policy: { version: 1, etag: 'BwX1', bindings }, created: 0, setPolicy: [], deleted: [] };
  iam.interceptor = (call) => {
    if (call.host === 'serviceusage' && call.pathname.endsWith('/services/iam.googleapis.com:enable')) {
      h.state.enabled.add('iam.googleapis.com');
      return response(200, { name: 'operations/acat.iam-enable', done: true, response: {} });
    }
    if (call.host === 'cloudresourcemanager' && call.pathname === `/v3/${project}:getIamPolicy`) return response(200, iam.policy);
    if (call.host === 'cloudresourcemanager' && call.pathname === `/v3/${project}:setIamPolicy`) {
      assert.equal(call.body.policy.etag, iam.policy.etag, 'sent back with the etag that was read');
      iam.setPolicy.push(call.body);
      iam.policy = { ...call.body.policy, etag: 'BwX2' };
      return response(200, iam.policy);
    }
    if (call.host !== 'iam') return undefined;
    if (call.pathname === accountPath && call.method === 'GET') return iam.account ? response(200, iam.account) : response(404);
    if (call.pathname === `/v1/projects/${projectId}/serviceAccounts` && call.method === 'POST') {
      assert.equal(call.body.accountId, 'church-accounts');
      iam.account = { email: accountEmail, projectId, name: `projects/${projectId}/serviceAccounts/${accountEmail}` };
      return response(200, iam.account);
    }
    if (call.pathname === `${accountPath}/keys` && call.method === 'GET') {
      assert.equal(call.search, '?keyTypes=USER_MANAGED');
      return response(200, { keys: iam.keys.map((id) => ({ name: `projects/${projectId}/serviceAccounts/${accountEmail}/keys/${id}` })) });
    }
    if (call.pathname === `${accountPath}/keys` && call.method === 'POST') {
      if (refuseKeys) return response(400, { error: { status: 'FAILED_PRECONDITION', message: 'Key creation is not allowed on this service account.' } });
      const id = `${++iam.created}`.padStart(40, 'a');
      iam.keys.push(id);
      const file = { type: 'service_account', project_id: projectId, private_key_id: id, private_key: PRIVATE_KEY, client_email: accountEmail };
      return response(200, { name: `projects/${projectId}/serviceAccounts/${accountEmail}/keys/${id}`,
        privateKeyData: Buffer.from(JSON.stringify(file)).toString('base64') });
    }
    if (call.pathname.startsWith(`${accountPath}/keys/`) && call.method === 'DELETE') {
      const id = call.pathname.split('/').at(-1);
      iam.deleted.push(id);
      iam.keys = iam.keys.filter((key) => key !== id);
      return response(200, {});
    }
    return undefined;
  };
  h.setInterceptor(iam.interceptor);
  return iam;
}

test('account management: a service account that may only manage sign-ins, and a key that is never saved', async (t) => {
  const h = await setup(t);
  await h.through('admin');
  const iam = fakeIam(h);
  const key = await h.adapter.newAccountAdminKey(h.context, { configured: false });
  assert.ok(h.state.enabled.has('iam.googleapis.com'));
  assert.equal(JSON.parse(key.json).client_email, accountEmail);
  assert.equal(key.id, iam.keys[0]);
  // Every binding that was there is sent back; one member is added.
  assert.equal(iam.setPolicy.length, 1);
  assert.deepEqual(iam.policy.bindings, [
    { role: 'roles/owner', members: ['user:operator@example.invalid'] },
    { role: 'roles/firebaseauth.admin', members: [`serviceAccount:${accountEmail}`] },
  ]);
  const persisted = JSON.stringify([h.context.snapshots, h.context.checkpoint, h.context.events]);
  assert.equal(persisted.includes('never-persist-account-key'), false);

  // Stored on the site (configured) with exactly that key: nothing to do.
  assert.equal(await h.adapter.newAccountAdminKey(h.context, { configured: true }), null);
  assert.equal(iam.created, 1);
  assert.equal(iam.setPolicy.length, 1, 'an existing grant is not sent again');
});

test('account management redoes a key the site does not hold, and only then retires the others', async (t) => {
  const h = await setup(t);
  await h.through('admin');
  // An earlier run stopped between creating a key and storing it.
  const iam = fakeIam(h, { keys: ['b'.repeat(40), 'c'.repeat(40)],
    account: { email: accountEmail, projectId },
    bindings: [{ role: 'roles/firebaseauth.admin', members: ['user:someone@example.invalid', `serviceAccount:${accountEmail}`] }] });
  const key = await h.adapter.newAccountAdminKey(h.context, { configured: true });
  assert.ok(key, 'two keys: which one the site holds is unknown');
  assert.equal(iam.setPolicy.length, 0);
  assert.deepEqual(iam.deleted, [], 'nothing is retired before the new key is stored');
  await h.adapter.retireOtherAccountAdminKeys(h.context, { keep: key.id });
  assert.deepEqual(iam.keys, [key.id]);
  assert.deepEqual(iam.deleted.sort(), ['b'.repeat(40), 'c'.repeat(40)]);
});

test('an organisation that forbids service account keys skips account management, not the install', async (t) => {
  const h = await setup(t);
  await h.through('admin');
  fakeIam(h, { refuseKeys: true });
  assert.equal(await h.adapter.newAccountAdminKey(h.context, { configured: false }), null);
  assert.ok(h.context.events.some((event) => event.message?.includes('不允許建立服務帳號金鑰')));
});

test('a first install that already published keeps its key; a disabled account is left disabled', async (t) => {
  const h = await setup(t);
  await h.through('admin');
  const iam = fakeIam(h, { keys: ['b'.repeat(40)], account: { email: accountEmail, projectId } });
  h.context.checkpoint.resources.website = 'https://demo-church-site.pages.dev';
  assert.equal(await h.adapter.newAccountAdminKey(h.context, { configured: false }), null);
  assert.equal(iam.created, 0);

  iam.account = { email: accountEmail, projectId, disabled: true };
  delete h.context.checkpoint.resources.website;
  assert.equal(await h.adapter.newAccountAdminKey(h.context, { configured: false }), null);
  assert.equal(iam.created, 0);
  assert.ok(h.context.events.some((event) => event.message?.includes('被停用')));
});

test('update mode sets account management up on a site installed before it', async (t) => {
  const h = await setup(t);
  await h.through('activation');
  h.context.transient = {};
  const iam = fakeIam(h);
  const key = await h.adapter.newAccountAdminKey(h.context, { update: true, configured: false });
  assert.ok(key);
  assert.equal(iam.created, 1);
  // A Google project without this install's label is never touched.
  h.state.project.labels = { 'church-install': 'someone-else' };
  await rejectsCode(h.adapter.newAccountAdminKey(h.context, { update: true, configured: false }), 'GOOGLE_RESOURCE_CONFLICT');
  assert.equal(iam.created, 1);
});

test('a service account Google has not finished creating is waited for, not reported as a failure', async (t) => {
  const h = await setup(t);
  await h.through('admin');
  const iam = fakeIam(h);
  let refused = 0;
  h.setInterceptor((call, ...rest) => {
    if (call.pathname.endsWith(':setIamPolicy') && refused < 2) {
      refused++;
      return response(400, { error: { status: 'INVALID_ARGUMENT', message: `Service account ${accountEmail} does not exist.` } });
    }
    return iam.interceptor(call, ...rest);
  });
  const key = await h.adapter.newAccountAdminKey(h.context, { configured: false });
  assert.ok(key);
  assert.equal(refused, 2);
  assert.equal(iam.setPolicy.length, 1);
  assert.equal(h.state.delays.filter((ms) => ms === 10_000).length, 2);
});
