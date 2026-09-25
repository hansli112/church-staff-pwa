import { randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, mkdir, open, readdir, realpath, rename, unlink } from 'node:fs/promises';
import path from 'node:path';
import { validateChurchConfig } from '../../worker/church_config.js';
import { CORE_ICONS, fingerprint, installationError, isPrivateDirectory, projectIdFor, STEPS } from './shared.mjs';

export { installationError, STEPS };

export const REGIONS = [
  ['asia-east1', '台灣'], ['asia-east2', '香港'],
  ['asia-northeast1', '東京'], ['asia-southeast1', '新加坡'],
  ['australia-southeast1', '雪梨'], ['europe-west1', '比利時'],
  ['us-central1', '美國中部'], ['us-east1', '美國東部'],
];
const RUN_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const PRIVATE_KEY = /^(?:access_?token|refresh_?token|token|secret|client_?secret|password|passwordHash|salt|api_?key|authorization|oobCode|oobLink|firebaseConfig)$/i;
const clone = (value) => JSON.parse(JSON.stringify(value));

// Validate a required single-line field and return it trimmed.
function requireText(value, label, max = 100) {
  if (typeof value !== 'string' || !value.trim() || value.length > max || /[\x00-\x1f]/.test(value)) {
    throw installationError(`${label}未填寫或格式不正確`, 'INVALID_INPUT');
  }
  return value.trim();
}

function requireEmail(value, label) {
  const result = requireText(value, label, 254);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result)) throw installationError(`${label}格式不正確`, 'INVALID_INPUT');
  return result;
}

export function createInstallationPlan(input, identity, {
  runId = randomUUID(), sourceRevision = 'development', mode = 'cloud',
} = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw installationError('請填寫教會設定', 'INVALID_INPUT');
  const allowed = new Set(['appName', 'shortName', 'timeZone', 'region', 'services', 'adminName', 'adminEmail', 'cloudflareAccountId']);
  if (Object.keys(input).some((key) => !allowed.has(key))) throw installationError('設定包含不支援的欄位', 'INVALID_INPUT');
  if (!RUN_ID.test(runId)) throw installationError('安裝識別碼不正確', 'INVALID_INPUT');
  const googleEmail = requireEmail(identity?.googleEmail, 'Google 帳號');
  if (!/^[0-9a-f]{32}$/i.test(input.cloudflareAccountId ?? '') ||
      !identity?.accounts?.some((account) => account.id === input.cloudflareAccountId)) {
    throw installationError('請選擇已授權的 Cloudflare 帳號', 'INVALID_INPUT');
  }
  if (!REGIONS.some(([id]) => id === input.region)) throw installationError('請選擇資料庫地區', 'INVALID_INPUT');
  if (!Array.isArray(input.services) || input.services.length < 1 || input.services.length > 20) {
    throw installationError('請設定 1 至 20 種聚會', 'INVALID_INPUT');
  }
  let churchConfig;
  try {
    churchConfig = validateChurchConfig({
      schemaVersion: 1,
      appName: requireText(input.appName, '教會名稱'),
      shortName: requireText(input.shortName, '顯示簡稱', 20),
      timeZone: requireText(input.timeZone, '時區'),
      services: input.services.map((service, index) => ({
        id: `service${index + 1}`,
        label: requireText(service?.label, '聚會簡稱', 20),
        name: requireText(service?.name, '聚會名稱'),
        weekday: service?.weekday,
        enabled: true,
      })),
      features: { calendar: false, photoImport: false, pushNotifications: false, lineNotifications: false },
      devotional: { enabled: false, dataUrl: '', linkUrl: '', sourceName: '每日靈糧', fetchUrl: '', fetchFormat: 'json' },
      icons: { ...CORE_ICONS },
    });
  } catch (error) {
    if (error.safeToDisplay) throw error;
    throw installationError(`教會設定不正確：${error.message}`, 'INVALID_INPUT');
  }
  const projectId = projectIdFor(runId);
  const adminName = requireText(input.adminName, '管理員姓名');
  const plan = {
    schemaVersion: 1, runId, sourceRevision, mode,
    projectId, pagesProject: projectId,
    cloudflareAccountId: input.cloudflareAccountId,
    googleEmail, region: input.region, churchConfig,
    // Sign-in uses the email; like bootstrap-admin, the username defaults to the name.
    admin: { name: adminName, email: requireEmail(input.adminEmail, '管理員 email'), username: adminName },
  };
  return { ...plan, digest: fingerprint(plan) };
}

function validateStoredPlan(plan, sourceRevision, mode) {
  if (!plan || plan.schemaVersion !== 1 || !RUN_ID.test(plan.runId ?? '')) throw installationError('安裝紀錄格式不正確');
  const { digest, ...fields } = plan;
  if (fingerprint(fields) !== digest) throw installationError('安裝設定已被更改，拒絕接續');
  const config = validateChurchConfig(plan.churchConfig);
  if (Object.values(config.features).some(Boolean) || config.devotional.enabled ||
      plan.projectId !== projectIdFor(plan.runId) || plan.pagesProject !== plan.projectId ||
      !REGIONS.some(([id]) => id === plan.region)) throw installationError('紀錄不是核心首次安裝設定');
  if (plan.sourceRevision !== sourceRevision) throw installationError('程式版本與這次安裝不同；請使用原版本接續，不要重新建立專案');
  if (plan.mode !== mode) throw installationError('示範安裝與真實安裝不可互相接續');
  requireEmail(plan.googleEmail, 'Google 帳號');
  requireEmail(plan.admin?.email, '管理員 email');
}

function assertCheckpointSafe(value, depth = 0) {
  if (depth > 30) throw new Error('Checkpoint nesting exceeds limit');
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    if (['__proto__', 'prototype', 'constructor'].includes(key) || PRIVATE_KEY.test(key)) {
      throw new Error('Credentials or unsafe keys must not be persisted');
    }
    assertCheckpointSafe(child, depth + 1);
  }
}

async function privateDirectory(directory) {
  await mkdir(directory, { mode: 0o700 }).catch((error) => { if (error.code !== 'EEXIST') throw error; });
  const stat = await lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Installer directory must not be a link');
  if ((stat.mode & 0o077) !== 0) throw installationError('安裝紀錄目錄權限過寬，請先限制為只有本人可存取');
}

async function assertRegular(file) {
  const stat = await lstat(file).catch((error) => { if (error.code !== 'ENOENT') throw error; });
  if (stat && (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || (stat.mode & 0o077) !== 0)) {
    throw new Error('Installer state must be a private regular file');
  }
  return stat;
}

async function openStore(rootDir, runId) {
  if (!RUN_ID.test(runId)) throw installationError('安裝識別碼不正確', 'INVALID_INPUT');
  const root = await realpath(rootDir);
  const local = path.join(root, '.local');
  // Existing .local may contain unrelated operator files. Never change its permissions.
  const localStat = await lstat(local).catch((error) => { if (error.code !== 'ENOENT') throw error; });
  if (localStat && (!localStat.isDirectory() || localStat.isSymbolicLink())) throw new Error('.local must be a real directory');
  if (!localStat) await mkdir(local, { mode: 0o700 });
  const base = path.join(local, 'install');
  await privateDirectory(base);
  const runDir = path.join(base, runId);
  await privateDirectory(runDir);
  const file = path.join(runDir, 'state.json');
  return {
    runDir,
    async read() {
      const stat = await assertRegular(file);
      if (!stat || stat.size > 2 * 1024 * 1024) throw installationError('找不到有效的安裝紀錄');
      const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
      try { return JSON.parse(await handle.readFile('utf8')); } finally { await handle.close(); }
    },
    async write(value, initial = false) {
      assertCheckpointSafe(value);
      const body = JSON.stringify(value, null, 2) + '\n';
      if (Buffer.byteLength(body) > 2 * 1024 * 1024) throw new Error('Installer state exceeds size limit');
      if (initial) {
        const handle = await open(file, 'wx', 0o600);
        try { await handle.writeFile(body); await handle.sync(); } finally { await handle.close(); }
        return;
      }
      await assertRegular(file);
      const temporary = path.join(runDir, `.state-${randomUUID()}.tmp`);
      const handle = await open(temporary, 'wx', 0o600);
      try {
        await handle.writeFile(body);
        await handle.sync();
        await handle.close();
        await rename(temporary, file);
      } catch (error) {
        await handle.close().catch(() => {});
        await unlink(temporary).catch(() => {});
        throw error;
      }
    },
  };
}

function verifiedWebsite(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname.endsWith('.pages.dev') && url.pathname === '/' && !url.search ? url.href : undefined;
  } catch { return undefined; }
}

export function publicError(error) {
  const result = {
    code: typeof error?.code === 'string' && /^[A-Z_]{2,80}$/.test(error.code) ? error.code : 'INSTALLATION_ERROR',
    message: error?.safeToDisplay === true ? String(error.message).slice(0, 1_000) : '操作未完成。請確認授權與工具狀態後重試；原始輸出不會公開，以免洩漏憑證。',
  };
  const action = error?.action ?? (error?.helpUrl ? { title: '開啟官方設定頁', url: error.helpUrl } : undefined);
  if (action?.url) {
    try {
      const url = new URL(action.url);
      if (url.protocol === 'https:' && !url.username && !url.password &&
          ['console.firebase.google.com', 'console.cloud.google.com', 'dash.cloudflare.com'].includes(url.hostname)) {
        result.action = { title: String(action.title ?? '開啟官方設定頁').slice(0, 100), url: url.href };
      }
    } catch { /* Never echo an untrusted diagnostic URL. */ }
  }
  return result;
}

export function createInstallationManager({ rootDir, google, cloudflare, build, sourceRevision = 'development', demo = false }) {
  const mode = demo ? 'demo' : 'cloud';
  let state;
  let store;
  let busy = false;
  let controller;
  let lastError;
  let message = '';
  let device;
  let googleIdentity;
  let cloudflareIdentity;
  let transient = {};
  let writeQueue = Promise.resolve();

  const emit = (event) => {
    if (typeof event?.message === 'string') message = event.message.slice(0, 1_000);
    const candidate = event?.verificationUrl ?? event?.verificationUri ?? event?.url;
    if (candidate) {
      try {
        const url = new URL(candidate);
        if (url.protocol === 'https:' && url.hostname === 'dash.cloudflare.com' && !url.username && !url.password) {
          device = { url: url.href, code: String(event.userCode ?? event.code ?? '').slice(0, 50) };
        }
      } catch { /* Auth providers may only link to their official host. */ }
    }
  };
  const save = (patch) => {
    writeQueue = writeQueue.then(async () => {
      const next = clone(state);
      for (const key of ['resources', 'intents', 'backups']) {
        if (patch[key]) next[key] = { ...next[key], ...clone(patch[key]) };
      }
      await store.write(next);
      Object.assign(state, next);
    });
    return writeQueue;
  };
  const exclusive = async (operation) => {
    if (busy) throw installationError('另一個步驟仍在執行，請等待或停止', 'BUSY');
    busy = true;
    lastError = undefined;
    controller = new AbortController();
    try { return await operation(controller.signal); }
    catch (error) { lastError = publicError(error); throw error; }
    finally { busy = false; controller = undefined; }
  };
  const verifyIdentity = async (plan, signal) => {
    googleIdentity = await google.inspectIdentity({ signal });
    cloudflareIdentity = await cloudflare.inspectIdentity({ signal });
    if (googleIdentity.email !== plan.googleEmail ||
        !cloudflareIdentity.accounts?.some((account) => account.id === plan.cloudflareAccountId)) {
      throw installationError('目前授權帳號與安裝紀錄不符，已停止，沒有切換到其他專案', 'IDENTITY_MISMATCH');
    }
  };

  return {
    async listRuns() {
      const root = await realpath(rootDir);
      const local = path.join(root, '.local');
      const base = path.join(local, 'install');
      for (const directory of [local, base]) {
        const stat = await lstat(directory).catch((error) => { if (error.code !== 'ENOENT') throw error; });
        if (!stat) return [];
        if (!stat.isDirectory() || stat.isSymbolicLink()) throw installationError('安裝紀錄目錄不正確');
      }
      const candidates = (await readdir(base)).filter((name) => RUN_ID.test(name)).slice(0, 100);
      const results = [];
      for (const runId of candidates) {
        try {
          const candidate = await openStore(rootDir, runId);
          const record = await candidate.read();
          validateStoredPlan(record.plan, sourceRevision, mode);
          results.push({ runId, appName: record.plan.churchConfig.appName, projectId: record.plan.projectId, status: record.status });
        } catch { /* Invalid or different-version records cannot become resume targets. */ }
      }
      return results;
    },
    snapshot() {
      return {
        demo, busy, message, error: lastError, device,
        identity: {
          googleEmail: googleIdentity?.email,
          cloudflareEmail: cloudflareIdentity?.email,
          accounts: (cloudflareIdentity?.accounts ?? []).map(({ id, name }) => ({ id, name })),
        },
        plan: state?.plan,
        status: state?.status ?? 'setup',
        steps: STEPS.map(({ id, label }) => ({ id, label, status: state?.steps?.[id] ?? 'pending' })),
        website: state?.status === 'complete' ? verifiedWebsite(state.resources?.website) : undefined,
        regions: REGIONS,
      };
    },
    connectGoogle() {
      return exclusive(async (signal) => {
        message = '請完成 Google 官方 Cloud Shell 授權';
        googleIdentity = await google.inspectIdentity({ signal });
        message = 'Google 帳號已連接';
      });
    },
    connectCloudflare() {
      return exclusive(async (signal) => {
        device = undefined;
        message = '正在開啟 Cloudflare 官方授權';
        await cloudflare.startLogin({ emit, signal });
        cloudflareIdentity = await cloudflare.inspectIdentity({ signal });
        device = undefined;
        message = 'Cloudflare 帳號已連接';
      });
    },
    plan(input) {
      return exclusive(async (signal) => {
        if (state?.approved) throw installationError('這次安裝已開始，不能更改設定或另建專案；請接續原安裝');
        const plan = createInstallationPlan(input, {
          googleEmail: googleIdentity?.email, accounts: cloudflareIdentity?.accounts,
        }, { sourceRevision, mode });
        // Read-only checks before anything is recorded or confirmed. Google
        // offers no read-only quota/terms check; those surface at the first
        // step, before any other resource exists.
        message = '正在檢查帳號與網站名稱…';
        await verifyIdentity(plan, signal);
        await cloudflare.preflight?.(plan, { signal });
        const nextStore = await openStore(rootDir, plan.runId);
        const next = { schemaVersion: 1, plan, approved: false, status: 'ready', steps: {}, resources: {}, intents: {}, backups: {} };
        await nextStore.write(next, true);
        state = next;
        store = nextStore;
        transient = {};
        message = '請核對新專案、資料地區與管理員，再確認安裝';
        return plan;
      });
    },
    load(runId) {
      return exclusive(async () => {
        if (state?.approved && state.plan.runId !== runId) throw installationError('請先完成或停止目前的安裝，不可在執行期間切換目標');
        const nextStore = await openStore(rootDir, runId);
        const next = await nextStore.read();
        validateStoredPlan(next.plan, sourceRevision, mode);
        if (next.schemaVersion !== 1 || typeof next.approved !== 'boolean') throw installationError('安裝紀錄格式不正確');
        assertCheckpointSafe(next);
        state = next;
        state.status = state.status === 'complete' ? 'complete' : 'paused';
        store = nextStore;
        transient = {};
        writeQueue = Promise.resolve();
        message = '已載入紀錄；請重新連接相同帳號，再確認接續';
      });
    },
    apply({ digest, confirmProject, confirmAdmin, acknowledgeRegion, acknowledgeEmail } = {}) {
      return exclusive(async (signal) => {
        if (!state || digest !== state.plan.digest || confirmProject !== state.plan.projectId ||
            confirmAdmin !== state.plan.admin.email || acknowledgeRegion !== true || acknowledgeEmail !== true) {
          throw installationError('請明確核對新專案、管理員、資料地區與寄信，再確認安裝', 'CONFIRMATION_REQUIRED');
        }
        validateStoredPlan(state.plan, sourceRevision, mode);
        await verifyIdentity(state.plan, signal);
        state.approved = true;
        state.status = 'running';
        await store.write(state);
        const context = {
          plan: { ...clone(state.plan), activationEmailConfirmed: true },
          runDir: store.runDir, checkpoint: state, save, emit, signal, transient,
        };
        try {
          for (const step of STEPS) {
            signal.throwIfAborted();
            // Providers re-inspect previously completed steps; checkpoints are not authority.
            state.steps[step.id] = 'running';
            message = step.label;
            await store.write(state);
            if (step.provider === 'build') await build(context);
            else await (step.provider === 'google' ? google : cloudflare).execute(step.id, context);
            await writeQueue;
            state.steps[step.id] = 'complete';
            await store.write(state);
          }
          state.status = 'complete';
          message = '部署步驟已完成。請查看管理員信箱並實際登入驗收；規則可能需要幾分鐘生效。';
        } catch (error) {
          const current = STEPS.find((step) => state.steps[step.id] === 'running');
          if (current) state.steps[current.id] = signal.aborted ? 'paused' : error.actionRequired ? 'waiting' : 'failed';
          state.status = 'paused';
          await store.write(state);
          throw error;
        } finally {
          await store.write(state);
        }
      });
    },
    cancel() {
      controller?.abort();
      message = '正在停止；已建立的雲端資源不會刪除，之後可核對狀態再接續';
    },
    async dispose() {
      controller?.abort();
      await cloudflare.dispose?.();
      transient = {};
      googleIdentity = undefined;
      cloudflareIdentity = undefined;
      device = undefined;
    },
  };
}
