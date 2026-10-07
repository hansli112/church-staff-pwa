import { FieldValue } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { dateKeyUtc8, fail, type Caller, type Deps } from './common.js';

/**
 * 照片辨識: a roster editor sends photos of a paper roster; Gemini on Vertex
 * AI (which does not train on the photos) turns them into the JSON
 * the app's import parser reads. Nothing is stored: the photos only pass
 * through. Name matching and the import report stay in the app, the same
 * as self-host.
 *
 * Limits: PHOTOS_PER_MONTH per church; the whole platform stops for the
 * month once the estimated spend reaches MONTHLY_BUDGET_USD.
 */
export const PHOTOS_PER_MONTH = 30;
export const MONTHLY_BUDGET_USD = 20;
export const MAX_IMAGES = 3;
export const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic']);

/** Pinned models, tried in order (self-host measured these on real sheets). */
export const DEFAULT_MODELS = ['gemini-3.6-flash', 'gemini-3.7-flash'];

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

const monthKey = (d: Date) => dateKeyUtc8(d).slice(0, 7);

/** How many photos the church has left this month, and whether the platform is on. */
export async function photoQuota(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid } = await churchAccess(deps, caller, data, 'member');
  const month = monthKey(deps.now());
  const [usage, budget] = await Promise.all([
    deps.db.doc(`churches/${cid}/usage/${month}`).get(),
    deps.db.doc(`platform/photoBudget_${month}`).get(),
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
  events?: { name: string }[];
}

/** The prompt, built from the church's live settings on every call. */
export function buildPrompt(opts: {
  service: Service;
  names: string[];
  today: string;
  rules?: { layoutRules?: string; extraRoleRules?: string; nicknames?: Record<string, string> };
}) {
  const { service, names, today, rules } = opts;
  const roles = (service.duties ?? []).map((d) => `- ${d}`).join('\n');
  const events = (service.events ?? []).map((e) => `「${e.name}」`).join('、') || '（無）';
  const nicknames = Object.entries(rules?.nicknames ?? {})
    .map(([nick, full]) => `- 「${nick}」是「${full}」`)
    .join('\n');
  return [
    `幫我把「${service.name}」的服事表照片轉成 JSON。只輸出 JSON，第一個字元是 [，最後一個字元是 ]，不要有任何說明文字。`,
    '',
    '## 只要這些',
    '日期、服事項目、同工、活動。其他一律不要。',
    rules?.layoutRules ?? '',
    '## 服事項目命名',
    '只能用以下名稱，一字不差：',
    roles,
    '清單裡沒有的欄位整欄不要輸出。',
    rules?.extraRoleRules ?? '',
    '## 人名',
    '輸出的人名必須是下面同工名單裡的其中一個全名，一字不差。表格上寫的是簡稱（去掉姓氏）或加了稱謂（哥、姐、牧師、傳道…），要還原成名單裡的全名。',
    '同工名單：',
    names.join('、'),
    '- 罕用字容易認錯：不要自己拼字，從名單裡挑字形最接近的那一個。',
    '- 一格有多個人（用「/」或「+」分隔）就拆成多個元素；照表格上的先後順序，不要重排。',
    '- 空白格 → "people": ["待定"]。「暫停」代表那週沒有這一項，整個項目不要輸出。',
    '- 真的對不到名單裡任何一位，就照表格原文輸出。',
    nicknames,
    '## 活動',
    `放進該天的 events。意思相同時優先用這些名稱：${events}。對不到就照原文抄，不要拆。不要輸出顏色。沒有活動就不要寫 events。`,
    '## 格式',
    '[{"date":"2026-07-04","duties":[{"role":"司會","people":["陳小明"]}],"events":["聖餐"]}]',
    `- date 一定是 YYYY-MM-DD。標題沒寫年份時，今天是 ${today}，挑讓表上月份離今天最近的年份。`,
    '- people 的每個元素都是字串；duties 不可以是空陣列；同一個日期只出現一次。',
  ]
    .filter((line) => line !== '')
    .join('\n');
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
  const { cid } = await churchAccess(deps, caller, data, { rosterEditor: type });
  const images = parseImages(input.images);
  const { db } = deps;
  const month = monthKey(deps.now());
  const usageRef = db.doc(`churches/${cid}/usage/${month}`);
  const budgetRef = db.doc(`platform/photoBudget_${month}`);

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
    const [settings, members, rules] = await Promise.all([
      db.doc(`churches/${cid}/settings/services`).get(),
      db.collection(`churches/${cid}/members`).select('name').get(),
      db.doc(`churches/${cid}/settings/import_rules`).get(),
    ]);
    const service = ((settings.get('services') as Service[] | undefined) ?? []).find((s) => s.id === type);
    if (!service) fail('failed-precondition', 'unknown');
    const prompt = buildPrompt({
      service,
      names: members.docs.map((m) => m.get('name') as string).filter(Boolean),
      today: dateKeyUtc8(deps.now()),
      rules: rules.get(type) as Parameters<typeof buildPrompt>[0]['rules'],
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
      generationConfig: { temperature: 0, responseMimeType: 'application/json', maxOutputTokens: 16384 },
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
    const fenced = /^```(?:json)?\s*\n([\s\S]*?)\n```$/.exec(text);
    let rows: unknown;
    try {
      rows = JSON.parse(fenced ? fenced[1] : text);
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
