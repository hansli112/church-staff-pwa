#!/usr/bin/env node
// 搬到馬大別忙（線上版）用的搬家檔：唯讀，只讀這個專案的 Firestore，不改任何東西。
// 格式見 https://github.com/hansli112/church-staff-pwa/blob/martha-main/docs/move-format.md
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const help = `Usage:
  node scripts/export-move.mjs [--project PROJECT] [--out move.json]

只讀 Firestore 的 users、settings、rosters、staff_orders，寫成一個搬家檔，
再到馬大別忙「建立教會 → 從舊版搬過來」上傳。不讀、也不寫 Firebase 登入的帳號與密碼。
沒有 --project 時，找你的帳號看得到、有服事表或服事項目設定的專案；只有一個就用它。
登入憑證：GOOGLE_OAUTH_ACCESS_TOKEN，或 gcloud auth print-access-token。
`;

export const COLLECTIONS = { users: 'users', settings: 'settings', rosters: 'rosters', staffOrders: 'staff_orders' };

export function parseArgs(args) {
  const result = { out: 'move.json' };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--help') return { help: true };
    if (arg !== '--project' && arg !== '--out') throw new Error(`不認得的參數：${arg}`);
    const value = args[++i];
    if (!value || value.startsWith('--')) throw new Error(`${arg} 後面要接值`);
    result[arg.slice(2)] = value;
  }
  if (result.project && !/^[a-z][a-z0-9-]{4,29}$/.test(result.project)) throw new Error(`專案 ID 的格式不對：${result.project}`);
  return result;
}

/** A Firestore REST value as the move file has it: times as {__time__}, references as their path. */
export function plain(value) {
  if ('nullValue' in value) return null;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('timestampValue' in value) return { __time__: new Date(value.timestampValue).toISOString() };
  if ('stringValue' in value) return value.stringValue;
  if ('bytesValue' in value) return value.bytesValue;
  if ('referenceValue' in value) return value.referenceValue.replace(/^projects\/[^/]+\/databases\/[^/]+\/documents\//, '');
  if ('geoPointValue' in value) return { latitude: value.geoPointValue.latitude ?? 0, longitude: value.geoPointValue.longitude ?? 0 };
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(plain);
  if ('mapValue' in value) return fields(value.mapValue.fields);
  throw new Error(`不認得的 Firestore 值：${Object.keys(value).join(', ')}`);
}

const fields = (map = {}) => Object.fromEntries(Object.entries(map).map(([key, value]) => [key, plain(value)]));

/** One REST document as {id, data}. */
export const doc = (d) => ({ id: d.name.slice(d.name.lastIndexOf('/') + 1), data: fields(d.fields) });

export async function exportMove({ project, fetchImpl = fetch, getAccessToken, now = () => new Date(), log = console.log }) {
  const token = await getAccessToken();
  const get = async (url) => {
    const response = await fetchImpl(url, { headers: { Authorization: `Bearer ${token}` } });
    if (response.status === 404) return null;
    if (!response.ok) {
      const reason = response.status === 403 ? '這個帳號沒有讀取權限，請用建立這個專案的 Google 帳號' : `HTTP ${response.status}`;
      throw new Error(`讀不到 ${url.split('?')[0]}：${reason}`);
    }
    return response.json();
  };
  const base = (id) => `https://firestore.googleapis.com/v1/projects/${id}/databases/(default)/documents`;

  if (!project) {
    const projects = [];
    let pageToken = '';
    do {
      const page = await get(`https://cloudresourcemanager.googleapis.com/v1/projects?filter=lifecycleState:ACTIVE&pageSize=200${pageToken && `&pageToken=${encodeURIComponent(pageToken)}`}`);
      projects.push(...(page?.projects ?? []).map((p) => p.projectId));
      pageToken = page?.nextPageToken ?? '';
    } while (pageToken);
    const found = [];
    for (const id of projects) {
      try {
        const rosters = await get(`${base(id)}/rosters?pageSize=1`);
        if (rosters?.documents?.length || await get(`${base(id)}/settings/roster_templates`)) found.push(id);
      } catch { /* not a church: no Firestore or no access */ }
    }
    if (found.length !== 1) {
      throw new Error(found.length
        ? `找到好幾個同工助手的專案：${found.join('、')}。請加上 --project 選一個。`
        : '找不到同工助手的專案。請確認登入的是建立網站的 Google 帳號，或加上 --project。');
    }
    project = found[0];
  }

  const read = async (collection) => {
    const docs = [];
    let pageToken = '';
    do {
      const page = await get(`${base(project)}/${collection}?pageSize=300${pageToken && `&pageToken=${encodeURIComponent(pageToken)}`}`);
      docs.push(...(page?.documents ?? []).map(doc));
      pageToken = page?.nextPageToken ?? '';
    } while (pageToken);
    return docs;
  };
  const file = { format: 'church-staff-pwa-move', version: 1, project, exportedAt: now().toISOString() };
  for (const [key, collection] of Object.entries(COLLECTIONS)) file[key] = await read(collection);
  if (!file.users.length && !file.rosters.length) throw new Error(`${project} 裡沒有同工也沒有服事表，確認專案對不對`);

  const noEmail = file.users.filter((u) => !u.data.email).length;
  log(`專案 ${project}：同工 ${file.users.length} 位（沒有 email 的 ${noEmail} 位）、服事表 ${file.rosters.length} 份、同工排序 ${file.staffOrders.length} 個`);
  return file;
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
      console.log(help);
    } else {
      const file = await exportMove({
        project: options.project,
        getAccessToken: () => process.env.GOOGLE_OAUTH_ACCESS_TOKEN || execFileSync(
          'gcloud', ['auth', 'print-access-token'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
        ).trim(),
      });
      writeFileSync(options.out, JSON.stringify(file));
      console.log(`已寫好 ${options.out}。在 Cloud Shell 執行 cloudshell download ${options.out} 下載，再到馬大別忙「建立教會 → 從舊版搬過來」上傳。`);
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
