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

/// Pinned, not an alias like `gemini-flash-latest`.
///
/// Aliases point at whatever is currently in fashion, which is also whatever is
/// currently overloaded — the aliases were returning 503 while this exact model
/// answered immediately. Pinning also means the same photo converts the same
/// way tomorrow.
const DEFAULT_MODEL = 'gemini-3.6-flash';

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
/// 429 is not retried at all. The daily quota does not come back in seconds,
/// and the per-minute one does not come back in the few seconds waited here.
const RETRY_DELAYS_MS = [2000, 5000, 10000, 15000, 20000];
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
  const model = (env?.GEMINI_MODEL ?? '').trim() || DEFAULT_MODEL;

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

  const started = now();
  let response = await post(fetchImpl, model, key, body, timeoutMs);
  for (const delay of retryDelaysMs) {
    if (response.status !== 503) break;
    if (now() - started + delay > lastAttemptStartMs) break;
    await sleep(delay);
    response = await post(fetchImpl, model, key, body, timeoutMs);
  }

  if (!response.ok) {
    // Read whole: the quota that ran out is named ~1000 characters into a 429,
    // past where a log line would be cut. Only the log is truncated.
    const detail = await safeText(response);
    console.error('gemini call failed', model, response.status, detail.slice(0, 500));
    if (response.status === 503) {
      throw new HttpError(503, 'Gemini 免費版現在太多人用，過幾分鐘再試一次');
    }
    if (response.status === 429) throw new HttpError(429, quotaMessage(detail));
    if (response.status === 404) {
      // The operator changed GEMINI_MODEL to something that does not exist, or
      // the pinned one was retired. Nothing the caller can do.
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

/// The free tier allows 20 requests a day per model, and it also has a
/// per-minute limit. "Try again later" is right for the second and wrong for
/// the first: someone pressing the button every few minutes until tomorrow is
/// exactly what that message invites. The 429 body names the quota that ran
/// out, so say which one it was.
function quotaMessage(detail) {
  if (/PerDay/i.test(detail)) {
    return '今天的免費辨識次數用完了，下午三點後再試（或先展開下面自己貼 JSON）';
  }
  return '辨識太頻繁了，等一分鐘再試';
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
