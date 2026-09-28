// GET /api/devotional/today — same-day fallback for the devotional passage.
//
// The scheduled workflow commits daily-verse.json to the data branch, but
// GitHub runs schedules hours late (03:30–04:15 Taipei instead of 01:00), so
// every night the home page had no passage until then. When the data branch is
// still on an earlier day, the app asks here instead. Only the configured
// source is read, with the same adapter as the workflow.
//
// Signed-in members only, and cached per day at the edge, so the site cannot
// be used to hammer the source.

import { churchConfig, dateKeyInZone } from '../../../worker/church_config.js';
import { fetchDailyVerse } from '../../../worker/devotional.js';
import { HttpError, identifyCaller } from '../../../worker/firebase_user.js';
import { handleWith } from '../../../worker/http.js';

const LOG_LABEL = 'devotional function failed';

function verseResponse(body, cacheControl) {
  return new Response(body, {
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': cacheControl },
  });
}

export const onRequestGet = ({ request, env, waitUntil }) =>
  handleWith(LOG_LABEL, async () => {
    const { devotional, timeZone } = churchConfig(env);
    if (!devotional.enabled || !devotional.fetchUrl) throw new HttpError(404, '此教會未啟用每日靈糧來源');
    await identifyCaller(request, env);

    const now = new Date();
    const today = dateKeyInZone(now, timeZone);
    // Keyed by the church's date, so yesterday's copy can never be served today.
    const cacheKey = new Request(new URL(`/api/devotional/today?d=${today}`, request.url));
    const cache = globalThis.caches?.default;
    const cached = await cache?.match(cacheKey).catch(() => undefined);
    if (cached) return verseResponse(await cached.text(), 'private, max-age=3600');

    let verse;
    try {
      verse = await fetchDailyVerse(devotional.fetchUrl, { format: devotional.fetchFormat ?? 'json', timeZone, now });
    } catch (error) {
      console.error('devotional source failed', error.message);
      throw new HttpError(502, '暫時無法讀取今日經文');
    }
    // The source itself may still be on yesterday; say so rather than cache it.
    if (verse.date !== today) throw new HttpError(404, '來源尚未更新今日經文');

    const body = JSON.stringify({ date: verse.date, rawRange: verse.rawRange });
    if (cache) {
      const stored = cache.put(cacheKey, verseResponse(body, 'public, max-age=86400')).catch(() => {});
      if (waitUntil) waitUntil(stored); else await stored;
    }
    return verseResponse(body, 'private, max-age=3600');
  });
