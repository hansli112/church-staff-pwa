import { createHash } from 'node:crypto';
import { chmod, lstat, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { prepareDeployment, validateChurchConfig } from '../prepare-deployment.mjs';
import { FIREBASE_KEYS, finalizeWebDeployment, OPTIONAL_FIREBASE_KEYS as OPTIONAL } from '../finalize-web-deployment.mjs';
import { privateEnvironment, runIsolatedCommand } from './process.mjs';
import { CORE_ICONS, FLUTTER_VERSION, installationError, isPrivateDirectory, verifyBuildArtifacts, WRANGLER_VERSION } from './shared.mjs';

export { FLUTTER_VERSION };

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const buildError = (message) => installationError(message, 'BUILD_FAILED');
const WEB_CONFIG_FIELDS = {
  FIREBASE_API_KEY: 'apiKey', FIREBASE_AUTH_DOMAIN: 'authDomain', FIREBASE_PROJECT_ID: 'projectId',
  FIREBASE_STORAGE_BUCKET: 'storageBucket', FIREBASE_MESSAGING_SENDER_ID: 'messagingSenderId',
  FIREBASE_APP_ID: 'appId', FIREBASE_MEASUREMENT_ID: 'measurementId',
};

async function safeCopy(source, target, hash, relative) {
  const stat = await lstat(source);
  if (stat.isDirectory()) {
    await mkdir(target, { recursive: true, mode: 0o700 });
    for (const entry of (await readdir(source)).sort()) await safeCopy(path.join(source, entry), path.join(target, entry), hash, `${relative}/${entry}`);
  } else if (stat.isFile() && stat.nlink === 1) {
    const bytes = await readFile(source);
    hash.update(relative).update('\0').update(bytes).update('\0');
    await writeFile(target, bytes, { mode: 0o600 });
  } else throw buildError('建置來源不得包含符號連結、硬連結或特殊檔案。');
}

async function requiredFile(dir, name) {
  const stat = await lstat(path.join(dir, name)).catch(() => null);
  if (!stat?.isFile() || stat.nlink !== 1 || stat.size === 0) throw buildError(`建置不完整，缺少 ${name}；禁止發佈。`);
}

export async function buildCoreDeployment(context, { command = runIsolatedCommand, root = ROOT, flutter = process.env.INSTALLER_FLUTTER || 'flutter', wrangler = process.env.INSTALLER_WRANGLER || 'wrangler', environment = process.env, prepare = prepareDeployment, finalize = finalizeWebDeployment } = {}) {
  const { plan, runDir, transient, signal, emit = () => {}, save = async () => {} } = context;
  const config = validateChurchConfig(plan.churchConfig);
  if (Object.values(config.features).some(Boolean) || config.devotional.enabled || Object.entries(CORE_ICONS).some(([key, value]) => config.icons[key] !== value)) throw buildError('首次安裝只支援核心功能與中性圖示。');
  if (!path.isAbsolute(runDir) || path.resolve(runDir) === root || !/^[A-Za-z0-9_-]{8,80}$/.test(plan.runId)) throw buildError('建置需要獨立的安裝目錄。');
  const runStat = await lstat(runDir);
  if (!isPrivateDirectory(runStat)) throw buildError('安裝目錄必須為私人目錄（0700）。');
  // The Google adapter returns Firebase's JS SDK shape; Flutter and the
  // finalizer use dart-define names. This is the only place that converts them.
  const source = transient.firebaseConfig ?? {};
  const firebase = Object.fromEntries(FIREBASE_KEYS.map((key) => {
    const value = source[WEB_CONFIG_FIELDS[key]] ?? source[key] ?? (OPTIONAL.has(key) ? '' : undefined);
    if (typeof value !== 'string' || (!OPTIONAL.has(key) && !value.trim())) throw buildError(`缺少 ${key}，無法建置。`);
    return [key, value];
  }));
  if (firebase.FIREBASE_PROJECT_ID !== plan.projectId) throw buildError('Firebase 建置設定不屬於本次安裝專案。');
  // Keep both intermediate and final Flutter outputs out of the checkout.
  // A dedicated source copy also prevents pub get from changing its lockfile.
  let workRoot = runDir;
  if (environment.INSTALLER_BUILD_ROOT) {
    const temporaryRoot = environment.INSTALLER_BUILD_ROOT;
    const stat = await lstat(temporaryRoot);
    if (!path.isAbsolute(temporaryRoot) || !isPrivateDirectory(stat)) throw buildError('暫存建置根目錄必須是私人絕對路徑。');
    workRoot = path.join(temporaryRoot, plan.runId);
    await mkdir(workRoot, { recursive: true, mode: 0o700 });
    if (!(await lstat(workRoot)).isDirectory()) throw buildError('暫存建置目錄不得是符號連結。');
  }
  const workspace = path.join(workRoot, 'build-workspace');
  const buildDir = path.join(workRoot, 'web-build');
  const stagingDir = path.join(runDir, 'deployment');
  for (const dir of [workspace, buildDir]) {
    // Ownership receipts stay outside the public upload and survive Flutter's
    // replacement of --output, including a failed/incomplete build.
    const receipt = path.join(workRoot, `.installer-${path.basename(dir)}`);
    const old = await lstat(dir).catch((error) => { if (error.code === 'ENOENT') return null; throw error; });
    if (old && (!old.isDirectory() || (await readFile(receipt, 'utf8').catch(() => '')) !== plan.runId)) throw buildError('建置目錄包含未知內容，禁止覆寫。');
    if (old) await rm(dir, { recursive: true });
    await writeFile(receipt, plan.runId, { mode: 0o600 });
    await mkdir(dir, { mode: 0o700 });
  }
  const home = path.join(workspace, 'home');
  await mkdir(path.join(home, 'tmp'), { recursive: true, mode: 0o700 });
  const env = { ...privateEnvironment(home, environment), FLUTTER_SUPPRESS_ANALYTICS: 'true', DART_SUPPRESS_ANALYTICS: 'true', PUB_CACHE: environment.PUB_CACHE || path.join(home, 'pub-cache') };
  async function run(executable, args, timeoutMs = 120_000, cwd = workspace) {
    let result;
    try { result = await command(executable, args, { cwd, env, signal, timeoutMs }); } catch { throw buildError('建置工具無法執行、遭取消或逾時；請由 Cloud Shell 安裝入口重開。'); }
    if (result.exitCode !== 0) throw buildError('建置工具未成功完成；請檢查工具版本、可用磁碟空間與套件下載連線後重試。');
    return result.stdout;
  }
  const flutterInfo = await run(flutter, ['--version', '--machine']);
  let version;
  try { version = JSON.parse(flutterInfo).frameworkVersion; } catch { /* Fixed error below. */ }
  if (version !== FLUTTER_VERSION) throw buildError(`需要 Flutter ${FLUTTER_VERSION}，請由 Cloud Shell 安裝入口重開。`);
  if ((await run(wrangler, ['--version'])).trim() !== WRANGLER_VERSION) throw buildError(`需要 Wrangler ${WRANGLER_VERSION}。`);
  emit({ type: 'progress', step: 'build', message: '正在準備隔離的核心功能建置；不修改原始程式或正式設定。' });
  const hash = createHash('sha256').update(JSON.stringify({ runId: plan.runId, config, firebase }));
  for (const name of ['lib', 'web', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']) await safeCopy(path.join(root, name), path.join(workspace, name), hash, name);
  await mkdir(path.join(workspace, 'scripts'), { mode: 0o700 });
  await safeCopy(path.join(root, 'scripts/generate-neutral-icons.mjs'), path.join(workspace, 'scripts/generate-neutral-icons.mjs'), hash, 'scripts/generate-neutral-icons.mjs');
  await run(process.execPath, [path.join(workspace, 'scripts/generate-neutral-icons.mjs')]);
  const configPath = path.join(runDir, 'church.json');
  const firebasePath = path.join(runDir, 'firebase-config.json');
  await writeFile(configPath, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
  await writeFile(firebasePath, JSON.stringify(firebase, null, 2) + '\n', { mode: 0o600 });
  await chmod(firebasePath, 0o600);
  await prepare({ configPath, outDir: stagingDir, assetsDir: path.join(workspace, 'web'), root });
  // Worker and rules must participate in the stable cache/build identity too.
  for (const name of ['worker', 'functions', 'firestore.rules']) await safeCopy(path.join(stagingDir, name), path.join(workspace, name), hash, name);
  const buildVersion = `installer-${hash.digest('hex').slice(0, 24)}`;
  const generatedAt = context.checkpoint?.intents?.build?.generatedAt || plan.createdAt || new Date().toISOString();
  await save({ intents: { build: { buildVersion, generatedAt, flutterVersion: FLUTTER_VERSION, wranglerVersion: WRANGLER_VERSION } } });
  await writeFile(path.join(workspace, 'web/version.json'), JSON.stringify({ version: buildVersion, build_number: plan.runId, branch: 'main', generated_at: generatedAt }) + '\n');
  await run(flutter, ['pub', 'get', '--enforce-lockfile'], 600_000);
  await run(flutter, ['build', 'web', '--release', '--base-href', '/', '--no-web-resources-cdn', '--output', buildDir, `--dart-define-from-file=${path.join(stagingDir, 'dart-defines.json')}`, `--dart-define-from-file=${firebasePath}`], 1_200_000);
  for (const name of ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'cache_sw.js', 'version.json', 'canvaskit/canvaskit.wasm']) await requiredFile(buildDir, name);
  await finalize({ buildDir, stagingDir, firebaseConfig: firebase, buildVersion, vendorVersion: `flutter-${FLUTTER_VERSION}` });
  await run(wrangler, ['pages', 'functions', 'build', path.join(stagingDir, 'functions'), `--outdir=${path.join(buildDir, '_worker.js')}`], 120_000);
  // Same completeness contract publish re-checks before uploading.
  await verifyBuildArtifacts(buildDir, buildError);
  transient.buildDir = buildDir;
  transient.buildVersion = buildVersion;
  transient.deploymentDir = stagingDir;
  await save({ resources: { buildVersion } });
  return { buildDir, buildVersion, deploymentDir: stagingDir };
}
