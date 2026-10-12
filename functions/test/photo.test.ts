import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { buildPrompt, DEFAULT_MODELS, geminiClient, geminiModels, photoQuota, PHOTOS_PER_MONTH, recognizeRoster, type Gemini } from '../src/photo.js';
import { LANGUAGES, words } from '../src/languages.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch, setNow } from './support.js';

const image = { mimeType: 'image/jpeg', data: Buffer.from('jpeg').toString('base64') };
const ok: Gemini = async () => ({ rows: [{ date: '2026-10-04', duties: [] }], inputTokens: 2000, outputTokens: 3000 });

async function church() {
  await seedChurch('C1', { pastor: 'admin', editor: 'staff', staff: 'staff' });
  await seedChurch('C2', { other: 'admin' });
  await db.doc('churches/C1/members/editor').update({ groups: ['roster-editors'], zoneTypes: ['sunday'] });
  await db.doc('churches/C1/settings/services').set({
    services: [{ id: 'sunday', name: '主日崇拜', duties: ['司會', '司琴'], events: [{ name: '聖餐', color: 0 }] }],
    ids: ['sunday'],
  });
}

describe('recognizeRoster', () => {
  beforeEach(clearFirestore);
  test('an editor of the service gets rows back and one photo is counted', async () => {
    await church();
    let prompt = '';
    const gemini: Gemini = async (p) => {
      prompt = p;
      return ok(p, []);
    };
    const r = await recognizeRoster({ ...deps, gemini }, caller('editor'), {
      churchId: 'C1',
      serviceType: 'sunday',
      images: [image],
    });
    assert.equal(r.rows.length, 1);
    assert.equal(r.remaining, PHOTOS_PER_MONTH - 1);
    assert.match(prompt, /- 司會\n- 司琴/);
    for (const n of ['pastor', 'editor', 'staff']) assert.ok(prompt.includes(n), n);
    const budget = await db.doc('platform/photoBudget_2026-10').get();
    assert.ok(budget.get('costUsd') > 0);
  });

  test('staff, editors of other services and other churches are refused', async () => {
    await church();
    const call = (uid: string, type = 'sunday', cid = 'C1') =>
      recognizeRoster({ ...deps, gemini: ok }, caller(uid), { churchId: cid, serviceType: type, images: [image] });
    await rejectsWith(call('staff'), 'permissionDenied');
    await rejectsWith(call('editor', 'youth'), 'permissionDenied');
    await rejectsWith(call('other'), 'permissionDenied');
  });

  test('nobody, admins neither, recognizes for a service the church never had', async () => {
    await church();
    await db.doc('churches/C1/members/editor').update({ zoneTypes: ['sunday', 'youth'] });
    const call = (uid: string) =>
      recognizeRoster({ ...deps, gemini: ok }, caller(uid), { churchId: 'C1', serviceType: 'youth', images: [image] });
    await rejectsWith(call('pastor'), 'permissionDenied');
    await rejectsWith(call('editor'), 'permissionDenied');
    assert.equal((await db.doc('churches/C1/usage/2026-10').get()).exists, false, 'no photo counted');
  });

  test('a closed church recognizes nothing', async () => {
    await church();
    await db.doc('churches/C1').update({ status: 'suspended' });
    await rejectsWith(
      recognizeRoster({ ...deps, gemini: ok }, caller('editor'), { churchId: 'C1', serviceType: 'sunday', images: [image] }),
      'churchClosed',
    );
  });

  test('the church limit and the platform budget stop it with a reason', async () => {
    await church();
    await db.doc('churches/C1/usage/2026-10').set({ photos: PHOTOS_PER_MONTH });
    const err = await rejectsWith(
      recognizeRoster({ ...deps, gemini: ok }, caller('pastor'), { churchId: 'C1', serviceType: 'sunday', images: [image] }),
      'quotaExceeded',
    );
    assert.equal((err as { details: { detail: string } }).details.detail, 'church');

    await db.doc('churches/C1/usage/2026-10').set({ photos: 0 });
    await db.doc('platform/photoBudget_2026-10').set({ costUsd: 20 });
    const err2 = await rejectsWith(
      recognizeRoster({ ...deps, gemini: ok }, caller('pastor'), { churchId: 'C1', serviceType: 'sunday', images: [image] }),
      'quotaExceeded',
    );
    assert.equal((err2 as { details: { detail: string } }).details.detail, 'platform');
  });

  test('a failed recognition gives the photo back', async () => {
    await church();
    const broken: Gemini = async () => {
      throw new Error('boom');
    };
    await assert.rejects(
      recognizeRoster({ ...deps, gemini: broken }, caller('pastor'), { churchId: 'C1', serviceType: 'sunday', images: [image] }),
    );
    const q = await photoQuota(deps, caller('pastor'), { churchId: 'C1' });
    assert.equal(q.remaining, PHOTOS_PER_MONTH);
  });

  test('rejects too many or too large images', async () => {
    await church();
    const big = { mimeType: 'image/jpeg', data: 'A'.repeat(3 * 1024 * 1024) };
    await rejectsWith(
      recognizeRoster({ ...deps, gemini: ok }, caller('pastor'), { churchId: 'C1', serviceType: 'sunday', images: [big] }),
      'unknown',
    );
    await rejectsWith(
      recognizeRoster({ ...deps, gemini: ok }, caller('pastor'), {
        churchId: 'C1',
        serviceType: 'sunday',
        images: [image, image, image, image],
      }),
      'unknown',
    );
  });
});

describe("a church's own month and day", () => {
  beforeEach(clearFirestore);
  test('a photo on 31 October in Los Angeles counts for October there, whatever the date in Taipei', async () => {
    await church();
    await db.doc('churches/C1').update({ timeZone: 'America/Los_Angeles' });
    setNow(new Date('2026-11-01T02:00:00+08:00'));
    let prompt = '';
    const gemini: Gemini = async (p) => {
      prompt = p;
      return ok(p, []);
    };
    await recognizeRoster({ ...deps, gemini }, caller('editor'), { churchId: 'C1', serviceType: 'sunday', images: [image] });
    assert.equal((await db.doc('churches/C1/usage/2026-10').get()).get('photos'), 1);
    assert.match(prompt, /今天是 2026-10-31/);
    assert.equal((await photoQuota(deps, caller('staff'), { churchId: 'C1' })).remaining, PHOTOS_PER_MONTH - 1);
    // The platform's budget goes by its own month.
    assert.ok((await db.doc('platform/photoBudget_2026-11').get()).exists);
    setNow(new Date('2026-10-01T10:00:00+08:00'));
  });
});

describe('photoQuota', () => {
  beforeEach(clearFirestore);
  test('members see remaining photos; outsiders are refused', async () => {
    await church();
    await db.doc('churches/C1/usage/2026-10').set({ photos: 7 });
    const q = await photoQuota(deps, caller('staff'), { churchId: 'C1' });
    assert.deepEqual(q, { remaining: PHOTOS_PER_MONTH - 7, limit: PHOTOS_PER_MONTH, platformOpen: true });
    await rejectsWith(photoQuota(deps, caller('other'), { churchId: 'C1' }), 'permissionDenied');
  });

  test('a closed church has no quota to show', async () => {
    await church();
    for (const status of ['suspended', 'deleted']) {
      await db.doc('churches/C1').update({ status });
      await rejectsWith(photoQuota(deps, caller('staff'), { churchId: 'C1' }), 'churchClosed');
    }
  });
});

describe('buildPrompt', () => {
  test('uses canonical palette events and transcribes names without guessing an identity', () => {
    const p = buildPrompt({
      service: { id: 'sunday', name: '主日', duties: ['司會'] },
      names: ['陳小明'], today: '2026-10-02',
    });
    assert.match(p, /"events":\[\{"name":"聖餐","color":0\}\]/);
    assert.match(p, /不要還原簡稱/);
    assert.doesNotMatch(p, /字形最接近|整欄不要輸出/);
    assert.match(p, /今天是 2026-10-02/);
  });

  test('an English (or Japanese, or Korean) roster is read as written, not translated into Chinese', () => {
    const p = buildPrompt({ service: { id: 'sunday', name: 'Sunday Service', duties: ['Piano'] }, names: ['Amy'], today: '2026-10-02' });
    assert.match(p, /照原文辨識，不要翻譯/);
    const empty = /空白或(.*)填 "people": \[\]/.exec(p)?.[1] ?? '';
    for (const language of LANGUAGES) {
      assert.equal(empty.split(`「${words(language).placeholder}」`).length, 2, `${language}'s, once`);
    }
  });
});

describe('geminiClient', () => {
  const vertex = { project: 'p1', accessToken: async () => 'SECRET-TOKEN-123' };

  test('calls Gemini on Vertex AI in the project, signed with the service account', async (t) => {
    const fetch = t.mock.method(globalThis, 'fetch', async () =>
      Response.json({
        candidates: [{ content: { parts: [{ text: '[]' }] } }],
        usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 2 },
      }),
    );
    const r = await geminiClient(vertex, ['gemini-x'])('prompt', [image]);
    assert.deepEqual(r, { rows: [], inputTokens: 10, outputTokens: 2 });
    const [url, init] = fetch.mock.calls[0].arguments as [string, RequestInit];
    assert.equal(
      url,
      'https://aiplatform.googleapis.com/v1/projects/p1/locations/global/publishers/google/models/gemini-x:generateContent',
    );
    assert.equal((init.headers as Record<string, string>).authorization, 'Bearer SECRET-TOKEN-123');
  });

  test('requests the same typed photo and pasted JSON event contract', async (t) => {
    const fetch = t.mock.method(globalThis, 'fetch', async () => Response.json({
      candidates: [{ content: { parts: [{ text: '[{"date":"2026-10-18","duties":[],"events":[{"name":"聖餐","color":5}]}]' }] } }],
    }));
    const result = await geminiClient(vertex, ['gemini-x'])('prompt', [image]);
    assert.deepEqual(result.rows, [{date: '2026-10-18', duties: [], events: [{name: '聖餐', color: 5}]}]);
    const request = JSON.parse((fetch.mock.calls[0].arguments[1] as RequestInit).body as string);
    const event = request.generationConfig.responseSchema.items.properties.events.items;
    assert.deepEqual(event.required, ['name', 'color']);
    assert.equal(event.properties.color.type, 'INTEGER');
    assert.equal(event.properties.color.minimum, 0);
    assert.equal(event.properties.color.maximum, 5);
  });

  test('non-canonical fenced output fails explicitly instead of being silently downgraded', async (t) => {
    t.mock.method(globalThis, 'fetch', async () => Response.json({
      candidates: [{ content: { parts: [{ text: '```json\n[]\n```' }] } }],
    }));
    await rejectsWith(geminiClient(vertex, ['gemini-x'])('prompt', [image]), 'unknown');
  });

  test('a refused call says unavailable and logs why', async (t) => {
    t.mock.method(globalThis, 'fetch', async () =>
      Response.json({ error: { code: 403, message: 'Vertex AI API has not been used in project p1.' } }, { status: 403 }),
    );
    const warn = t.mock.method(console, 'warn', () => {});
    await rejectsWith(geminiClient(vertex, ['gemini-x'])('prompt', [image]), 'unavailable');
    const logged = warn.mock.calls.map((c) => c.arguments.join(' ')).join('\n');
    assert.match(logged, /403/);
    assert.match(logged, /Vertex AI API has not been used/);
    assert.doesNotMatch(logged, /SECRET-TOKEN-123/, 'the token is never logged');
  });
});

describe('geminiModels', () => {
  test('GEMINI_MODELS, comma separated, in order; the pinned ones when it names none', () => {
    assert.deepEqual(geminiModels('gemini-a,gemini-b'), ['gemini-a', 'gemini-b']);
    assert.deepEqual(geminiModels(' gemini-a , ,gemini-b,'), ['gemini-a', 'gemini-b']);
    assert.deepEqual(geminiModels(undefined), DEFAULT_MODELS);
    assert.deepEqual(geminiModels(' , '), DEFAULT_MODELS);
  });
});
