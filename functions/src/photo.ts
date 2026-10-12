import { FieldValue } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { dateKeyUtc8, fail, type Caller, type Deps } from './common.js';
import { LANGUAGES, words } from './languages.js';
import { LIMITS } from './limits.js';
import { dateKeyIn, timeZoneOf, type ChurchTimeZone } from './timeZones.js';

/**
 * 照片辨識: a roster editor sends photos of a paper roster; Gemini on Vertex
 * AI (which does not train on the photos) turns them into the JSON
 * the app's import parser reads. Nothing is stored: the photos only pass
 * through. Identity confirmation and format errors stay in the app's
 * shared editable import preview.
 *
 * Limits: PHOTOS_PER_MONTH per church; the whole platform stops for the
 * month once the estimated spend reaches MONTHLY_BUDGET_USD.
 */
export const PHOTOS_PER_MONTH = LIMITS.photosPerMonth;
export const MONTHLY_BUDGET_USD = 20;
export const MAX_IMAGES = 3;
export const MAX_IMAGE_BYTES = LIMITS.photoBytes;
const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic']);

/** Pinned models, tried in order (self-host measured these on real sheets). */
export const DEFAULT_MODELS = ['gemini-3.6-flash', 'gemini-3.7-flash'];

/** GEMINI_MODELS, comma separated, or [DEFAULT_MODELS] when it names none. */
export function geminiModels(env: string | undefined): string[] {
  const models = (env ?? '').split(',').map((m) => m.trim()).filter(Boolean);
  return models.length ? models : DEFAULT_MODELS;
}

/** Estimate only: USD per million tokens, flash, 2026-10. */
const PRICE_PER_M = { input: 0.3, output: 2.5 };

export interface GeminiImage {
  mimeType: string;
  data: string;
}

/** Calls Gemini; returns the parsed JSON array and the tokens it used. */
export type Gemini = (
  prompt: string,
  images: GeminiImage[],
) => Promise<{ rows: unknown[]; inputTokens: number; outputTokens: number }>;

/** A church's photos are counted by its own months; the platform's budget by UTC+8's. */
const monthKey = (d: Date, timeZone: ChurchTimeZone) => dateKeyIn(timeZone, d).slice(0, 7);
const platformMonth = (d: Date) => dateKeyUtc8(d).slice(0, 7);

/** How many photos the church has left this month, and whether the platform is on. */
export async function photoQuota(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid, church } = await churchAccess(deps, caller, data, 'member');
  const [usage, budget] = await Promise.all([
    deps.db.doc(`churches/${cid}/usage/${monthKey(deps.now(), timeZoneOf(church))}`).get(),
    deps.db.doc(`platform/photoBudget_${platformMonth(deps.now())}`).get(),
  ]);
  const used = (usage.get('photos') as number | undefined) ?? 0;
  return {
    remaining: Math.max(0, PHOTOS_PER_MONTH - used),
    limit: PHOTOS_PER_MONTH,
    platformOpen: ((budget.get('costUsd') as number | undefined) ?? 0) < MONTHLY_BUDGET_USD,
  };
}

interface Service {
  id: string;
  name: string;
  duties?: string[];
  events?: { name: string; color: number }[];
}

/** The prompt, built from the church's live settings on every call. */
export function buildPrompt(opts: { service: Service; names: string[]; today: string }) {
  const { service, names, today } = opts;
  const roles = (service.duties ?? []).map((d) => `- ${d}`).join('\n');
  const events = JSON.stringify(service.events ?? []);
  return [
    `把「${service.name}」的服事表照片轉成 JSON。只輸出 JSON 陣列，不加 Markdown 或說明文字。`,
    '照原文辨識，不要翻譯：英文、日文、韓文或其他語言的服事表，服事項目、人名、活動都照照片上的文字輸出。',
    '## 只要這些',
    '日期、服事項目、人名、活動。其他不要輸出。逐格讀取，不要漏掉看得見的服事項目或人名。',
    '## 服事項目',
    '教會目前的服事項目（參考，不是白名單）：',
    roles,
    '照片上其他服事項目也照原文輸出，不要略過、不自行改名。',
    '## 人名',
    '照照片原文抄寫。不要還原簡稱、稱謂、錯字，不憑相似字形選同工，不猜身分。確認身分由匯入預覽處理。',
    '以下同工名單僅供辨識已寫完整的人名，不能拿來補字或替換：',
    names.join('、'),
    '一格有多人（/ 或 + 分隔）拆成多個字串，保留照片先後順序。',
    `空白或${[...new Set(LANGUAGES.map((l) => words(l).placeholder))].map((p) => `「${p}」`).join('')}填 "people": []；「暫停」的服事項目不輸出。`,
    '## 活動',
    'events 每個元素固定是 {"name":"活動名稱","color":0}，color 是 0 到 5 的整數色票編號，不是 RGB 或 ARGB。',
    `教會常用活動：${events}。名稱完全相同時使用該 color；其他活動照原文抄，color 填 4。`,
    '沒有活動時可省略 events。',
    '## 格式',
    '[{"date":"2026-07-04","duties":[{"role":"司會","people":["陳小明"]}],"events":[{"name":"聖餐","color":0}]}]',
    `date 一定是 YYYY-MM-DD。標題沒寫年份時，今天是 ${today}，選照片月份離今天最近的年份。`,
    '每列必須有 date 和 duties 陣列；同一天只出現一次；不輸出其他欄位。',
  ].join('\n');
}

function parseImages(raw: unknown): GeminiImage[] {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > MAX_IMAGES) fail('invalid-argument', 'unknown');
  return raw.map((image: { mimeType?: unknown; data?: unknown }) => {
    if (typeof image?.mimeType !== 'string' || !IMAGE_TYPES.has(image.mimeType)) fail('invalid-argument', 'unknown');
    if (typeof image.data !== 'string' || (image.data.length * 3) / 4 > MAX_IMAGE_BYTES) {
      fail('invalid-argument', 'unknown', 'tooLarge');
    }
    return { mimeType: image.mimeType, data: image.data };
  });
}

export async function recognizeRoster(deps: Deps & { gemini: Gemini }, caller: Caller | null, data: unknown) {
  const input = data as { serviceType?: unknown; images?: unknown };
  const type = input?.serviceType;
  if (typeof type !== 'string') fail('invalid-argument', 'unknown');
  const { cid, church } = await churchAccess(deps, caller, data, { rosterEditor: type });
  const timeZone = timeZoneOf(church);
  const images = parseImages(input.images);
  const { db } = deps;
  const usageRef = db.doc(`churches/${cid}/usage/${monthKey(deps.now(), timeZone)}`);
  const budgetRef = db.doc(`platform/photoBudget_${platformMonth(deps.now())}`);

  // Reserve one photo before calling, so two editors at once cannot both
  // take the last one. Refunded if Gemini fails.
  await db.runTransaction(async (tx) => {
    const [usage, budget] = await Promise.all([tx.get(usageRef), tx.get(budgetRef)]);
    if (((budget.get('costUsd') as number | undefined) ?? 0) >= MONTHLY_BUDGET_USD) {
      fail('resource-exhausted', 'quotaExceeded', 'platform');
    }
    if (((usage.get('photos') as number | undefined) ?? 0) >= PHOTOS_PER_MONTH) {
      fail('resource-exhausted', 'quotaExceeded', 'church');
    }
    tx.set(usageRef, { photos: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });

  try {
    const [settings, members] = await Promise.all([
      db.doc(`churches/${cid}/settings/services`).get(),
      db.collection(`churches/${cid}/members`).select('name').get(),
    ]);
    const service = ((settings.get('services') as Service[] | undefined) ?? []).find((s) => s.id === type);
    if (!service) fail('failed-precondition', 'unknown');
    const prompt = buildPrompt({
      service,
      names: members.docs.map((m) => m.get('name') as string).filter(Boolean),
      today: dateKeyIn(timeZone, deps.now()),
    });
    const result = await deps.gemini(prompt, images);
    const cost = (result.inputTokens * PRICE_PER_M.input + result.outputTokens * PRICE_PER_M.output) / 1e6;
    await budgetRef.set(
      { costUsd: FieldValue.increment(cost), calls: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    const usage = await usageRef.get();
    return { rows: result.rows, remaining: Math.max(0, PHOTOS_PER_MONTH - ((usage.get('photos') as number) ?? 0)) };
  } catch (e) {
    await usageRef.set({ photos: FieldValue.increment(-1) }, { merge: true });
    throw e;
  }
}

const RETRY_DELAYS_MS = [3000, 10000];

/** Where Gemini runs and how to sign the call: the Functions service account. */
export interface VertexConfig {
  project: string;
  accessToken: () => Promise<string>;
}

/**
 * The real Gemini call, through Vertex AI, with 503 retries and model
 * fallback (from self-host). Vertex bills the project's Cloud Billing
 * account; the Gemini API in AI Studio has its own prepaid credit, which the
 * Cloud free trial does not cover.
 */
export function geminiClient(vertex: VertexConfig, models: string[] = DEFAULT_MODELS): Gemini {
  const base = `https://aiplatform.googleapis.com/v1/projects/${vertex.project}/locations/global/publishers/google/models`;
  return async (prompt, images) => {
    const body = JSON.stringify({
      contents: [
        {
          role: 'user',
          parts: [{ text: prompt }, ...images.map((i) => ({ inlineData: { mimeType: i.mimeType, data: i.data } }))],
        },
      ],
      generationConfig: {
        temperature: 0,
        responseMimeType: 'application/json',
        maxOutputTokens: 16384,
        responseSchema: {
          type: 'ARRAY',
          items: {
            type: 'OBJECT', required: ['date', 'duties'],
            properties: {
              date: { type: 'STRING', description: 'YYYY-MM-DD' },
              duties: {
                type: 'ARRAY', items: {
                  type: 'OBJECT', required: ['role', 'people'],
                  properties: { role: { type: 'STRING' }, people: { type: 'ARRAY', items: { type: 'STRING' } } },
                },
              },
              events: {
                type: 'ARRAY', items: {
                  type: 'OBJECT', required: ['name', 'color'],
                  properties: { name: { type: 'STRING' }, color: { type: 'INTEGER', minimum: 0, maximum: 5 } },
                },
              },
            },
          },
        },
      },
    });
    const queue = [...models];
    let retries = 0;
    let last: Response | undefined;
    while (queue.length > 0) {
      const model = queue.shift()!;
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 100_000);
      try {
        last = await fetch(`${base}/${encodeURIComponent(model)}:generateContent`, {
          method: 'POST',
          headers: { authorization: `Bearer ${await vertex.accessToken()}`, 'content-type': 'application/json' },
          body,
          signal: controller.signal,
        });
      } catch {
        fail('unavailable', 'unavailable');
      } finally {
        clearTimeout(timer);
      }
      if (last.ok) break;
      if (last.status === 503) {
        const delay = RETRY_DELAYS_MS[retries++];
        if (delay === undefined) break;
        queue.push(model);
        await new Promise((r) => setTimeout(r, delay));
      } else if (last.status !== 429 && last.status !== 404) {
        break;
      }
    }
    if (!last?.ok) {
      // The reason (no permission, API off, model gone) is only in the answer.
      const detail = last ? (await last.text().catch(() => '')).slice(0, 500) : '';
      console.warn('gemini refused', last?.status, detail);
      fail('unavailable', 'unavailable');
    }
    const payload = (await last.json()) as {
      candidates?: { content?: { parts?: { text?: string }[] } }[];
      usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
    };
    const text = (payload.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? '').join('').trim();
    let rows: unknown;
    try {
      rows = JSON.parse(text);
    } catch {
      fail('internal', 'unknown', 'unparseable');
    }
    if (!Array.isArray(rows)) fail('internal', 'unknown', 'unparseable');
    return {
      rows,
      inputTokens: payload.usageMetadata?.promptTokenCount ?? 0,
      outputTokens: payload.usageMetadata?.candidatesTokenCount ?? 0,
    };
  };
}
