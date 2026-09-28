// Contract shared by the installer core and its adapters. Keeping it in one
// place means a new step, tool version or build artifact is declared once.
import { createHash } from 'node:crypto';
import { lstat, readFile } from 'node:fs/promises';
import path from 'node:path';

export const FLUTTER_VERSION = '3.41.0';
export const WRANGLER_VERSION = '4.138.0';

// Order is execution order. `provider` selects the adapter that owns the step.
export const STEPS = [
  ['google-project', '建立專屬 Google 專案', 'google'],
  ['firebase', '準備 Firebase', 'google'],
  ['database', '建立資料庫', 'google'],
  ['auth', '設定帳號登入', 'google'],
  ['web-app', '取得網站設定', 'google'],
  ['pages-project', '準備網站空間', 'cloudflare'],
  ['build', '建置教會網站', 'build'],
  ['rules', '部署資料存取規則', 'google'],
  ['admin', '建立指定管理員', 'google'],
  ['publish', '發布網站', 'cloudflare'],
  ['auth-domains', '設定登入網域', 'google'],
  ['activation', '寄送管理員設定密碼信', 'google'],
].map(([id, label, provider]) => ({ id, label, provider }));

export const stepIdsFor = (provider) => new Set(STEPS.filter((step) => step.provider === provider).map((step) => step.id));

// First installs only use the neutral artwork shipped in web/.
export const CORE_ICONS = Object.freeze({
  favicon: 'favicon.png', icon192: 'icons/Icon-192.png', icon512: 'icons/Icon-512.png',
  maskable192: 'icons/Icon-maskable-192.png', maskable512: 'icons/Icon-maskable-512.png',
});

// Project and Pages names are derived from the run so a retry can never pick
// a different target.
export const projectIdFor = (runId) => `church-${runId.replaceAll('-', '').slice(0, 20)}`;

export function installationError(message, code = 'INSTALLATION_ERROR') {
  return Object.assign(new Error(message), { code, safeToDisplay: true });
}

export const sha256 = (text) => createHash('sha256').update(text).digest('hex');

// Key order must not change a fingerprint, so objects are serialized sorted.
export const canonical = (value) => JSON.stringify(value, (_, entry) => entry && !Array.isArray(entry) && typeof entry === 'object'
  ? Object.fromEntries(Object.keys(entry).sort().map((key) => [key, entry[key]])) : entry);
export const fingerprint = (value) => sha256(canonical(value) ?? 'null');

export const isPrivateDirectory = (stat) => stat.isDirectory() && !stat.isSymbolicLink() && (stat.mode & 0o077) === 0;

// A complete, finalized Pages upload. Build checks it after finalizing and
// publish checks it again right before upload.
const REQUIRED_BUILD_FILES = ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'cache_sw.js', 'firebase-messaging-sw.js', 'version.json', 'canvaskit/canvaskit.wasm', '_worker.js/index.js'];
const UNRESOLVED_PLACEHOLDER = /__(?:FIREBASE_[A-Z_]+|BUILD_VERSION|VENDOR_VERSION)__/;

export async function verifyBuildArtifacts(directory, fail) {
  for (const name of REQUIRED_BUILD_FILES) {
    const stat = await lstat(path.join(directory, name)).catch(() => null);
    if (!stat?.isFile() || stat.size === 0) throw fail('建置產物不完整，禁止發佈。');
  }
  for (const name of ['cache_sw.js', 'firebase-messaging-sw.js']) {
    if (UNRESOLVED_PLACEHOLDER.test(await readFile(path.join(directory, name), 'utf8'))) throw fail('建置含未替換設定，禁止發佈。');
  }
}
