// Only provisions resources inside the project created by this installation.
// Importing/constructing this adapter never reads credentials or contacts Google.
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';
import { bootstrap, buildAdminProfile, enabledServiceIds, firestoreValue } from '../bootstrap-admin.mjs';
import { renderRules } from '../prepare-deployment.mjs';
import { runCommand } from './process.mjs';
import { canonical, fingerprint, sha256 as hash, stepIdsFor } from './shared.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const hosts = new Set(['cloudresourcemanager', 'serviceusage', 'firebase', 'firestore', 'identitytoolkit', 'firebaserules']);
const steps = stepIdsFor('google');
const projectPattern = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
// Firestore REST omits empty repeated fields on read: a written
// {arrayValue:{values:[]}} comes back as {arrayValue:{}} (same for empty maps).
// Compare documents in that read-back form, or every profile with an empty
// list would look like someone else's data.
function readBackForm(value) {
  if (Array.isArray(value)) return value.map(readBackForm);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value)
    .filter(([key, entry]) => !(['values', 'fields'].includes(key) &&
      (Array.isArray(entry) ? entry.length === 0 : entry && typeof entry === 'object' && Object.keys(entry).length === 0)))
    .map(([key, entry]) => [key, readBackForm(entry)]));
}
const documentFingerprint = (fields) => fingerprint(readBackForm(fields ?? {}));
const encodedName = (name) => name.split('/').map(encodeURIComponent).join('/');

export class ActionRequired extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'ActionRequired';
    this.code = code;
    this.safeToDisplay = true;
    this.actionRequired = true;
  }
}

function stop(code, message) { throw new ActionRequired(code, message); }
function conflict(message = '雲端資源已存在或被其他操作變更；為避免接管既有站，已停止。請核對本次安裝紀錄。') {
  stop('GOOGLE_RESOURCE_CONFLICT', message);
}

// Never expose provider messages, request URLs, command output or response bodies.
function cloudError(status, error = {}, authSetup = false) {
  const reason = `${error.status ?? ''} ${error.message ?? ''} ${canonical(error.details ?? [])}`.toUpperCase();
  if (authSetup && (status === 404 || /CONFIGURATION_NOT_FOUND|PROJECT_NOT_FOUND|OPERATION_NOT_ALLOWED/.test(reason))) {
    stop('AUTH_SETUP_REQUIRED', '請在本次 Firebase 專案的 Authentication 按「Get started」，不要升級付費方案；完成這一次官方確認後回到此處繼續。');
  }
  if (/BILLING|BLAZE|IDENTITY_PLATFORM.*UPGRADE/.test(reason)) {
    stop('GOOGLE_FREE_TIER_REQUIRED', 'Google 要求付費方案；安裝器不會綁定帳單或升級。請核對免費 Firebase 設定後再繼續。');
  }
  if (/TERMS|TOS_|TOS_NOT|AGREEMENT/.test(reason)) {
    stop('GOOGLE_TERMS_REQUIRED', '請先在 Google Cloud／Firebase 官方網站接受帳號所需條款，再回到此處繼續。');
  }
  if (status === 401 || status === 16) stop('GOOGLE_AUTH_REQUIRED', 'Google 授權已過期或未完成；請重新完成 Cloud Shell 官方授權，再繼續本次安裝。');
  if (status === 429 || status === 8 || /QUOTA|RESOURCE_EXHAUSTED/.test(reason)) {
    stop('GOOGLE_QUOTA_REQUIRED', 'Google 專案或 API 配額不足；請到官方配額頁核對，稍後再繼續。安裝進度已保留。');
  }
  if (status === 403 || status === 7 || /ORG_POLICY|PERMISSION_DENIED/.test(reason)) {
    stop('GOOGLE_PERMISSION_REQUIRED', '目前 Google 帳號缺少建立或設定此專案的權限，或受到組織政策限制。請由組織管理員核對權限；不會切換到其他憑證。');
  }
  if (status === 409 || status === 6 || /ALREADY_EXISTS|EMAIL_EXISTS|DUPLICATE_LOCAL_ID/.test(reason)) conflict();
  stop('GOOGLE_API_FAILED', 'Google API 未完成操作；請稍後續跑以核對實際狀態。未自動刪除或覆寫既有資源。');
}

// One step's view of the plan: derived resource names, a short-lived token
// refreshed on demand, and the checkpoint helpers every step shares.
function openStepSession(context, { fetchImpl, command, delay, now, inspectIdentity }) {
  const { plan, signal } = context;
  if (!projectPattern.test(plan?.projectId ?? '') || !emailPattern.test(plan?.googleEmail ?? '') ||
      typeof plan.runId !== 'string' || !/^[a-zA-Z0-9_-]{8,100}$/.test(plan.runId) ||
      !/^[a-z][a-z0-9-]{1,40}$/.test(plan.region ?? '') ||
      !/^[a-z0-9][a-z0-9-]{0,57}[a-z0-9]$/.test(plan.pagesProject ?? '') ||
      !emailPattern.test(plan.admin?.email ?? '') || !plan.admin?.name || !plan.admin?.username) {
    stop('GOOGLE_INVALID_PLAN', '安裝計畫的專案、地區或管理員資料無效；未讀取憑證或連線。');
  }
  const serviceIds = enabledServiceIds(plan.churchConfig);
  const projectId = plan.projectId;
  const project = `projects/${projectId}`;
  const database = `${project}/databases/(default)`;
  const documents = `${database}/documents`;
  const authPath = `/v1/${project}/accounts`;
  // Matches Firebase CLI's documented admin configuration endpoint; the
  // discovery method path alone omits this prefix. Never try a paid setup API.
  const configPath = `/admin/v2/${project}/config`;
  const runLabel = hash(plan.runId).slice(0, 32);
  const adminUid = `install-${hash(plan.runId).slice(0, 40)}`;
  context.transient ??= {};
  context.checkpoint.resources ??= {};
  // Cloudflare may suffix the name; use the verified subdomain the Pages step saved.
  const pagesDomain = () => {
    const value = context.checkpoint.resources.pagesSubdomain;
    if (typeof value !== 'string' || !/^[a-z0-9][a-z0-9-]{0,62}\.pages\.dev$/.test(value) || !value.startsWith(plan.pagesProject)) {
      stop('GOOGLE_INVALID_PLAN', '尚未取得已核對的網站網址，不能設定登入網域或寄送設定密碼信。');
    }
    return value;
  };
  context.checkpoint.intents ??= {};
  let token;
  let checkedAt = -Infinity;

  async function save(section, key, value) {
    await context.save({ [section]: { [key]: value } });
    // Also support hosts whose save writes durably without mutating the view.
    context.checkpoint[section][key] = value;
  }
  const resource = (key) => context.checkpoint.resources[key];
  const intent = (key) => context.checkpoint.intents[key];
  async function begin(key, value) {
    if (!intent(key)) await save('intents', key, { ...value, at: new Date(now()).toISOString() });
    return intent(key);
  }
  async function credentials() {
    if (token && now() - checkedAt < 60_000) return;
    const identity = await inspectIdentity({ signal });
    if (identity.email !== plan.googleEmail.toLowerCase()) {
      stop('GOOGLE_ACCOUNT_CHANGED', '目前 Google 登入與確認安裝時不同；請回到原帳號再續跑，不會使用其他身分寫入。');
    }
    try {
      token = (await command('gcloud', ['auth', 'print-access-token', `--account=${identity.email}`, '--quiet'], { signal })).stdout.trim();
    } catch {
      signal?.throwIfAborted();
      stop('GOOGLE_AUTH_REQUIRED', '無法取得 Google 短期授權；請重新完成 Cloud Shell 官方授權。');
    }
    if (!token || /\s/.test(token)) stop('GOOGLE_AUTH_REQUIRED', 'Google 短期授權無效；請重新完成官方授權。');
    checkedAt = now();
  }
  async function request(host, pathname, { method = 'GET', body, missing = false, authSetup = false, readOnly = method === 'GET' } = {}) {
    if (!hosts.has(host) || !pathname.startsWith('/') || /[\r\n#]/.test(pathname)) stop('GOOGLE_INVALID_TARGET', 'Google API 目標無效。');
    for (let attempt = 0; attempt < 4; attempt++) {
      signal?.throwIfAborted();
      await credentials();
      let response;
      let data;
      try {
        response = await fetchImpl(`https://${host}.googleapis.com${pathname}`, {
          method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
            ...(host === 'identitytoolkit' ? { 'x-goog-user-project': projectId } : {}) },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }), redirect: 'error',
          signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(30_000)]) : AbortSignal.timeout(30_000),
        });
        const text = await response.text();
        if (text.length > 4 * 1024 * 1024) stop('GOOGLE_INVALID_RESPONSE', 'Google 回應超出預期大小；已停止操作。');
        data = text ? JSON.parse(text) : {};
      } catch (error) {
        signal?.throwIfAborted();
        if (error instanceof ActionRequired) throw error;
        stop('GOOGLE_CONNECTION_INTERRUPTED', 'Google 連線中斷；操作可能已被接受。請續跑核對狀態，不要另建第二個安裝。');
      }
      if (response.ok) return data;
      if (response.status === 404 && missing) return null;
      if (readOnly && (response.status === 429 || response.status >= 500) && attempt < 3) {
        await delay(500 * 2 ** attempt, signal);
        continue;
      }
      cloudError(response.status, data.error, authSetup);
    }
  }
  function operationPath(host, name) {
    const simple = /^operations\/[a-zA-Z0-9_.:-]+$/;
    const firestore = new RegExp(`^projects/${projectId}/databases/\\(default\\)/operations/[a-zA-Z0-9_.:-]+$`);
    if (!(host === 'firestore' ? firestore : simple).test(name ?? '')) stop('GOOGLE_INVALID_RESPONSE', 'Google operation 目標與本次安裝不一致；已停止。');
    return encodedName(name);
  }
  async function wait(host, version, operation, key) {
    if (!operation || typeof operation !== 'object') stop('GOOGLE_INVALID_RESPONSE', 'Google 未回傳預期的 operation。');
    if (operation.name) {
      operationPath(host, operation.name);
      await save('intents', key, { ...intent(key), operation: operation.name });
    }
    const started = now();
    for (let attempt = 0; ; attempt++) {
      if (operation.done) {
        if (operation.error) {
          // A terminal failure is not an uncertain write. Reconcile resources
          // on the next run, then allow a new attempt after permissions/quota
          // are fixed instead of polling the same failed operation forever.
          const { operation: _failed, ...previous } = intent(key);
          await save('intents', key, { ...previous, lastOperationFailed: true });
          cloudError(operation.error.code, operation.error);
        }
        return operation.response;
      }
      if (!operation.name) stop('GOOGLE_INVALID_RESPONSE', 'Google operation 缺少名稱；請續跑核對資源。');
      if (attempt >= 45 || now() - started >= 180_000) stop('GOOGLE_OPERATION_PENDING', 'Google 仍在建立資源；本次 operation 已保存，請稍後續跑。');
      if (attempt % 5 === 0) {
        const label = { googleProject: '新專案', googleServices: 'Firebase 所需 API', firebase: 'Firebase', database: 'Firestore 資料庫' }[key] ?? '雲端資源';
        context.emit?.({ message: `Google 正在準備${label}（本階段已等待 ${Math.floor((now() - started) / 1000)} 秒）` });
      }
      await delay(Math.min(1000 * 2 ** attempt, 8000), signal);
      operation = await request(host, `/${version}/${operationPath(host, operation.name)}`);
    }
  }
  async function createOrWait(host, version, key, pathname, body) {
    const operation = intent(key)?.operation
      ? await request(host, `/${version}/${operationPath(host, intent(key).operation)}`)
      : await request(host, pathname, { method: 'POST', body });
    return wait(host, version, operation, key);
  }
  function checkProject(value) {
    if (!value || !intent('googleProject') || value.projectId !== projectId ||
        value.labels?.['church-install'] !== runLabel || value.state !== 'ACTIVE' ||
        !/^projects\/\d+$/.test(value.name ?? '') ||
        (resource('googleProject') && resource('googleProject').projectNumber !== value.name.split('/')[1])) conflict();
    return value;
  }
  async function ownedProject() {
    return checkProject(await request('cloudresourcemanager', `/v3/${project}`));
  }
  async function noOtherData(requireAdmin = Boolean(resource('admin'))) {
    const db = await request('firestore', `/v1/${encodedName(database)}`);
    if (!intent('database')?.uid || db.name !== database || db.uid !== intent('database').uid ||
        (resource('database') && resource('database').uid !== db.uid) || db.locationId !== plan.region ||
        db.type !== 'FIRESTORE_NATIVE' || (db.databaseEdition && db.databaseEdition !== 'STANDARD')) conflict('Firestore 資料庫身分或地區已變更；不會寫入替換後的資料庫。');
    const collections = await request('firestore', `/v1/${encodedName(documents)}:listCollectionIds`, { method: 'POST', body: { pageSize: 2 }, readOnly: true });
    if (requireAdmin && !(collections.collectionIds ?? []).includes('users')) conflict('本次管理員 profile 已消失；不會自動重新建立或升權。');
    if (collections.nextPageToken || (collections.collectionIds ?? []).some((id) => id !== 'users')) conflict('此專案已有其他 Firestore 資料；首次安裝不會接管或覆寫。');
    if ((collections.collectionIds ?? []).includes('users')) {
      const result = await request('firestore', `/v1/${encodedName(documents)}/users?pageSize=2&showMissing=true`);
      if (!intent('adminProfile') || result.nextPageToken || (result.documents ?? []).length !== 1 ||
          result.documents[0].name !== `${documents}/users/${adminUid}` ||
          documentFingerprint(result.documents[0].fields) !== intent('adminProfile').fieldsFingerprint) conflict('此專案已有其他使用者資料；不會覆寫或升權。');
      const children = await request('firestore', `/v1/${encodedName(documents)}/users/${adminUid}:listCollectionIds`, { method: 'POST', body: { pageSize: 1 }, readOnly: true });
      if (children.nextPageToken || children.collectionIds?.length) conflict('此專案已有使用者子集合資料；首次安裝已停止。');
    }
  }
  function checkAuthUser(user) {
    if (!user || user.localId !== adminUid || user.email?.toLowerCase() !== plan.admin.email.toLowerCase() ||
        user.disabled || user.customAttributes || user.validSince && Number(user.validSince) < 0) conflict('管理員 Auth 身分與本次安裝不一致；不會使用或升權既有帳號。');
    return { localId: user.localId, email: user.email, disabled: false };
  }
  async function onlyOwnAuth() {
    const data = await request('identitytoolkit', `${authPath}:batchGet?maxResults=2`, { authSetup: true });
    if (data.nextPageToken || (data.users ?? []).some((user) => !intent('adminAuth') || user.localId !== adminUid) || (data.users ?? []).length > 1) {
      conflict('此專案已有其他 Firebase Auth 帳號；首次安裝不會接管。');
    }
    return data.users?.length ? checkAuthUser(data.users[0]) : null;
  }
  async function getAuthConfig() {
    const config = await request('identitytoolkit', configPath, { authSetup: true });
    if (![`${project}/config`, `projects/${resource('googleProject')?.projectNumber}/config`].includes(config.name) || config.subtype === 'IDENTITY_PLATFORM' ||
        config.signIn?.phoneNumber?.enabled || config.signIn?.anonymous?.enabled || config.signIn?.allowDuplicateEmails) {
      conflict('Firebase Auth 設定不是預期的免費首次安裝狀態；請核對官方設定，不會自動變更其他登入方式。');
    }
    return config;
  }
  return {
    plan, context, signal, now, serviceIds, projectId, project, database, documents, authPath, configPath, runLabel, adminUid,
    token: () => token, pagesDomain, save, resource, intent, begin, credentials, request, operationPath, wait, createOrWait,
    checkProject, ownedProject, noOtherData, checkAuthUser, onlyOwnAuth, getAuthConfig,
  };
}

// Create the run-labelled Google project, or reconcile a pending create.
async function createProject(s) {
  const { projectId, project, runLabel, save, resource, intent, begin, request, operationPath, wait, createOrWait, checkProject } = s;
  let value = await request('cloudresourcemanager', `/v3/${project}`, { missing: true });
  if (!value) {
    if (resource('googleProject')) conflict('本次建立的 Google 專案已消失；不會自動重新建立或切換目標。');
    await begin('googleProject', { projectId, runLabel });
    await createOrWait('cloudresourcemanager', 'v3', 'googleProject', '/v3/projects', {
      projectId, displayName: 'Church Staff', labels: { 'church-install': runLabel },
    });
    value = await request('cloudresourcemanager', `/v3/${project}`);
  } else if (value.state !== 'ACTIVE' && intent('googleProject')?.operation) {
    await wait('cloudresourcemanager', 'v3', await request('cloudresourcemanager', `/v3/${operationPath('cloudresourcemanager', intent('googleProject').operation)}`), 'googleProject');
    value = await request('cloudresourcemanager', `/v3/${project}`);
  }
  checkProject(value);
  const metadata = { projectId, projectNumber: value.name.split('/')[1], runLabel, createTime: value.createTime };
  await save('resources', 'googleProject', metadata);
  return { googleProject: metadata };
}

// Enable the APIs the app needs and add Firebase to the project.
async function enableFirebase(s) {
  const { owned, projectId, project, save, resource, intent, begin, request, createOrWait } = s;
  const services = ['firebase.googleapis.com', 'firestore.googleapis.com', 'identitytoolkit.googleapis.com', 'firebaserules.googleapis.com'];
  const missing = [];
  s.context.emit?.({ message: '正在核對 Firebase 所需的 Google API…' });
  for (const service of services) {
    const state = await request('serviceusage', `/v1/${owned.name}/services/${service}`);
    if (state.state !== 'ENABLED') missing.push(service);
  }
  if (missing.length) {
    s.context.emit?.({ message: '正在啟用 Firebase 所需的 Google API…' });
    await begin('googleServices', { services: missing });
    await createOrWait('serviceusage', 'v1', 'googleServices', `/v1/${owned.name}/services:batchEnable`, { serviceIds: missing });
    s.context.emit?.({ message: '正在核對 Google API 是否已啟用…' });
    for (const service of services) {
      if ((await request('serviceusage', `/v1/${owned.name}/services/${service}`)).state !== 'ENABLED') stop('GOOGLE_OPERATION_PENDING', 'Google API 仍在啟用；請稍後續跑。');
    }
  }
  s.context.emit?.({ message: '正在核對 Firebase 專案狀態…' });
  let firebase = await request('firebase', `/v1beta1/${project}`, { missing: true });
  if (!firebase) {
    if (resource('firebase')) conflict();
    s.context.emit?.({ message: '正在將 Firebase 加入新專案…' });
    await begin('firebase', { projectId });
    await createOrWait('firebase', 'v1beta1', 'firebase', `/v1beta1/${project}:addFirebase`, {});
    firebase = await request('firebase', `/v1beta1/${project}`);
  }
  if (!intent('firebase') || firebase.projectId !== projectId || String(firebase.projectNumber) !== owned.name.split('/')[1]) conflict();
  await save('resources', 'firebase', { projectId });
  s.context.emit?.({ message: 'Firebase 已準備完成' });
  return { firebase: { projectId } };
}

// Create the (default) Native Firestore database in the confirmed region.
async function createDatabase(s) {
  const { plan, project, database, save, resource, intent, begin, request, operationPath, wait, createOrWait, noOtherData } = s;
  let listing = await request('firestore', `/v1/${project}/databases`);
  if (listing.unreachable?.length || (listing.databases ?? []).some((db) => db.name !== database)) conflict('此專案已有非預期資料庫；首次安裝不會接管。');
  let db = listing.databases?.[0];
  if (!db) {
    if (resource('database')) conflict();
    await begin('database', { name: database, locationId: plan.region });
    const result = await createOrWait('firestore', 'v1', 'database', `/v1/${project}/databases?databaseId=%28default%29`, {
      locationId: plan.region, type: 'FIRESTORE_NATIVE', databaseEdition: 'STANDARD',
    });
    if (!result?.uid || result.name !== database) stop('GOOGLE_INVALID_RESPONSE', 'Google 未回傳可核對的資料庫建立結果；已保留 operation。');
    await save('intents', 'database', { ...intent('database'), uid: result.uid });
    db = await request('firestore', `/v1/${encodedName(database)}`);
  } else if (!intent('database')?.uid && intent('database')?.operation) {
    const result = await wait('firestore', 'v1', await request('firestore', `/v1/${operationPath('firestore', intent('database').operation)}`), 'database');
    if (result?.uid) await save('intents', 'database', { ...intent('database'), uid: result.uid });
  }
  if (!intent('database')?.uid || db.name !== database || db.uid !== intent('database').uid ||
      db.locationId !== plan.region || db.type !== 'FIRESTORE_NATIVE' || (db.databaseEdition && db.databaseEdition !== 'STANDARD')) conflict();
  await noOtherData();
  const metadata = { name: database, uid: db.uid, locationId: db.locationId };
  await save('resources', 'database', metadata);
  return { database: metadata };
}

// Turn on Email/Password sign-in, changing nothing else in the Auth config.
async function enableEmailSignIn(s) {
  const { configPath, save, intent, begin, request, ownedProject, onlyOwnAuth, getAuthConfig } = s;
  let config = await getAuthConfig();
  await onlyOwnAuth();
  const desired = { enabled: true, passwordRequired: true };
  await begin('auth', { before: { email: config.signIn?.email ?? {} }, desired });
  if (canonical(config.signIn?.email ?? {}) !== canonical(desired)) {
    if (canonical(config.signIn?.email ?? {}) !== canonical(intent('auth').before.email)) conflict();
    await ownedProject();
    const check = await getAuthConfig();
    if (canonical(check.signIn?.email ?? {}) !== canonical(intent('auth').before.email)) conflict();
    await request('identitytoolkit', `${configPath}?updateMask=signIn.email`, { method: 'PATCH', body: { signIn: { email: desired } }, authSetup: true });
    config = await getAuthConfig();
  }
  if (canonical(config.signIn?.email) !== canonical(desired)) conflict();
  await save('resources', 'auth', { emailPassword: true });
  return { auth: { emailPassword: true } };
}

// Register the single Web app and hand its public config to the build.
async function registerWebApp(s) {
  const { context, owned, projectId, project, runLabel, save, resource, intent, begin, request, createOrWait } = s;
  const displayName = `Church install ${runLabel}`;
  let apps = await request('firebase', `/v1beta1/${project}/webApps?pageSize=2&showDeleted=true`);
  if (apps.nextPageToken || (apps.apps ?? []).length > 1) conflict();
  let app = apps.apps?.[0];
  if (!app) {
    if (resource('webApp')) conflict();
    await begin('webApp', { displayName });
    await createOrWait('firebase', 'v1beta1', 'webApp', `/v1beta1/${project}/webApps`, { displayName });
    apps = await request('firebase', `/v1beta1/${project}/webApps?pageSize=2&showDeleted=true`);
    if (apps.nextPageToken || apps.apps?.length !== 1) conflict();
    app = apps.apps[0];
  }
  if (!intent('webApp') || app.displayName !== displayName || app.projectId !== projectId || app.state !== 'ACTIVE' ||
      !/^[a-zA-Z0-9:_-]+$/.test(app.appId ?? '') || app.name !== `${project}/webApps/${app.appId}` ||
      (resource('webApp') && resource('webApp').appId !== app.appId)) conflict();
  const config = await request('firebase', `/v1beta1/${encodedName(app.name)}/config`);
  if (config.projectId !== projectId || config.appId !== app.appId || config.authDomain !== `${projectId}.firebaseapp.com` ||
      typeof config.apiKey !== 'string' || !config.apiKey || String(config.messagingSenderId) !== owned.name.split('/')[1]) conflict('Firebase Web 設定與本次專案不一致；未繼續建置。');
  context.transient.firebaseConfig = Object.fromEntries(['apiKey', 'authDomain', 'projectId', 'storageBucket', 'messagingSenderId', 'appId']
    .filter((key) => config[key] !== undefined).map((key) => [key, config[key]]));
  const metadata = { appId: app.appId, name: app.name };
  await save('resources', 'webApp', metadata);
  return { webApp: metadata };
}

const releaseNameOf = (s) => `${s.project}/releases/cloud.firestore`;

function rulesetPath(s, name) {
  if (!new RegExp(`^projects/${s.projectId}/rulesets/[a-zA-Z0-9_-]+$`).test(name ?? '')) conflict('Firestore ruleset 不屬於本次專案；已停止。');
  return `/v1/${encodedName(name)}`;
}

function ruleSource(source) {
  if (!Array.isArray(source?.files) || source.files.some((file) => typeof file.name !== 'string' || typeof file.content !== 'string')) conflict();
  return { files: source.files.map(({ name, content }) => ({ name, content })) };
}

// The live release and its ruleset, reduced to the fields worth backing up.
async function liveRules(s) {
  const releaseName = releaseNameOf(s);
  const release = await s.request('firebaserules', `/v1/${releaseName}`, { missing: true });
  if (!release) return { release: null, ruleset: null };
  if (release.name !== releaseName) conflict();
  const ruleset = await s.request('firebaserules', rulesetPath(s, release.rulesetName));
  if (ruleset.name !== release.rulesetName) conflict();
  return {
    release: Object.fromEntries(['name', 'rulesetName', 'createTime', 'updateTime']
      .filter((key) => release[key] !== undefined).map((key) => [key, release[key]])),
    ruleset: { name: ruleset.name, source: ruleSource(ruleset.source) },
  };
}

// A brand-new database has no release, or Firebase's single deny-all file.
function isInitialDenyAll(state) {
  if (!state.release) return true;
  if (state.ruleset.source.files.length !== 1) return false;
  const text = state.ruleset.source.files[0].content?.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, '').replace(/\s/g, '');
  return ["rules_version='2';", 'rules_version="2";', ''].some((prefix) =>
    text === `${prefix}servicecloud.firestore{match/databases/{database}/documents{match/{document=**}{allowread,write:iffalse;}}}`);
}

// The rules prepare-deployment staged must equal what this plan generates.
async function generatedRules(s) {
  const { plan, context } = s;
  const source = await readFile(path.join(context.transient.deploymentDir ?? path.join(context.runDir, 'deployment'), 'firestore.rules'), 'utf8');
  const expected = renderRules(await readFile(path.join(ROOT, 'firestore.rules'), 'utf8'), plan.churchConfig);
  if (source !== expected) stop('GOOGLE_RULES_MISMATCH', '待發佈規則與本次教會設定產生的規則不同；已停止，請重新產生部署產物。');
  return [{ name: 'firestore.rules', content: `// church-install: ${s.runLabel}\n${source}` }];
}

// Back up the initial state, create (or reuse) this run's ruleset, then release it.
async function releaseRuleset(s, current, files, desiredFingerprint) {
  const { project, save, intent, begin, request, ownedProject } = s;
  const releaseName = releaseNameOf(s);
  if (!intent('rules')) {
    if (!isInitialDenyAll(current)) conflict('Firestore 已有非初始閉鎖規則；首次安裝不會覆寫既有規則。');
    await begin('rules', { fingerprint: desiredFingerprint, before: current, beforeFingerprint: fingerprint(current) });
  }
  if (intent('rules').fingerprint !== desiredFingerprint || intent('rules').beforeFingerprint !== fingerprint(current)) conflict('Firestore 規則在安裝中被其他操作變更；未覆寫。');
  let name = intent('rules').rulesetName;
  if (name) {
    const known = await request('firebaserules', rulesetPath(s, name));
    if (fingerprint(ruleSource(known.source).files) !== desiredFingerprint) conflict();
  } else {
    const created = await request('firebaserules', `/v1/${project}/rulesets`, { method: 'POST', body: { source: { files } } });
    rulesetPath(s, created.name);
    name = created.name;
    await save('intents', 'rules', { ...intent('rules'), rulesetName: name });
  }
  await ownedProject();
  if (fingerprint(await liveRules(s)) !== intent('rules').beforeFingerprint) conflict('Firestore 規則在發佈前已變更；未覆寫。');
  const release = { name: releaseName, rulesetName: name };
  // Rules releases have no CAS: updateTime is output-only. Only install into
  // the empty/deny-all state backed up above; never use this as an upgrader.
  await request('firebaserules', current.release ? `/v1/${releaseName}` : `/v1/${project}/releases`, {
    method: current.release ? 'PATCH' : 'POST', body: current.release ? { release } : release,
  });
}

// Publish the generated rules over the empty/deny-all initial state only.
async function publishRules(s) {
  const { context, save, resource, intent, noOtherData } = s;
  await noOtherData();
  const files = await generatedRules(s);
  const desiredFingerprint = fingerprint(files);
  const current = await liveRules(s);
  if (fingerprint(current.ruleset?.source?.files) === desiredFingerprint) {
    // Already live: only accept it as ours if this run recorded that ruleset.
    if (!intent('rules') || intent('rules').fingerprint !== desiredFingerprint ||
        intent('rules').rulesetName !== current.release.rulesetName ||
        (resource('rules') && resource('rules').releaseFingerprint !== fingerprint(current.release))) conflict();
  } else {
    await releaseRuleset(s, current, files, desiredFingerprint);
  }
  const after = await liveRules(s);
  if (fingerprint(after.ruleset?.source?.files) !== desiredFingerprint) conflict('規則發佈後的核對結果不同；請檢查 Firebase Console，勿繼續部署網站。');
  const metadata = { rulesetName: after.release.rulesetName, fingerprint: desiredFingerprint, releaseFingerprint: fingerprint(after.release) };
  await save('resources', 'rules', metadata);
  context.emit?.({ message: '已核對規則發佈；Firebase 規則仍可能需要數分鐘傳播，尚未代表登入權限驗收成功。' });
  return { rules: metadata };
}

// Create the Auth user for the confirmed email under this run's fixed uid,
// unless this run already did. No password is set here.
async function ensureAdminAuthUser(s) {
  const { plan, authPath, adminUid, resource, begin, request, ownedProject, checkAuthUser, onlyOwnAuth } = s;
  let user = await onlyOwnAuth();
  if (!user) {
    if (resource('admin')) conflict();
    await begin('adminAuth', { uid: adminUid, email: plan.admin.email });
    await ownedProject();
    const result = await request('identitytoolkit', authPath, { method: 'POST', body: {
      localId: adminUid, email: plan.admin.email, displayName: plan.admin.name, emailVerified: false, disabled: false,
    }, authSetup: true });
    if (result.localId !== adminUid) conflict();
    user = await onlyOwnAuth();
  }
  return checkAuthUser(user);
}

// Hand the create-only profile write to bootstrap-admin, routed through this
// session's request() so it can only reach the three expected endpoints.
async function writeAdminProfileOnce(s, options) {
  const { plan, signal, documents, authPath, adminUid, request } = s;
  const allowed = new Map([
    [`https://identitytoolkit.googleapis.com${authPath}:lookup`, ['identitytoolkit', `${authPath}:lookup`]],
    [`https://firestore.googleapis.com/v1/${documents}/users/${adminUid}`, ['firestore', `/v1/${encodedName(documents)}/users/${adminUid}`]],
    [`https://firestore.googleapis.com/v1/${documents}:commit`, ['firestore', `/v1/${encodedName(documents)}:commit`]],
  ]);
  try {
    await bootstrap(options, {
      getAccessToken: () => s.token(), readConfig: () => plan.churchConfig, log: () => {},
      fetchImpl: async (url, init) => {
        const target = allowed.get(url);
        if (!target) stop('GOOGLE_INVALID_TARGET', '管理員建立要求非預期的 API 目標；已停止。');
        const data = await request(...target, { method: init.method ?? 'GET', body: init.body ? JSON.parse(init.body) : undefined, missing: !init.method });
        return new Response(data === null ? null : JSON.stringify(data), { status: data === null ? 404 : 200 });
      },
    });
  } catch (error) {
    if (error instanceof ActionRequired) throw error;
    signal?.throwIfAborted();
    stop('GOOGLE_ADMIN_CREATE_FAILED', '管理員 create-only 建立未完成；既有 profile 不會覆寫。請續跑核對 Auth 身分與資料。');
  }
}

// Create the confirmed admin Auth user and its create-only profile.
async function createAdmin(s) {
  const { plan, now, serviceIds, projectId, documents, adminUid, save, resource, intent, begin, request, ownedProject, noOtherData, getAuthConfig } = s;
  const config = await getAuthConfig();
  if (!config.signIn?.email?.enabled || !config.signIn.email.passwordRequired) stop('AUTH_SETUP_REQUIRED', '請先完成 Email/Password 登入設定，再建立管理員。');
  await noOtherData();
  const user = await ensureAdminAuthUser(s);
  const options = { project: projectId, uid: adminUid, email: plan.admin.email, name: plan.admin.name, username: plan.admin.username,
    config: 'installer-config', apply: true, 'confirm-project': projectId, 'confirm-uid': adminUid };
  const profile = buildAdminProfile(options, user, serviceIds);
  const fields = Object.fromEntries(Object.entries(profile).map(([key, value]) => [key, firestoreValue(value)]));
  const fieldsFingerprint = documentFingerprint(fields);
  const existing = await request('firestore', `/v1/${encodedName(documents)}/users/${adminUid}`, { missing: true });
  if (existing) {
    // Resume: accept only the exact profile this run recorded before writing.
    if (!intent('adminProfile') || intent('adminProfile').fieldsFingerprint !== fieldsFingerprint ||
        existing.name !== `${documents}/users/${adminUid}` || documentFingerprint(existing.fields) !== fieldsFingerprint) {
      conflict('管理員 profile 已存在或不符合本次安裝；不覆寫、不升權。');
    }
  } else {
    if (resource('admin')) conflict('本次管理員 profile 已被移除；不會自動重新升權。');
    await begin('adminProfile', { uid: adminUid, fieldsFingerprint, before: { exists: false, checkedAt: new Date(now()).toISOString() } });
    if (intent('adminProfile').fieldsFingerprint !== fieldsFingerprint) conflict();
    await ownedProject();
    await writeAdminProfileOnce(s, options);
  }
  await noOtherData(true);
  const metadata = { uid: adminUid, profileFingerprint: fieldsFingerprint };
  await save('resources', 'admin', metadata);
  return { admin: metadata };
}

// Add this run's verified Pages domain to the Auth authorized domains.
async function authorizeDomain(s) {
  const { configPath, pagesDomain, save, intent, begin, request, ownedProject, getAuthConfig } = s;
  const domain = pagesDomain();
  let config = await getAuthConfig();
  const before = config.authorizedDomains ?? [];
  if (!Array.isArray(before) || before.some((value) => typeof value !== 'string')) conflict();
  if (!intent('authDomains')) {
    if (before.includes(domain)) conflict('本次 Pages 登入網域已由其他操作加入；請核對後再繼續，不會接管設定。');
    await begin('authDomains', { before: { authorizedDomains: before }, desired: [...before, domain] });
  }
  const desired = intent('authDomains').desired;
  if (canonical(before) !== canonical(desired)) {
    if (canonical(before) !== canonical(intent('authDomains').before.authorizedDomains)) conflict('Auth 登入網域在安裝中被其他操作變更；未覆寫。');
    await ownedProject();
    const current = await getAuthConfig();
    if (canonical(current.authorizedDomains ?? []) !== canonical(before)) conflict();
    await request('identitytoolkit', `${configPath}?updateMask=authorizedDomains`, { method: 'PATCH', body: { authorizedDomains: desired }, authSetup: true });
    config = await getAuthConfig();
  }
  if (canonical(config.authorizedDomains) !== canonical(desired)) conflict();
  await save('resources', 'authDomains', { domain });
  return { authDomains: { domain } };
}

// Ask Firebase to send the admin a password-setup email, at most once.
async function sendActivation(s) {
  const { plan, authPath, adminUid, pagesDomain, save, resource, intent, begin, request, noOtherData, onlyOwnAuth, getAuthConfig } = s;
  if (plan.activationEmailConfirmed !== true) stop('ACTIVATION_CONFIRMATION_REQUIRED', '寄送 Firebase 設定密碼信前，需要本人確認管理員 email 並同意寄信。');
  const domain = pagesDomain();
  const user = await onlyOwnAuth();
  if (!user || resource('admin')?.uid !== user.localId) conflict();
  await noOtherData();
  if (!(await getAuthConfig()).authorizedDomains?.includes(domain)) conflict();
  if (!resource('activation')?.sent) {
    if (intent('activation')) stop('ACTIVATION_DELIVERY_UNKNOWN', '上次寄信是否被接受無法確定，為避免重複寄信已停止。請先檢查信箱／垃圾信；若仍未收到，請到本次 Firebase Console 的 Authentication → Users，核對指定管理員 email 後選擇寄送密碼重設信。不要另建管理員。');
    await begin('activation', { uid: adminUid, state: 'sending' });
    // Firebase sends its own message. Never request/retain an OOB link/code.
    await request('identitytoolkit', `${authPath}:sendOobCode`, { method: 'POST', body: {
      requestType: 'PASSWORD_RESET', email: user.email, returnOobLink: false, continueUrl: `https://${domain}/`,
    } });
    await save('resources', 'activation', { sent: true });
  }
  return { activation: { sent: true } };
}

const STEP_HANDLERS = {
  'google-project': createProject,
  'firebase': enableFirebase,
  'database': createDatabase,
  'auth': enableEmailSignIn,
  'web-app': registerWebApp,
  'rules': publishRules,
  'admin': createAdmin,
  'auth-domains': authorizeDomain,
  'activation': sendActivation,
};

export function createGoogleInstaller({
  fetchImpl = globalThis.fetch,
  command = (file, args, options = {}) => runCommand(file, args, { timeoutMs: 30_000, maxOutputBytes: 1024 * 1024, ...options }),
  delay = (ms, signal) => sleep(ms, undefined, { signal }),
  now = Date.now,
} = {}) {
  async function inspectIdentity({ signal } = {}) {
    signal?.throwIfAborted();
    if (['CLOUDSDK_AUTH_ACCESS_TOKEN', 'CLOUDSDK_AUTH_ACCESS_TOKEN_FILE', 'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE',
      'CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT'].some((key) => process.env[key])) {
      stop('GOOGLE_AUTH_REQUIRED', '請使用 Cloud Shell 本人的官方登入，不支援環境變數覆寫憑證或服務帳號模擬。');
    }
    let accounts;
    let config;
    try {
      accounts = JSON.parse((await command('gcloud', ['auth', 'list', '--filter=status:ACTIVE', '--format=json', '--quiet'], { signal })).stdout);
      config = JSON.parse((await command('gcloud', ['config', 'list', '--format=json', '--quiet'], { signal })).stdout);
    } catch {
      signal?.throwIfAborted();
      stop('GOOGLE_AUTH_REQUIRED', '無法讀取 Google 登入身分；請先完成 Cloud Shell 官方授權。');
    }
    const overrides = config.auth ?? {};
    if (['impersonate_service_account', 'credential_file_override', 'access_token_file'].some((key) => overrides[key])) {
      stop('GOOGLE_AUTH_REQUIRED', '目前 gcloud 使用覆寫憑證或服務帳號模擬；請改用 Cloud Shell 本人的官方登入。');
    }
    if (!Array.isArray(accounts) || accounts.length !== 1 || accounts[0].status !== 'ACTIVE' ||
        !emailPattern.test(accounts[0].account ?? '') || accounts[0].account.endsWith('.gserviceaccount.com')) {
      stop('GOOGLE_AUTH_REQUIRED', '找不到唯一有效的 Google 個人登入；請先完成 Cloud Shell 官方授權。');
    }
    return { email: accounts[0].account.toLowerCase() };
  }

  async function executeStep(step, context) {
    if (!steps.has(step)) stop('GOOGLE_INVALID_STEP', '不支援的 Google 安裝步驟。');
    const s = openStepSession(context, { fetchImpl, command, delay, now, inspectIdentity });
    await s.credentials();
    if (step === 'google-project') return createProject(s);
    // Every later step first proves the project is still the one this run created.
    s.owned = await s.ownedProject();
    return STEP_HANDLERS[step](s);
  }
  async function execute(step, context) {
    try { return await executeStep(step, context); }
    catch (error) {
      if (error instanceof ActionRequired && projectPattern.test(context?.plan?.projectId ?? '')) {
        const id = encodeURIComponent(context.plan.projectId);
        const links = {
          AUTH_SETUP_REQUIRED: `https://console.firebase.google.com/project/${id}/authentication`,
          ACTIVATION_DELIVERY_UNKNOWN: `https://console.firebase.google.com/project/${id}/authentication/users`,
          GOOGLE_FREE_TIER_REQUIRED: `https://console.firebase.google.com/project/${id}/overview`,
          GOOGLE_PERMISSION_REQUIRED: `https://console.cloud.google.com/iam-admin/iam?project=${id}`,
          GOOGLE_QUOTA_REQUIRED: `https://console.cloud.google.com/iam-admin/quotas?project=${id}`,
          GOOGLE_TERMS_REQUIRED: 'https://console.firebase.google.com/',
        };
        if (links[error.code]) error.helpUrl = links[error.code];
      }
      throw error;
    }
  }
  return { inspectIdentity, execute };
}
