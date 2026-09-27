#!/usr/bin/env node
// Scheduled fetch of the configured devotional source into the data branch.
// The adapters live in worker/devotional.js so the site's same-day fallback
// accepts exactly the same sources.
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { validateChurchConfig } from '../worker/church_config.js';
import { fetchDailyVerse } from '../worker/devotional.js';

export { fetchDailyVerse, parseDailyBibleHtml, validateDailyVerse } from '../worker/devotional.js';

export function devotionalFetchSettings(rawConfig) {
  if (!rawConfig?.trim()) return { enabled: false };
  const config = validateChurchConfig(JSON.parse(rawConfig));
  return {
    enabled: config.devotional.enabled && Boolean(config.devotional.fetchUrl),
    url: config.devotional.fetchUrl ?? '',
    format: config.devotional.fetchFormat ?? 'json',
    timeZone: config.timeZone,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0') throw new Error('不允許停用 TLS 驗證。');
    const [output, ...extra] = process.argv.slice(2);
    if (!output || extra.length || (output.startsWith('--') && output !== '--check-config')) {
      throw new Error('Usage: CHURCH_CONFIG_JSON=<public-config-json> node scripts/fetch-daily-verse.mjs OUTPUT.json|--check-config');
    }
    const settings = devotionalFetchSettings(process.env.CHURCH_CONFIG_JSON);
    if (output === '--check-config') {
      console.log(`enabled=${settings.enabled}`);
    } else if (!settings.enabled) {
      console.log('未啟用靈糧抓取或 fetchUrl 為空；沒有網路請求，也未寫檔。');
    } else {
      const data = await fetchDailyVerse(settings.url, { timeZone: settings.timeZone, format: settings.format });
      writeFileSync(output, `${JSON.stringify(data, null, 2)}\n`);
      console.log(`已驗證靈糧來源；日期 ${data.date}。內容與再散布授權仍須部署者確認。`);
    }
  } catch (error) {
    // URL 可能含 feed 的 access token，避免直接印出 fetch 的錯誤或 payload。
    console.error(error instanceof SyntaxError ? '設定或來源不是有效 JSON；只有明確選擇 dailyBibleHtml 才會使用專用 HTML adapter。' : error.message);
    process.exitCode = 1;
  }
}
