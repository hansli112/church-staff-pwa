import { chmod, lstat, mkdir, mkdtemp, readdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { privateEnvironment, runIsolatedCommand } from './process.mjs';
import { fingerprint, installationError, isPrivateDirectory, stepIdsFor, verifyBuildArtifacts, WRANGLER_VERSION } from './shared.mjs';

export const CLOUDFLARE_SCOPES = ['account:read', 'user:read', 'pages:write'];
const API = 'https://api.cloudflare.com/client/v4';
const ACCOUNT_ID = /^[a-f0-9]{32}$/;
const STEP_IDS = stepIdsFor('cloudflare');
const cloudflareError = (message) => installationError(message, 'CLOUDFLARE_INSTALL_FAILED');

export function parseDevicePrompt(output) {
  const clean = output.replace(/\x1b\[[0-9;]*m/g, '');
  const match = clean.match(/To authorize [^\n]+, please visit:\s+(https:\/\/[^\s]+)\s+and enter the code:\s+([A-Z0-9]{4}-[A-Z0-9]{4})\b/);
  if (!match) return null;
  const url = new URL(match[1]);
  // The CLI prints the bare URI. Do not forward arbitrary query strings,
  // fragments or URLs from diagnostic output (which can contain tokens).
  if (url.origin !== 'https://dash.cloudflare.com' || url.username || url.password || url.search || url.hash || !/^\/oauth2\/[a-z/-]+$/.test(url.pathname)) return null;
  return { verificationUrl: url.href, userCode: match[2] };
}

function safeJson(stdout) {
  try { return JSON.parse(stdout); } catch { throw cloudflareError('Cloudflare 工具回應格式不符，請重新授權。'); }
}

const configurationFingerprint = (project) => fingerprint(project.deployment_configs);

async function verifyUpload(directory) {
  if (!path.isAbsolute(directory) || !(await lstat(directory)).isDirectory()) throw cloudflareError('Pages 建置目錄格式不符。');
  async function visit(dir) {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const file = path.join(dir, entry.name);
      if (entry.name.startsWith('.env') || ['firebase-config.json', 'firestore.rules', 'dart-defines.json'].includes(entry.name)) throw cloudflareError('Pages 產物含私人設定檔，禁止發佈。');
      if (entry.isDirectory()) await visit(file);
      else if (!entry.isFile() || (await lstat(file)).nlink !== 1) throw cloudflareError('Pages 產物不可包含符號連結、硬連結或特殊檔案。');
    }
  }
  await visit(directory);
  await verifyBuildArtifacts(directory, (message) => cloudflareError(`Pages ${message}`));
}

export function createCloudflareInstaller({ command = runIsolatedCommand, fetchImpl = fetch, sessionDir, wrangler = process.env.INSTALLER_WRANGLER || 'wrangler', environment = process.env, loginTimeoutMs = 310_000, requestTimeoutMs = 30_000, wait = delay } = {}) {
  if (!sessionDir || !path.isAbsolute(sessionDir)) throw cloudflareError('Cloudflare 需要獨立的絕對路徑暫存目錄。');
  let home;
  let initializing;
  let disposed = false;
  let loginActive = false;
  const activeCommands = new Set();
  const lifetime = new AbortController();
  async function init() {
    if (disposed) throw cloudflareError('Cloudflare 授權已結束，請重新開啟安裝精靈。');
    if (!initializing) initializing = (async () => {
      const stat = await lstat(sessionDir);
      if (!isPrivateDirectory(stat)) throw cloudflareError('Cloudflare 暫存目錄必須是私人目錄（0700）。');
      home = await mkdtemp(path.join(sessionDir, 'cloudflare-'));
      await chmod(home, 0o700);
      await mkdir(path.join(home, 'tmp'), { mode: 0o700 });
    })();
    await initializing;
  }
  async function cli(args, { signal, onStdout, timeoutMs, accountId } = {}) {
    await init();
    const pending = Promise.resolve().then(() => command(wrangler, args, {
      cwd: home, env: { ...privateEnvironment(home, environment), ...(accountId ? { CLOUDFLARE_ACCOUNT_ID: accountId } : {}) },
      signal: AbortSignal.any([lifetime.signal, ...(signal ? [signal] : [])]), onStdout, timeoutMs,
    }));
    activeCommands.add(pending);
    try { return await pending; }
    catch { throw cloudflareError('Cloudflare 工具無法完成，請重新授權或重試。'); }
    finally { activeCommands.delete(pending); }
  }
  async function inspectIdentity({ signal } = {}) {
    const result = await cli(['whoami', '--json'], { signal });
    const data = safeJson(result.stdout);
    if (!data.loggedIn) return { loggedIn: false, accounts: [] };
    if (result.exitCode !== 0 || data.authType !== 'OAuth Token' || !Array.isArray(data.accounts)) throw cloudflareError('請使用本次安裝的 Cloudflare 官方授權，不支援 API Key。');
    if (!CLOUDFLARE_SCOPES.every((scope) => data.tokenPermissions?.includes(scope))) throw cloudflareError('Cloudflare 授權缺少必要的 Pages 或帳號讀取權限，請重新授權。');
    const accounts = data.accounts.filter((account) => ACCOUNT_ID.test(account.id) && typeof account.name === 'string').map(({ id, name }) => ({ id, name: name.slice(0, 200) }));
    return { loggedIn: true, email: typeof data.email === 'string' ? data.email.slice(0, 254) : '', accounts };
  }
  async function startLogin({ emit = () => {}, signal } = {}) {
    if (loginActive) throw cloudflareError('Cloudflare 授權正在進行，請完成或取消後再試。');
    loginActive = true;
    let buffer = '';
    let shown = false;
    const onStdout = (chunk) => {
      buffer = (buffer + chunk).slice(-16_384);
      const prompt = parseDevicePrompt(buffer);
      if (prompt && !shown) { shown = true; emit({ type: 'authorization', provider: 'cloudflare', ...prompt, message: '請前往 Cloudflare 官方頁面，確認下列裝置碼並授權。' }); }
    };
    try {
      const version = await cli(['--version'], { signal });
      if (version.exitCode !== 0 || version.stdout.trim() !== WRANGLER_VERSION) throw cloudflareError(`需要 Wrangler ${WRANGLER_VERSION}，請由 Cloud Shell 安裝入口重開。`);
      const result = await cli(['login', '--device', '--browser=false', '--scopes', ...CLOUDFLARE_SCOPES], { signal, onStdout, timeoutMs: loginTimeoutMs });
      onStdout(result.stdout);
      if (result.exitCode !== 0 || !shown) throw cloudflareError('Cloudflare 授權未完成或已過期；請確認未拒絕授權，再重新連接。');
      const identity = await inspectIdentity({ signal });
      if (!identity.loggedIn || !identity.accounts.length) throw cloudflareError('Cloudflare 尚無可用帳號，請在官方網站建立帳號後重試。');
      return identity;
    } catch (error) {
      // Even CLI failures can contain token text. Only our own fixed messages
      // are exposed; partial credentials are discarded before another attempt.
      if (home) { await rm(home, { recursive: true, force: true }); home = undefined; initializing = undefined; }
      if (signal?.aborted || lifetime.signal.aborted) throw cloudflareError('Cloudflare 授權已取消。');
      throw cloudflareError('Cloudflare 授權未完成、遭拒絕或已逾時，請重新連接；請確認使用指定版本 Wrangler。');
    } finally { loginActive = false; }
  }
  async function token(signal) {
    const result = await cli(['auth', 'token', '--json'], { signal });
    const data = safeJson(result.stdout);
    if (result.exitCode !== 0 || data.type !== 'oauth' || typeof data.token !== 'string' || !data.token) throw cloudflareError('Cloudflare 授權已失效，請重新連接。');
    return data.token;
  }
  async function api(route, { method = 'GET', body, signal, missing = false } = {}) {
    const accessToken = await token(signal);
    for (let attempt = 0; attempt < 4; attempt += 1) {
      let response;
      try {
        response = await fetchImpl(`${API}${route}`, {
          method, headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
          ...(body ? { body: JSON.stringify(body) } : {}),
          signal: AbortSignal.any([lifetime.signal, AbortSignal.timeout(requestTimeoutMs), ...(signal ? [signal] : [])]), redirect: 'error',
        });
      } catch { throw cloudflareError('無法連線 Cloudflare，請稍後重新授權並續跑；不會自動刪除資源。'); }
      if (response.status === 404 && missing) return null;
      if (method === 'GET' && (response.status === 429 || response.status >= 500) && attempt < 3) { await wait(500 * 2 ** attempt, undefined, { signal }); continue; }
      let data;
      try { data = await response.json(); } catch { throw cloudflareError('Cloudflare 回傳無法辨識的資料，已停止。'); }
      if (!response.ok || data.success !== true) throw cloudflareError(`Cloudflare 操作失敗（HTTP ${response.status}）；請確認 Pages 權限、帳號方案與額度，再續跑。`);
      return data;
    }
  }
  async function deployments(base, signal) {
    const result = [];
    for (let page = 1; page <= 20; page += 1) {
      const data = await api(`${base}/deployments?per_page=100&page=${page}`, { signal });
      if (!Array.isArray(data.result)) throw cloudflareError('Pages 部署清單格式不符。');
      result.push(...data.result);
      if (data.result.length < 100) return result;
    }
    throw cloudflareError('Pages 已有過多部署，不符合全新安裝條件。');
  }
  // Cloudflare may add a suffix when the name is taken elsewhere; trust only its answer.
  function pagesSubdomain(project, plan) {
    const subdomain = project?.subdomain;
    if (typeof subdomain !== 'string' || !/^[a-z0-9][a-z0-9-]{0,62}\.pages\.dev$/.test(subdomain) || !subdomain.startsWith(plan.pagesProject)) {
      throw cloudflareError('Cloudflare 未回傳可辨識的網站網址，已停止。');
    }
    return subdomain;
  }
  // Resume may only continue a project this run created. Every condition
  // below is evidence of that: the durable create intent, the exact name and
  // account, direct upload (no Git source), production branch 'main', and the
  // two env vars written atomically at creation. Once recorded, the project id,
  // settings fingerprint and subdomain must also stay unchanged.
  function verifyProject(project, context) {
    const { plan, checkpoint } = context;
    const intent = checkpoint.intents?.pagesProject;
    const recorded = checkpoint.resources ?? {};
    const vars = project?.deployment_configs?.production?.env_vars;
    const createdByThisRun = project && intent && intent.runId === plan.runId && intent.name === plan.pagesProject &&
      intent.accountId === plan.cloudflareAccountId && project.name === plan.pagesProject &&
      project.production_branch === 'main' && !project.source;
    const bindingsMatch = vars?.INSTALLER_RUN_ID?.value === plan.runId && vars?.FIREBASE_PROJECT_ID?.value === plan.projectId &&
      vars?.INSTALLER_RUN_ID?.type === 'plain_text' && vars?.FIREBASE_PROJECT_ID?.type === 'plain_text' &&
      Object.keys(vars || {}).every((key) => ['INSTALLER_RUN_ID', 'FIREBASE_PROJECT_ID'].includes(key));
    const unchangedSinceRecorded = (!recorded.pagesProjectId || project.id === recorded.pagesProjectId) &&
      (!recorded.pagesConfigFingerprint || configurationFingerprint(project) === recorded.pagesConfigFingerprint) &&
      (!recorded.pagesSubdomain || project.subdomain === recorded.pagesSubdomain);
    if (!createdByThisRun || !bindingsMatch || !unchangedSinceRecorded) {
      throw cloudflareError('Pages 目標已存在或設定已變更，且無法確認屬於本次安裝；不會接管或覆蓋。');
    }
  }
  // Every deployment must be this run's production upload (same marker).
  function assertOnlyOwnDeployments(existing, marker) {
    for (const deployment of existing) {
      if (!marker || deployment.environment !== 'production' || deployment.deployment_trigger?.metadata?.branch !== 'main' ||
          deployment.deployment_trigger?.metadata?.commit_message !== marker) {
        throw cloudflareError('Pages 已有非本次安裝的部署，已停止；不會覆蓋既有網站。');
      }
    }
  }
  const projectRoute = (plan) => `/accounts/${plan.cloudflareAccountId}/pages/projects/${plan.pagesProject}`;
  async function prepare(context) {
    const { plan, signal } = context;
    if (!ACCOUNT_ID.test(plan.cloudflareAccountId) || !/^[a-z0-9][a-z0-9-]{0,57}$/.test(plan.pagesProject) || !/^[A-Za-z0-9_-]{8,80}$/.test(plan.runId) || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(plan.projectId)) throw cloudflareError('Cloudflare 安裝計畫格式不符。');
    const identity = await inspectIdentity({ signal });
    if (!identity.accounts.some((account) => account.id === plan.cloudflareAccountId)) throw cloudflareError('請明確選擇目前已授權的 Cloudflare 帳號。');
    return (await api(projectRoute(plan), { signal, missing: true }))?.result;
  }
  // Read-only check before confirmation: the account is usable and the name free.
  async function preflight(plan, { signal } = {}) {
    if (await prepare({ plan, signal })) throw cloudflareError('此網站名稱已被使用；請重新整理頁面，以新的安裝識別碼重新預覽。');
  }
  async function createPagesProject(context) {
    const { plan, checkpoint, save, signal } = context;
    let project = await prepare(context);
    if (!project) {
      if (checkpoint.resources?.pagesProjectId) throw cloudflareError('本次 Pages 專案已被移除，已停止以避免重建其他站台。');
      const intent = { runId: plan.runId, accountId: plan.cloudflareAccountId, name: plan.pagesProject };
      await save({ intents: { pagesProject: intent } });
      checkpoint.intents = { ...checkpoint.intents, pagesProject: intent };
      await api(`/accounts/${plan.cloudflareAccountId}/pages/projects`, { method: 'POST', signal, body: {
        name: plan.pagesProject, production_branch: 'main', deployment_configs: {
          production: { env_vars: { FIREBASE_PROJECT_ID: { type: 'plain_text', value: plan.projectId }, INSTALLER_RUN_ID: { type: 'plain_text', value: plan.runId } } },
        },
      } });
      project = (await api(projectRoute(plan), { signal })).result;
    }
    verifyProject(project, context);
    assertOnlyOwnDeployments(await deployments(projectRoute(plan), signal), checkpoint.intents?.pagesPublish?.marker);
    await save({ resources: { pagesProjectId: project.id, pagesProject: project.name, pagesSubdomain: pagesSubdomain(project, plan), pagesConfigFingerprint: configurationFingerprint(project) } });
    return { pagesProject: project.name };
  }
  async function publish(context) {
    const { plan, checkpoint, save, signal, transient } = context;
    const base = projectRoute(plan);
    const project = await prepare(context);
    verifyProject(project, context);
    const existing = await deployments(base, signal);
    const publishIntent = checkpoint.intents?.pagesPublish;
    assertOnlyOwnDeployments(existing, publishIntent?.marker);
    if (!transient.buildDir || !transient.buildVersion) throw cloudflareError('缺少已驗證的建置產物，禁止發佈。');
    await verifyUpload(transient.buildDir);
    const marker = `installer:${plan.runId}:${transient.buildVersion}`;
    if (publishIntent && publishIntent.marker !== marker) throw cloudflareError('本次建置版本已改變，請勿用續跑覆蓋已部署內容。');
    await save({ intents: { pagesPublish: { marker } } });
    const completed = (item) => item?.latest_stage?.name === 'deploy' && item.latest_stage.status === 'success';
    const failed = (item) => ['failure', 'canceled'].includes(item?.latest_stage?.status);
    const previousFailures = new Set(existing.filter(failed).map((item) => item.id));
    let deployment = existing.find(completed) || existing.find((item) => !failed(item));
    if (!deployment) {
      verifyProject((await api(base, { signal })).result, context);
      const result = await cli(['pages', 'deploy', transient.buildDir, '--project-name', plan.pagesProject, '--branch', 'main', '--commit-message', marker, '--commit-dirty=true'], { signal, accountId: plan.cloudflareAccountId, timeoutMs: 600_000 });
      if (result.exitCode !== 0) throw cloudflareError('Pages 發佈尚未確認完成；請重新授權並續跑，安裝器會先查詢實際部署狀態。');
    }
    for (let attempt = 0; attempt < 60; attempt += 1) {
      const all = await deployments(base, signal);
      if (all.some((item) => item.environment !== 'production' || item.deployment_trigger?.metadata?.branch !== 'main' || item.deployment_trigger?.metadata?.commit_message !== marker)) throw cloudflareError('發佈期間偵測到其他 Pages 部署，已停止。');
      deployment = all.find(completed) || all.find((item) => !failed(item)) || all.find((item) => !previousFailures.has(item.id));
      if (completed(deployment)) {
        const current = (await api(base, { signal })).result;
        verifyProject(current, context);
        const website = `https://${pagesSubdomain(current, plan)}`;
        transient.website = website;
        await save({ resources: { pagesDeploymentId: deployment.id, website } });
        return { website };
      }
      if (failed(deployment)) throw cloudflareError('Pages 部署失敗，請至 Cloudflare 官方部署頁確認原因；不會自動覆寫。');
      await wait(2000, undefined, { signal });
    }
    throw cloudflareError('Pages 部署仍未完成，請稍後續跑以確認實際狀態。');
  }
  async function execute(step, context) {
    if (!STEP_IDS.has(step)) throw cloudflareError('不支援的 Cloudflare 安裝步驟。');
    return step === 'pages-project' ? createPagesProject(context) : publish(context);
  }
  async function dispose() {
    disposed = true;
    lifetime.abort();
    await initializing?.catch(() => {});
    await Promise.allSettled([...activeCommands]);
    if (home) await rm(home, { recursive: true, force: true });
  }
  return { inspectIdentity, startLogin, preflight, execute, dispose };
}
