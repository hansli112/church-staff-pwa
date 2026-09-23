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

/// One retry, then give up. 503 on this endpoint is usually a brief spike, but
/// the caller is watching a spinner after already uploading a photo — a long
/// backoff chain is worse than telling them to press the button again.
const RETRY_DELAY_MS = 2000;

const MAX_OUTPUT_TOKENS = 16384;

export async function callGemini(
  env,
  { prompt, images, fetchImpl = fetch, retryDelayMs = RETRY_DELAY_MS, timeoutMs = UPSTREAM_TIMEOUT_MS },
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

  let response = await post(fetchImpl, model, key, body, timeoutMs);
  if (response.status === 503 || response.status === 429) {
    await sleep(retryDelayMs);
    response = await post(fetchImpl, model, key, body, timeoutMs);
  }

  if (!response.ok) {
    const detail = await safeText(response);
    console.error('gemini call failed', model, response.status, detail);
    if (response.status === 503) throw new HttpError(503, '辨識服務忙碌中，請稍後再試一次');
    if (response.status === 429) throw new HttpError(429, '辨識用量已達上限，請稍後再試');
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

async function safeText(response) {
  try {
    return (await response.text()).slice(0, 500);
  } catch {
    return '<unreadable>';
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
