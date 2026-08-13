// Live end-to-end check of the calendar write path.
//
// Imports the *real* worker/google_calendar.js — the same code the deployed
// Pages Function runs — and points it at the real Google Calendar API with the
// real service account key. Nothing here is mocked, so a pass means the JWT
// signing, the OAuth exchange, the API enablement and the calendar sharing are
// all genuinely working. The unit tests cannot tell you any of that.
//
// It creates one all-day event far in the future, reads it back, then deletes
// it. If the delete fails the id is printed so it can be removed by hand.
//
// Usage:
//     node scripts/verify-calendar-writer.mjs
//
// Reads the key from .local/service-account.json (gitignored) and the calendar
// id from .local/calendar-id, GOOGLE_CALENDAR_ID, or `gh variable get`.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildGoogleEvent, callCalendar } from '../worker/google_calendar.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Deliberately in 2099 so a failed cleanup cannot land in anyone's real week.
const PROBE_DATE = '2099-12-31';
const PROBE_TITLE = '（測試）行事曆寫入檢查，可以直接刪掉';

function die(message) {
  console.error(`✗ ${message}`);
  process.exit(1);
}

function serviceAccountJson() {
  const file = path.join(ROOT, '.local', 'service-account.json');
  try {
    return readFileSync(file, 'utf8');
  } catch {
    die(
      `找不到 ${path.relative(ROOT, file)}。\n` +
        '  先建立 service account 金鑰，或把既有的那份放到這個位置。',
    );
  }
}

function calendarId() {
  const fromEnv = process.env.GOOGLE_CALENDAR_ID?.trim();
  if (fromEnv) return fromEnv;
  try {
    return readFileSync(path.join(ROOT, '.local', 'calendar-id'), 'utf8').trim();
  } catch {
    // Fall through to gh.
  }
  try {
    return execFileSync('gh', ['variable', 'get', 'GOOGLE_CALENDAR_ID'], {
      cwd: ROOT,
      encoding: 'utf8',
    }).trim();
  } catch {
    die(
      '找不到 GOOGLE_CALENDAR_ID。三選一：\n' +
        '  export GOOGLE_CALENDAR_ID=...\n' +
        '  echo ... > .local/calendar-id\n' +
        '  gh auth login（讓這支自己去讀 repo variable）',
    );
  }
}

async function main() {
  const env = {
    GOOGLE_SERVICE_ACCOUNT_JSON: serviceAccountJson(),
    GOOGLE_CALENDAR_ID: calendarId(),
  };

  const account = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON).client_email;
  console.log(`service account : ${account}`);
  console.log(`calendar        : ${env.GOOGLE_CALENDAR_ID.slice(0, 12)}…`);
  console.log();

  let created;
  try {
    const response = await callCalendar(env, {
      method: 'POST',
      body: buildGoogleEvent({
        title: PROBE_TITLE,
        allDay: true,
        start: PROBE_DATE,
        description: '由 scripts/verify-calendar-writer.mjs 建立，應該會自動刪除。',
      }),
    });
    created = await response.json();
  } catch (error) {
    console.error(`✗ 寫入失敗：${error.message}`);
    if (error.status === 502) {
      console.error();
      console.error('  最常見的原因是日曆還沒分享給 service account。');
      console.error('  Google 日曆 → 該日曆設定 → 與特定使用者或群組共用 →');
      console.error(`  加入 ${account}，權限選「變更活動」。`);
    }
    process.exit(1);
  }

  console.log(`✓ 新增成功  id=${created.id}`);

  try {
    const response = await callCalendar(env, { method: 'GET', eventId: created.id });
    const readBack = await response.json();
    if (readBack.summary !== PROBE_TITLE) {
      die(`讀回來的標題對不上：${readBack.summary}`);
    }
    // end.date is exclusive, so a single-day event on the 31st ends on the 1st.
    if (readBack.start?.date !== PROBE_DATE) {
      die(`日期對不上：送出 ${PROBE_DATE}，讀回 ${readBack.start?.date}`);
    }
    console.log(`✓ 讀回確認  ${readBack.start.date} → ${readBack.end.date}（結束日不含當天，正確）`);
  } catch (error) {
    console.error(`✗ 讀回失敗：${error.message}`);
  }

  try {
    await callCalendar(env, { method: 'DELETE', eventId: created.id });
    console.log('✓ 刪除成功');
  } catch (error) {
    console.error(`✗ 刪除失敗：${error.message}`);
    console.error(`  請手動刪掉日曆上的「${PROBE_TITLE}」（${PROBE_DATE}）`);
    process.exit(1);
  }

  console.log();
  console.log('全部通過 —— 新增、讀取、刪除都打得到真正的 Google Calendar。');
}

await main();
