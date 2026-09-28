// Daily devotional passage: a JSON feed or the explicitly selected legacy
// dailyBibleHtml adapter, never a generic scraper. Shared by the scheduled
// GitHub workflow (Node) and the /api/devotional/today fallback (Workers), so
// both accept exactly the same sources. Redistribution rights remain the
// deployer's job.

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
  // Web streams rather than Node Buffers: the same code runs in Workers.
  const maxBytes = format === 'json' ? 65_536 : 2_097_152;
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let size = 0;
  let text = '';
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      await reader.cancel();
      throw new Error(`靈糧來源超過 ${maxBytes} bytes。`);
    }
    text += decoder.decode(value, { stream: true });
  }
  text += decoder.decode();
  const data = format === 'json' ? JSON.parse(text) : parseDailyBibleHtml(text);
  return validateDailyVerse(data, options);
}
