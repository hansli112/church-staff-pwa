// Calls Gemini with a prompt and one or more photos, and returns the JSON it
// produced.
//
// Why this runs on the server at all: the API key must not reach the browser.
// A key in the bundle is a key anyone can lift and spend, and this one is
// billed per call. Same reasoning as the calendar service account in
// google_calendar.js.

import { HttpError, requireEnv } from './firebase_user.js';

// v1, not v1beta. The newer models answer v1beta with an empty-bodied 404,
// which reads like "no such model" and sends you hunting for the wrong thing.
const API_BASE = 'https://generativelanguage.googleapis.com/v1';

/// Pinned, not an alias like `gemini-flash-latest`, and tried in this order.
///
/// Aliases point at whatever is currently in fashion, which is also whatever is
/// currently overloaded — the aliases were returning 503 while this exact model
/// answered immediately. Pinning also means the same photo converts the same
/// way tomorrow.
///
/// Two, because on the free tier one model is often busy or out of its daily
/// 20 requests while another is not: on 2026-09-23 3.6 answered 429 and 3.7
/// succeeded a minute later. Each has its own quota, so two models is also
/// twice the requests per day. 3.7 is here because it was measured, not
/// because it is newer: on the 主日 table it matched the 3.6 import in all 117
/// cells. Do not add a model to this list without checking its output
/// against a photo — see the lite models below.
const DEFAULT_MODELS = ['gemini-3.6-flash', 'gemini-3.7-flash'];

/// A dense roster table takes Gemini a while: a real quarter's table measured
/// 52-68s, almost all of it generating ~3300 output tokens (lowering the
/// thinking level did not help). The calendar calls use 10s; 60s was the first
/// guess here and sat right on top of the measured times.
const UPSTREAM_TIMEOUT_MS = 100000;

/// Waits before each retry of a 503, and when to stop starting new attempts.
///
/// On the free tier a 503 ("This model is currently experiencing high demand")
/// is not a rare spike. On 2026-09-23 every flash model answered photo requests
/// with 503 for stretches, while the same model answered a one-line text
/// prompt at once. What got through was patience: the local script, backing
/// off 5s/15s/40s, succeeded where the worker's one quick retry gave up.
///
/// A 503 comes back in 5-40s; a success takes 50-70s. So retries continue
/// while there is still time for one full conversion to finish inside what the
/// app waits (190s, see RosterImportService), and not after.
///
/// Falling back to a lite model was measured and rejected: both lite models
/// answered in 15s and put the wrong person on ~50 duties of one quarter —
/// the kind of error nobody spots before pressing import.
///
/// Retries alternate between the models. A 503 on one says little about the
/// other, and the failed attempt still counts against that model's daily 20
/// (measured: 503s burned 3.6's quota), so spreading them also spreads that.
///
/// 429 is never retried on the same model: the daily quota does not come back
/// in seconds. That model is dropped for the rest of the request and the next
/// one is tried at once.
///
/// Two retries, not five, because every 503 is also one of the day's 40 (20 per
/// model). Five retries let one import during a busy spell spend six of them:
/// on 2026-09-24 two imports like that finished off the day's quota. None of
/// the five-retry chains measured on 2026-09-23 succeeded after the third
/// attempt; the ones that got through did so on the first or third. Three
/// attempts keeps the rescue and caps an import at three of the day's 40.
export const RETRY_DELAYS_MS = [3000, 10000];
const LAST_ATTEMPT_START_MS = 75000;

const MAX_OUTPUT_TOKENS = 16384;

export async function callGemini(
  env,
  {
    prompt,
    images,
    fetchImpl = fetch,
    retryDelaysMs = RETRY_DELAYS_MS,
    lastAttemptStartMs = LAST_ATTEMPT_START_MS,
    timeoutMs = UPSTREAM_TIMEOUT_MS,
    now = Date.now,
  },
) {
  const key = requireEnv(env, 'GEMINI_API_KEY');
  const models = modelList(env);

  const body = {
    contents: [
      {
        parts: [
          { text: prompt },
          ...images.map((image) => ({
            inline_data: { mime_type: image.mimeType, data: image.data },
          })),
        ],
      },
    ],
    generationConfig: {
      // Converting a table to JSON has no room for invention; the same photo
      // should produce the same rows every time.
      temperature: 0,
      // Ask for JSON directly rather than parsing it back out of prose.
      responseMimeType: 'application/json',
      maxOutputTokens: MAX_OUTPUT_TOKENS,
    },
  };

  // A queue, not an index: a model that answered 503 goes to the back, one
  // that cannot answer today (429: out of quota; 404: retired) leaves it. An
  // index modulo the remaining count skips a model once another is dropped.
  const queue = [...models];
  const started = now();
  let retries = 0;
  let model;
  let response;
  // Kept across models: a quota that ran out on one model is still the reason
  // the request failed if the next one then turns out to be retired.
  let quotaDetail = null;
  while (queue.length > 0) {
    model = queue.shift();
    response = await post(fetchImpl, model, key, body, timeoutMs);
    if (response.ok) break;

    if (response.status === 429) {
      quotaDetail = await safeText(response);
      console.error('gemini quota exhausted', model, quotaDetail.slice(0, 500));
    } else if (response.status === 404) {
      // Retired, or a typo in GEMINI_MODEL. The other model may be fine.
      console.error('gemini model not found', model);
    } else if (response.status === 503) {
      console.error('gemini busy', model, `retry ${retries}`);
      queue.push(model);
    } else {
      break;
    }
    if (queue.length === 0) break;

    // A model that cannot answer today is replaced at once; a busy one waits.
    const delay = response.status === 503 ? retryDelaysMs[retries] : 0;
    if (delay === undefined || now() - started + delay > lastAttemptStartMs) break;
    if (response.status === 503) {
      retries += 1;
      await sleep(delay);
    }
  }

  if (response.ok) {
    console.log('gemini ok', model, `retries ${retries}`);
  } else {
    // Read whole: the quota that ran out is named ~1000 characters into a 429,
    // past where a log line would be cut. Only the log is truncated.
    const detail = response.status === 429 ? quotaDetail : await safeText(response);
    console.error('gemini call failed', model, response.status, detail.slice(0, 500));
    // Busy is checked first: it is the only one of these that goes away by
    // itself within minutes, so it is the most useful thing to say.
    if (response.status === 503) {
      throw new HttpError(503, 'Gemini 免費版現在太多人用，過幾分鐘再試一次');
    }
    if (quotaDetail !== null) throw new HttpError(429, quotaMessage(quotaDetail, now()));
    if (response.status === 404) {
      // No model answered, and at least the last one does not exist — a typo in
      // GEMINI_MODEL or a retired model. Nothing the caller can do.
      throw new HttpError(500, '辨識服務設定有誤，請聯絡管理員');
    }
    throw new HttpError(502, '辨識失敗，請稍後再試');
  }

  return extractJson(await response.json());
}

/// Pulls the model's JSON out of a generateContent response.
///
/// Exported for the tests: every branch here is a shape that has actually come
/// back from the API, and they are cheaper to cover directly than through a
/// faked HTTP round trip.
export function extractJson(payload) {
  const candidate = payload?.candidates?.[0];
  if (!candidate) {
    // Blocked by a safety filter, or the whole request was refused. The prompt
    // feedback says which, and it is the operator who needs to see it.
    console.error('gemini returned no candidates', JSON.stringify(payload?.promptFeedback));
    throw new HttpError(502, '辨識沒有產生結果，請換一張照片再試');
  }

  const text = (candidate.content?.parts ?? [])
    .map((part) => part?.text ?? '')
    .join('')
    .trim();

  if (text === '') {
    const reason = candidate.finishReason ?? 'unknown';
    console.error('gemini returned empty text', reason);
    if (reason === 'MAX_TOKENS') {
      throw new HttpError(502, '服事表太大，請把照片裁成上下兩半，分兩次辨識');
    }
    throw new HttpError(502, '辨識沒有產生結果，請換一張照片再試');
  }

  let parsed;
  try {
    parsed = JSON.parse(stripFence(text));
  } catch {
    // responseMimeType should prevent this, but a truncated response parses as
    // nothing and the caller deserves better than a raw SyntaxError.
    console.error('gemini returned unparseable text', text.slice(0, 300));
    throw new HttpError(502, '辨識結果不是有效的資料，請再試一次');
  }

  if (!Array.isArray(parsed)) {
    console.error('gemini returned a non-array', typeof parsed);
    throw new HttpError(502, '辨識結果格式不對，請再試一次');
  }
  return parsed;
}

/// The prompt forbids code fences, but models add them anyway often enough that
/// failing the whole conversion over one is not worth it.
function stripFence(text) {
  const fenced = /^```(?:json)?\s*\n([\s\S]*?)\n```$/.exec(text);
  return fenced ? fenced[1].trim() : text;
}

async function post(fetchImpl, model, key, body, timeoutMs) {
  const url = `${API_BASE}/models/${encodeURIComponent(model)}:generateContent`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchImpl(url, {
      method: 'POST',
      // The key goes in a header, not the query string: query strings land in
      // proxy and server access logs, headers do not.
      headers: {
        'X-goog-api-key': key,
        'content-type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof HttpError) throw error;
    if (controller.signal.aborted) {
      // Our own timeout, not a network failure: "cannot connect" would send
      // the caller checking their Wi-Fi when the fix is a smaller photo.
      console.error('gemini request timed out', model, timeoutMs);
      throw new HttpError(504, '辨識太久了，請把照片裁到只剩表格再試');
    }
    console.error('gemini request failed', error);
    throw new HttpError(502, '無法連上辨識服務，請稍後再試');
  } finally {
    clearTimeout(timer);
  }
}

/// GEMINI_MODEL overrides the list, comma-separated and in order. Only for when
/// Google retires a model: see DEFAULT_MODELS for why a replacement has to be
/// checked against a photo first.
function modelList(env) {
  const configured = (env?.GEMINI_MODEL ?? '')
    .split(',')
    .map((name) => name.trim())
    .filter((name) => name !== '');
  return configured.length > 0 ? configured : DEFAULT_MODELS;
}

/// The free tier allows 20 requests a day per model, and it also has a
/// per-minute limit. "Try again later" is right for the second and wrong for
/// the first: someone pressing the button every few minutes until tomorrow is
/// exactly what that message invites. The 429 body names the quota that ran
/// out, so say which one it was.
function quotaMessage(detail, nowMs) {
  if (/PerDay/i.test(detail)) {
    return `今天的免費辨識次數用完了，${quotaResetText(nowMs)}後再試（或先展開下面自己貼 JSON）`;
  }
  return '辨識太頻繁了，等一分鐘再試';
}

const PACIFIC_HOUR = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/Los_Angeles',
  hour: 'numeric',
  hourCycle: 'h23',
});

/// When the daily quota comes back, in the words a Taiwanese user reads.
///
/// The free tier resets at midnight Pacific time. That is 15:00 in Taiwan while
/// the US is on daylight saving time and 16:00 after it ends (early November),
/// so a fixed "下午三點" is wrong for five months a year. Taiwan has no DST, so
/// the reset is always 07:00 or 08:00 UTC: find the next of those instants that
/// is midnight in Los Angeles.
///
/// Exported for the tests, which pin both sides of the DST switch.
export function quotaResetText(nowMs) {
  const TAIPEI_OFFSET_MS = 8 * 3600 * 1000;
  const today = new Date(nowMs);
  for (let day = 0; day < 3; day += 1) {
    for (const utcHour of [7, 8]) {
      const reset = Date.UTC(
        today.getUTCFullYear(),
        today.getUTCMonth(),
        today.getUTCDate() + day,
        utcHour,
      );
      if (reset <= nowMs || Number(PACIFIC_HOUR.format(reset)) !== 0) continue;
      const taipeiDay = (ms) => Math.floor((ms + TAIPEI_OFFSET_MS) / 86400000);
      const when = taipeiDay(reset) === taipeiDay(nowMs) ? '' : '明天';
      return `${when}下午${utcHour === 7 ? '三' : '四'}點`;
    }
  }
  // Unreachable while Los Angeles keeps a UTC-7/-8 offset.
  return '明天';
}

async function safeText(response) {
  try {
    return await response.text();
  } catch {
    return '<unreadable>';
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
