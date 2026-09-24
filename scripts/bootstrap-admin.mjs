#!/usr/bin/env node
// 首位管理員的一次性離線預覽／create-only 建立工具；不建立或更改 Auth 帳號。
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { validateChurchConfig } from '../worker/church_config.js';

const help = `Usage:
  node scripts/bootstrap-admin.mjs --project PROJECT --uid AUTH_UID --name NAME [--username NAME]
  node scripts/bootstrap-admin.mjs --project PROJECT --email EMAIL --name NAME [--config PATH]

預設 dry-run：完全離線，不讀憑證、不查 Auth、不寫 Firestore。
先在 Firebase Console 建立並確認屬於首位管理員的 Email/Password Auth 帳號。
真正建立時另加 --apply --confirm-project PROJECT --confirm-uid AUTH_UID。
--config PATH 選填：使用與部署相同的完整 church.json 驗證，再由 enabled services 建立 zones / zoneTypes。
登入憑證：GOOGLE_OAUTH_ACCESS_TOKEN，或 gcloud auth application-default print-access-token。
`;

export function parseArgs(args) {
  const result = { apply: false };
  const flags = new Set(['project', 'uid', 'email', 'name', 'username', 'config', 'confirm-project', 'confirm-uid']);
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--help') return { help: true };
    if (arg === '--apply') { result.apply = true; continue; }
    const key = arg.slice(2);
    if (!arg.startsWith('--') || !flags.has(key) || !args[i + 1] || args[i + 1].startsWith('--')) {
      throw new Error(`不支援或缺值的參數：${arg}`);
    }
    if (Object.hasOwn(result, key)) throw new Error(`重複參數：${arg}`);
    result[key] = args[++i].trim();
  }
  if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(result.project ?? '')) {
    throw new Error('請用 --project 明確指定 Firebase project ID（不是 project number）。');
  }
  if (!result.uid && !result.email) throw new Error('必須提供 --uid 或 --email。');
  if (result.uid && !validUid(result.uid)) throw new Error('Auth UID 不可包含斜線或控制字元，長度為 1–128。');
  if (result.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result.email)) throw new Error('Email 格式不正確。');
  if (!result.name || result.name.length > 100) throw new Error('--name 為必填，且最多 100 字。');
  result.username ??= result.name;
  if (!result.username || result.username.length > 100) throw new Error('--username 最多 100 字。');
  if (result.apply && (result['confirm-project'] !== result.project || !validUid(result['confirm-uid']))) {
    throw new Error('--apply 還必須提供相同的 --confirm-project，以及 Console 中核對過的 --confirm-uid。');
  }
  if (result.apply && result.uid && result.uid !== result['confirm-uid']) throw new Error('確認 UID 與指定 UID 不一致。');
  return result;
}

function validUid(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 128 && !['.', '..'].includes(value) && !/[\/\x00-\x1f\x7f]/.test(value);
}

export function enabledServiceIds(config) {
  if (config === undefined) return [];
  return validateChurchConfig(config).services
    .filter((service) => service.enabled)
    .map((service) => service.id);
}

export function buildAdminProfile(options, authUser, serviceIds = []) {
  if (!validUid(authUser.localId) || !authUser.email) throw new Error('Auth 帳號必須有有效 UID 與 email。');
  if (authUser.disabled) throw new Error('Auth 帳號已停用，拒絕建立管理員。');
  if (options.uid && authUser.localId !== options.uid) throw new Error('Auth 回傳 UID 與指定 UID 不一致。');
  if (options.email && authUser.email.toLowerCase() !== options.email.toLowerCase()) throw new Error('Auth 回傳 email 與指定 email 不一致。');
  if (options.apply && authUser.localId !== options['confirm-uid']) throw new Error('Auth 帳號與核對過的 UID 不一致；未寫入。');
  return {
    id: authUser.localId,
    name: options.name,
    email: authUser.email,
    username: options.username,
    role: 'admin',
    zones: serviceIds.map((id) => ({ serviceType: id, smallGroups: [], ministries: [] })),
    zoneTypes: serviceIds,
    groups: [],
  };
}

export function firestoreValue(value) {
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(firestoreValue) } };
  if (value && typeof value === 'object') return { mapValue: { fields: firestoreFields(value) } };
  throw new Error('不支援的 Firestore 欄位型別。');
}

function firestoreFields(object) {
  return Object.fromEntries(Object.entries(object).map(([key, value]) => [key, firestoreValue(value)]));
}

export async function bootstrap(options, {
  fetchImpl = globalThis.fetch,
  getAccessToken = () => process.env.GOOGLE_OAUTH_ACCESS_TOKEN || execFileSync(
    'gcloud', ['auth', 'application-default', 'print-access-token'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  ).trim(),
  readConfig = (path) => JSON.parse(readFileSync(path, 'utf8')),
  log = console.log,
} = {}) {
  // 驗證也在這層執行，避免程式化呼叫繞過 CLI 的確認旗標。
  const validated = parseArgs([
    '--project', options.project, '--name', options.name,
    ...Object.entries(options).filter(([key]) => !['project', 'name', 'apply'].includes(key))
      .flatMap(([key, value]) => [`--${key}`, String(value)]),
    ...(options.apply ? ['--apply'] : []),
  ]);
  const serviceIds = enabledServiceIds(validated.config ? readConfig(validated.config) : undefined);
  log(`目標 project=${validated.project}; database=(default); Auth=${validated.uid ?? validated.email}; name=${validated.name}`);
  log(`操作：只建立 users/{Auth UID}，role=admin；不修改 Auth、不覆寫既有 profile。zones=${JSON.stringify(serviceIds)}`);
  if (!validated.apply) {
    log('DRY RUN（離線）：尚未驗證 Auth 身分、IAM 權限或 profile 是否存在；沒有任何 API 呼叫。');
    return { applied: false, project: validated.project, serviceIds };
  }
  const token = await getAccessToken();
  if (!token || typeof token !== 'string' || /\s/.test(token)) throw new Error('無法取得有效 OAuth access token。');
  const headers = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    'x-goog-user-project': validated.project,
  };
  const request = (url, init = {}) => fetchImpl(url, { ...init, headers, redirect: 'error', signal: AbortSignal.timeout(30_000) });
  const lookup = await request(`https://identitytoolkit.googleapis.com/v1/projects/${validated.project}/accounts:lookup`, {
    method: 'POST',
    body: JSON.stringify(validated.uid ? { localId: [validated.uid] } : { email: [validated.email] }),
  });
  if (!lookup.ok) throw new Error(`Firebase Auth lookup 失敗（HTTP ${lookup.status}）；未寫入。`);
  const { users } = await lookup.json();
  if (!Array.isArray(users) || users.length !== 1) throw new Error('找不到唯一的 Firebase Auth 帳號；請先在 Console 建立並核對。');
  const profile = buildAdminProfile(validated, users[0], serviceIds);
  const documentName = `projects/${validated.project}/databases/(default)/documents/users/${profile.id}`;
  const existing = await request(`https://firestore.googleapis.com/v1/projects/${validated.project}/databases/(default)/documents/users/${encodeURIComponent(profile.id)}`);
  if (existing.ok) throw new Error('users profile 已存在；不覆寫、不升權。請由既有管理員處理。');
  if (existing.status !== 404) throw new Error(`無法確認 profile 不存在（HTTP ${existing.status}）；未寫入。`);
  log(`已核對 Auth uid=${profile.id}; email=${profile.email}。準備 create-only 寫入 ${documentName}。`);
  const committed = await request(`https://firestore.googleapis.com/v1/projects/${validated.project}/databases/(default)/documents:commit`, {
    method: 'POST',
    body: JSON.stringify({ writes: [{ update: { name: documentName, fields: firestoreFields(profile) }, currentDocument: { exists: false } }] }),
  });
  if (!committed.ok) throw new Error(`建立失敗（HTTP ${committed.status}）；若文件已存在，create-only 條件會拒絕，不會覆寫。`);
  log('已建立管理員 profile。請用 Console 建立的 Auth email/password 登入並驗證權限。');
  return { applied: true, profile };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) console.log(help);
    else await bootstrap(options);
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'Bootstrap failed.');
    process.exitCode = 1;
  }
}
