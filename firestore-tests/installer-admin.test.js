// 安裝精靈「建立首位管理員」步驟，對 Firestore + Auth emulator 實跑。
//
//   cd firestore-tests && npm test
//
// Auth 帳號建立、查詢，以及 Firestore 的 create-only commit 都打真的 emulator；
// emulator 沒有的管理 API（Resource Manager、Auth 設定、資料庫中繼資料）才用
// 固定回應代替。規則用與安裝器相同的 renderRules 產生，驗證這份 profile 在規則
// 眼中真的是 admin，而一般帳號不是。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { renderRules } from '../scripts/prepare-deployment.mjs';
import { createInstallationPlan } from '../scripts/installer/core.mjs';
import { createGoogleInstaller } from '../scripts/installer/google.mjs';
import { sha256 } from '../scripts/installer/shared.mjs';

const FIRESTORE = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8181';
const AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9199';
const OPERATOR = 'operator@example.invalid';
// Separate project so this file never touches rules.test.js data.
const plan = {
  ...createInstallationPlan({
    appName: '測試教會', shortName: '同工助手', timeZone: 'Asia/Taipei', region: 'asia-east1',
    services: [{ label: '主日', name: '主日崇拜', weekday: 7 }, { label: '週間', name: '週間聚會', weekday: 3 }],
    adminName: '測試管理員', adminEmail: 'admin@example.invalid', cloudflareAccountId: '0'.repeat(32),
  }, { googleEmail: OPERATOR, accounts: [{ id: '0'.repeat(32) }] }, { runId: '5f6e7d8c-9b0a-4c1d-8e2f-3a4b5c6d7e8f', sourceRevision: 'emulator' }),
  activationEmailConfirmed: true,
};
const { projectId } = plan;
const adminUid = `install-${sha256(plan.runId).slice(0, 40)}`;
const runLabel = sha256(plan.runId).slice(0, 32);
const databaseName = `projects/${projectId}/databases/(default)`;
let testEnv;
let runDir;

// withSecurityRulesDisabled does not return the callback's value.
async function readProfile() {
  let snapshot;
  await testEnv.withSecurityRulesDisabled(async (ctx) => { snapshot = await getDoc(doc(ctx.firestore(), 'users', adminUid)); });
  return snapshot;
}

const json = (body, status = 200) => new Response(JSON.stringify(body), { status });

// Real emulator for Auth accounts and Firestore documents; fixed answers for
// the management APIs the emulators do not provide.
async function fetchImpl(url, init) {
  const { hostname, pathname, search } = new URL(url);
  if (hostname === 'cloudresourcemanager.googleapis.com') {
    return json({ name: 'projects/123456789', projectId, state: 'ACTIVE', labels: { 'church-install': runLabel } });
  }
  if (hostname === 'identitytoolkit.googleapis.com' && pathname.startsWith('/admin/v2/')) {
    return json({ name: `projects/${projectId}/config`, subtype: 'FIREBASE_AUTH', signIn: { email: { enabled: true, passwordRequired: true } }, authorizedDomains: [] });
  }
  if (hostname === 'firestore.googleapis.com' && decodeURIComponent(pathname) === `/v1/${databaseName}`) {
    return json({ name: databaseName, uid: 'emulator-database', locationId: plan.region, type: 'FIRESTORE_NATIVE' });
  }
  const target = hostname === 'firestore.googleapis.com'
    ? `http://${FIRESTORE}${pathname}${search}`
    : hostname === 'identitytoolkit.googleapis.com' ? `http://${AUTH}/identitytoolkit.googleapis.com${pathname}${search}` : null;
  assert.ok(target, `unexpected API ${hostname}`);
  // "owner" is the emulators' admin token, like an operator's IAM credentials.
  return fetch(target, { ...init, headers: { ...init.headers, Authorization: 'Bearer owner' } });
}

const command = async (_file, args) => {
  if (args[0] === 'config') return { stdout: '{}', stderr: '' };
  if (args[1] === 'list') return { stdout: JSON.stringify([{ account: OPERATOR, status: 'ACTIVE' }]), stderr: '' };
  return { stdout: 'owner\n', stderr: '' };
};

// State after the earlier installer steps, as the core would have recorded it.
function context() {
  const checkpoint = {
    resources: { googleProject: { projectId, projectNumber: '123456789', runLabel }, database: { name: databaseName, uid: 'emulator-database', locationId: plan.region } },
    intents: { googleProject: { projectId, runLabel }, database: { uid: 'emulator-database' } },
  };
  return {
    plan, runDir, checkpoint, transient: {}, emit() {}, signal: undefined,
    save: async (patch) => { for (const [section, value] of Object.entries(patch)) Object.assign(checkpoint[section] ??= {}, value); },
  };
}

async function resetEmulators() {
  await fetch(`http://${FIRESTORE}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: 'DELETE' });
  await fetch(`http://${AUTH}/emulator/v1/projects/${projectId}/accounts`, { method: 'DELETE' });
}

before(async () => {
  runDir = await mkdtemp(path.join(os.tmpdir(), 'installer-admin-'));
  const [host, port] = FIRESTORE.split(':');
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules: renderRules(readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), plan.churchConfig), host, port: Number(port) },
  });
});
after(async () => { await testEnv?.cleanup(); await rm(runDir, { recursive: true, force: true }); });

test('creates the Auth user and create-only admin profile that the generated rules treat as admin', async () => {
  await resetEmulators();
  const google = createGoogleInstaller({ fetchImpl, command, delay: async () => {} });
  const step = context();
  await google.execute('admin', step);
  assert.equal(step.checkpoint.resources.admin.uid, adminUid);

  const profile = (await readProfile()).data();
  assert.equal(profile.role, 'admin');
  assert.equal(profile.email, 'admin@example.invalid');
  // Sign-in uses the email; the username is only a label.
  assert.equal(profile.username, '測試管理員');
  assert.deepEqual(profile.zoneTypes, ['service1', 'service2']);

  // Resuming the same step recognises its own profile and writes nothing new.
  await google.execute('admin', step);
  assert.equal((await readProfile()).data().role, 'admin');

  const admin = testEnv.authenticatedContext(adminUid).firestore();
  const member = testEnv.authenticatedContext('someone-else').firestore();
  const staff = { id: 'staff-1', name: '同工', email: 'staff@example.invalid', username: '同工', role: 'member', zones: [] };
  await assertSucceeds(setDoc(doc(admin, 'users', 'staff-1'), staff));
  await assertFails(setDoc(doc(member, 'users', 'someone-else'), { ...staff, id: 'someone-else', role: 'admin' }));
  // Once other people's data exists, resuming refuses rather than touching it.
  await assert.rejects(google.execute('admin', step), /其他使用者資料/);

});

test('refuses to adopt a project that already has another Auth account', async () => {
  await resetEmulators();
  const created = await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts`, {
    method: 'POST', headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
    body: JSON.stringify({ localId: 'existing-user', email: 'existing@example.invalid' }),
  });
  assert.equal(created.status, 200);
  const google = createGoogleInstaller({ fetchImpl, command, delay: async () => {} });
  await assert.rejects(google.execute('admin', context()), /其他 Firebase Auth 帳號/);
  assert.equal((await readProfile()).exists(), false);
});

test('never overwrites a profile that appeared outside this installation', async () => {
  await resetEmulators();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', adminUid), { id: adminUid, name: '別人', email: 'other@example.invalid', username: '別人', role: 'member', zones: [] });
  });
  const google = createGoogleInstaller({ fetchImpl, command, delay: async () => {} });
  await assert.rejects(google.execute('admin', context()), /其他使用者資料|不覆寫/);
  assert.equal((await readProfile()).data().role, 'member');
});
