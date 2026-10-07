import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { buildPrompt, geminiClient, photoQuota, PHOTOS_PER_MONTH, recognizeRoster, type Gemini } from '../src/photo.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch } from './support.js';

const image = { mimeType: 'image/jpeg', data: Buffer.from('jpeg').toString('base64') };
const ok: Gemini = async () => ({ rows: [{ date: '2026-10-04', duties: [] }], inputTokens: 2000, outputTokens: 3000 });

async function church() {
  await seedChurch('C1', { pastor: 'admin', editor: 'staff', staff: 'staff' });
  await seedChurch('C2', { other: 'admin' });
  await db.doc('churches/C1/members/editor').update({ groups: ['roster-editors'], zoneTypes: ['sunday'] });
  await db.doc('churches/C1/settings/services').set({
    services: [{ id: 'sunday', name: '主日崇拜', duties: ['司會', '司琴'], events: [{ name: '聖餐' }] }],
    ids: ['sunday'],
  });
}

beforeEach(clearFirestore);

describe('recognizeRoster', () => {
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

describe('photoQuota', () => {
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
  test('includes nicknames and the layout rules when the church has them', () => {
    const p = buildPrompt({
      service: { id: 'sunday', name: '主日', duties: ['司會'] },
      names: ['陳小明'],
      today: '2026-10-02',
      rules: { layoutRules: '## 這張表怎麼讀\n轉置的表', nicknames: { 小名: '陳小明' } },
    });
    assert.match(p, /轉置的表/);
    assert.match(p, /「小名」是「陳小明」/);
    assert.match(p, /今天是 2026-10-02/);
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
