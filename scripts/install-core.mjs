#!/usr/bin/env node
import { mkdtemp, lstat, readFile, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { createInstallationManager, installationError } from './installer/core.mjs';
import { startInstallerServer } from './installer/server.mjs';
import { runCommand } from './installer/process.mjs';
import { isPrivateDirectory, projectIdFor } from './installer/shared.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// The release this checkout would install or update to (shown by the wizard).
export async function readLocalRelease(root = ROOT) {
  try {
    const { version, notes } = JSON.parse(await readFile(path.join(root, 'release.json'), 'utf8'));
    if (typeof version !== 'string') return undefined;
    return { version, notes: Array.isArray(notes) ? notes.filter((note) => typeof note === 'string').slice(0, 10) : [] };
  } catch { return undefined; }
}

// Every commit from RESUMES_FROM up to this checkout: unfinished installs
// planned by any of them can be continued, so an update never strands them.
// scripts/start-installation.sh applies the same rule before updating.
// Without that history (e.g. a shallow clone) only this exact version resumes.
const COMMIT = /^[0-9a-f]{40}$/;
export async function readResumableRevisions(root = ROOT) {
  try {
    const floor = (await readFile(path.join(root, 'scripts/installer/RESUMES_FROM'), 'utf8')).split('\n')[0].trim();
    if (!COMMIT.test(floor)) return [];
    const { stdout } = await runCommand('git', ['rev-list', '--ancestry-path', `${floor}..HEAD`], { cwd: root });
    return [floor, ...stdout.split('\n').filter((line) => COMMIT.test(line))];
  } catch { return []; }
}

export function createDemoProviders({ failAt, delayMs = 150 } = {}) {
  let failed = false;
  const googleEmail = 'operator@example.invalid';
  const accounts = [{ id: '0123456789abcdef0123456789abcdef', name: '離線示範帳號' }];
  // One site this demo pretends was installed earlier, for update mode.
  const installedRunId = '4f1c2a9e-7b3d-4e8a-9c61-2d5f0a8b3e17';
  const installed = { accountId: accounts[0].id, accountName: accounts[0].name, pagesProject: 'grace-church-staff',
    subdomain: 'grace-church-staff.pages.dev', runId: installedRunId, projectId: projectIdFor(installedRunId) };
  const installedConfig = { schemaVersion: 1, appName: '恩典教會同工助手', shortName: '恩典同工', timeZone: 'Asia/Taipei',
    services: [{ id: 'service1', label: '主日', name: '主日崇拜', weekday: 7, enabled: true }] };
  const pause = (context) => delay(delayMs, undefined, { signal: context.signal });
  // Whether the pretend site stores an account management key (it starts without).
  let accountAdminKey = false;
  const execute = async (step, context) => {
    context.signal?.throwIfAborted();
    await delay(delayMs, undefined, { signal: context.signal });
    if (step === failAt && !failed) {
      failed = true;
      throw installationError('示範中斷：按「核對後接續安裝」可繼續。同一個新專案不會重複建立。', 'DEMO_INTERRUPTION');
    }
    await context.save({
      intents: { [step]: { runId: context.plan.runId, demo: true } },
      resources: {
        [step]: { verified: true, demo: true },
        ...(step === 'pages-project' ? { pagesSubdomain: `${context.plan.pagesProject}.pages.dev` } : {}),
        ...(step === 'publish' ? { website: `https://${context.plan.pagesProject}.pages.dev/` } : {}),
      },
    });
  };
  return {
    fetchAsset: async () => null,
    fetchSite: async (url) => url.endsWith('/church-config.json') ? structuredClone(installedConfig)
      : url.endsWith('/version.json') ? { version: 'installer-demo-old', release: '2026.9.1', channel: 'installer' } : null,
    google: {
      inspectIdentity: async () => ({ email: googleEmail }), execute, update: async (step, context) => pause(context),
      newAccountAdminKey: async (context, { configured }) => { await pause(context); return configured ? null : { id: '0123456789abcdef', json: '{"demo":true}' }; },
      retireOtherAccountAdminKeys: pause,
    },
    cloudflare: {
      listInstalls: async () => [structuredClone(installed)],
      publishUpdate: async (context) => { await pause(context); return { website: `https://${installed.subdomain}/`, unchanged: false }; },
      addCustomDomain: async (context) => {
        await pause(context);
        const domain = context.plan.customDomain;
        return { domain, status: 'pending', cname: { name: domain.split('.')[0], fullName: domain, target: installed.subdomain } };
      },
      startLogin: async ({ emit, signal }) => {
        emit({ message: '離線示範：模擬官方授權等待，不會開啟真實登入頁' });
        await delay(delayMs, undefined, { signal });
      },
      inspectIdentity: async () => ({ loggedIn: true, email: googleEmail, accounts }),
      accountAdminKeyState: async (context) => { await pause(context); return { stored: accountAdminKey, live: accountAdminKey }; },
      storeAccountAdminKey: async (context) => { await pause(context); accountAdminKey = true; },
      execute, dispose: async () => {},
    },
    build: (context) => execute('build', context),
  };
}

function argumentsFrom(argv) {
  const options = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (['--demo', '--cloud-shell', '--help'].includes(arg)) options[arg.slice(2)] = true;
    else if (['--port', '--resume', '--state-root', '--demo-fail-at'].includes(arg) && argv[i + 1] && !argv[i + 1].startsWith('--')) {
      options[arg.slice(2)] = argv[++i];
    } else throw new Error(`Unknown or incomplete option: ${arg}`);
  }
  if (options.help) return options;
  if (Boolean(options.demo) === Boolean(options['cloud-shell'])) throw new Error('請明確指定 --demo 或 --cloud-shell');
  if (!options.demo && (options['state-root'] || options['demo-fail-at'])) throw new Error('示範參數不能用於真實安裝');
  const port = Number(options.port ?? (options.demo ? 8765 : 8080));
  if (!Number.isInteger(port) || port < 2000 || port > 65000) throw new Error('port 必須介於 2000 到 65000');
  return { ...options, port };
}

export async function main(argv = process.argv.slice(2)) {
  const options = argumentsFrom(argv);
  if (options.help) {
    console.log('Usage: node scripts/install-core.mjs --demo [--port 8765] [--state-root DIRECTORY] [--demo-fail-at rules]\n       node scripts/install-core.mjs --cloud-shell [--resume RUN_ID]\nNo cloud requests run before explicit account connection and installation confirmation.');
    return;
  }
  let providers;
  let publicOrigin;
  let sourceRevision = 'offline-demo-v1';
  let resumableRevisions = [];
  let report;
  if (options.demo) providers = createDemoProviders({ failAt: options['demo-fail-at'] });
  else {
    const host = process.env.WEB_HOST;
    if (!host || !/^[a-z0-9.-]+\.cloudshell\.dev$/i.test(host)) throw new Error('請在 Google Cloud Shell 透過安裝教學啟動，不要將此工具公開架站');
    publicOrigin = `https://${options.port}-${host}`;
    const sessionRoot = process.env.INSTALLER_SESSION_ROOT;
    if (!sessionRoot || !path.isAbsolute(sessionRoot)) throw new Error('請先使用 scripts/start-installation.sh 準備獨立工具環境');
    const stat = await lstat(sessionRoot);
    if (!isPrivateDirectory(stat) ||
        await realpath(sessionRoot) !== path.resolve(sessionRoot)) throw new Error('授權暫存目錄必須是私有、真實的獨立目錄');
    const sessionDir = await mkdtemp(path.join(sessionRoot, 'session-'));
    const { createGoogleInstaller } = await import('./installer/google.mjs');
    const { createCloudflareInstaller } = await import('./installer/cloudflare.mjs');
    const { buildCoreDeployment } = await import('./installer/build.mjs');
    sourceRevision = (await runCommand('git', ['rev-parse', 'HEAD'], { cwd: ROOT })).stdout.trim();
    resumableRevisions = await readResumableRevisions();
    // CHURCH_INSTALLER_STATS=off: no counts, e.g. while testing the wizard.
    if (process.env.CHURCH_INSTALLER_STATS !== 'off') {
      const { createStatsReporter } = await import('./installer/stats.mjs');
      report = createStatsReporter({ revision: sourceRevision });
    }
    providers = {
      google: createGoogleInstaller(),
      cloudflare: createCloudflareInstaller({ sessionDir }),
      build: (context) => buildCoreDeployment(context),
    };
  }
  const rootDir = path.resolve(options['state-root'] ?? ROOT);
  const manager = createInstallationManager({ rootDir, ...providers, sourceRevision, resumableRevisions, report, demo: Boolean(options.demo), release: await readLocalRelease() });
  if (options.resume) await manager.load(options.resume);
  let server;
  try { server = await startInstallerServer({ manager, port: options.port, publicOrigin }); }
  catch (error) { await manager.dispose(); throw error; }
  console.log(options.demo ? '離線示範：不會連接或建立雲端資源。' : '私人安裝精靈已啟動。請只在自己的瀏覽器開啟以下連結：');
  console.log(server.url);
  report?.('opened');
  if (!options.demo) console.log('第一次點開時 Google 會先確認你的帳號；如果畫面請你再點一次，回到這裡再點同一個連結即可。');
  console.log('連結僅供這次私人工作階段使用，請勿分享。安裝期間請保持這個終端機開著，不要按 Ctrl+C；不小心停掉或關掉了，就重新按教學裡啟動精靈的那張指令卡接續，進度不會遺失。');
  let closing = false;
  const close = async () => {
    if (closing) return;
    closing = true;
    await server.close();
  };
  process.once('SIGINT', close);
  process.once('SIGTERM', close);
  return { server, manager, close };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => {
    console.error('無法啟動私人安裝精靈。請核對命令、Cloud Shell 環境與工具目錄權限；也可先以 --demo 驗證介面。');
    process.exitCode = 1;
  });
}
