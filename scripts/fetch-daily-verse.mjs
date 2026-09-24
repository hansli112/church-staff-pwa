#!/usr/bin/env node
// JSON feed or the explicitly selected legacy dailyBibleHtml adapter, never a
// generic scraper. Sources and redistribution rights remain the deployer's job.
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { validateChurchConfig } from '../worker/church_config.js';

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

export function parseDailyBibleHtml(html) {
  // Preserves the existing date <span>|</span> <span>range</span> contract.
  // A different source layout needs its own adapter and tests.
  const match = html.match(/(\d{4}-\d{2}-\d{2})\s*<span>\|<\/span>\s*<span>\s*([^<]+?)\s*<\/span>/s);
  if (!match) throw new Error('dailyBibleHtml 找不到既定日期／span 經文格式；請檢查來源版型，不會猜測任意網頁。');
  return { date: match[1], rawRange: match[2].trim() };
}

export function validateDailyVerse(data, { timeZone = 'Asia/Taipei', now = new Date() } = {}) {
  const today = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('來源必須是 JSON object，不是 HTML。');
  if (typeof data.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(data.date)) throw new Error('date 必須是 YYYY-MM-DD。');
  const date = new Date(`${data.date}T00:00:00.000Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== data.date || data.date > today) {
    throw new Error('date 不是有效日期，或晚於部署時區的今天。');
  }
  if (typeof data.rawRange !== 'string' || !data.rawRange.trim() || data.rawRange.length > 120 || /[<>\x00-\x1f\x7f]/.test(data.rawRange)) {
    throw new Error('rawRange 必須是 1–120 字的純文字經文範圍。');
  }
  return { date: data.date, rawRange: data.rawRange.trim(), fetchedAt: now.toISOString() };
}

export async function fetchDailyVerse(url, { fetchImpl = globalThis.fetch, format = 'json', ...options } = {}) {
  if (!['json', 'dailyBibleHtml'].includes(format)) throw new Error('不支援的 fetchFormat。');
  const source = new URL(url);
  if (source.protocol !== 'https:' || source.username || source.password) throw new Error('來源必須是無內嵌帳密的 HTTPS URL。');
  const response = await fetchImpl(source, {
    headers: { Accept: format === 'json' ? 'application/json' : 'text/html' },
    redirect: 'error', signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`靈糧來源回傳 HTTP ${response.status}。`);
  if (!response.body) throw new Error('靈糧來源沒有內容。');
  const chunks = [];
  const maxBytes = format === 'json' ? 65_536 : 2_097_152;
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > maxBytes) throw new Error(`靈糧來源超過 ${maxBytes} bytes。`);
    chunks.push(chunk);
  }
  const text = Buffer.concat(chunks).toString('utf8');
  const data = format === 'json' ? JSON.parse(text) : parseDailyBibleHtml(text);
  return validateDailyVerse(data, options);
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
