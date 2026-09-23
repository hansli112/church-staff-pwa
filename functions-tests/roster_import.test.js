// Tests for POST /api/roster/import-image.
//
// Same approach as calendar.test.js: no Miniflare, no wrangler dev. Node 22
// already gives fetch/Response/Headers, which is the surface the Workers
// runtime gives the function, and swapping the global fetch keeps the tests on
// the real wiring instead of a seam production never uses.

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { onRequestPost, parseImportRequest, rejectOversizedBody } from '../functions/api/roster/import-image.js';
import { callGemini, extractJson } from '../worker/gemini.js';
import {
  ADMIN_UID,
  CALENDAR_EDITOR_UID,
  MEMBER_UID,
  PROJECT_ID,
  ROSTER_EDITOR_UID,
  idToken,
  muteConsoleError,
  request,
  withFetch,
} from './helpers.js';

/// Gemini 免費層每日額度用完時的回應，原樣。
const REAL_DAILY_QUOTA_429 = {
  "error": {
    "code": 429,
    "message": "You exceeded your current quota, please check your plan and billing details. For more information on this error, head to: https://ai.google.dev/gemini-api/docs/rate-limits. To monitor your current usage, head to: https://ai.dev/rate-limit. \n* Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20, model: gemini-3.6-flash\nPlease retry in 51s.",
    "status": "RESOURCE_EXHAUSTED",
    "details": [
      {
        "@type": "type.googleapis.com/google.rpc.Help",
        "links": [
          {
            "description": "Learn more about Gemini API quotas",
            "url": "https://ai.google.dev/gemini-api/docs/rate-limits"
          }
        ]
      },
      {
        "@type": "type.googleapis.com/google.rpc.QuotaFailure",
        "violations": [
          {
            "quotaMetric": "generativelanguage.googleapis.com/generate_content_free_tier_requests",
            "quotaId": "GenerateRequestsPerDayPerProjectPerModel-FreeTier",
            "quotaDimensions": {
              "model": "gemini-3.6-flash",
              "location": "global"
            },
            "quotaValue": "20"
          }
        ]
      },
      {
        "@type": "type.googleapis.com/google.rpc.RetryInfo",
        "retryDelay": "51s"
      }
    ]
  }
};


const GEMINI_HOST = 'https://generativelanguage.googleapis.com/';

/// 發佈出去的是**模板**，不是完成品：{{...}} 那幾個由 worker 每次呼叫時從
/// Firestore 現況填。名單烤進模板的話，新同工建完帳號還要有人記得重跑腳本。
const PUBLISHED_TEMPLATE =
  '把服事表照片轉成 JSON。\n服事項目：{{ROLES}}\n活動：{{EVENTS}}\n' +
  '同工名單：\n{{NAMES}}\n今天是 {{TODAY}}。範例：{{SAMPLE_ROLE_A}}／{{SAMPLE_ROLE_B}}';
const PIXEL = 'aGVsbG8td29ybGQ=';

const ROLES = ['晨禱', '敬拜主領', 'Vocal'];
const EVENTS = ['聖餐', '愛餐'];
const STAFF = ['陳志明', '李大華'];

const ENV = {
  FIREBASE_PROJECT_ID: PROJECT_ID,
  GEMINI_API_KEY: 'test-gemini-key',
};

const ALL_TYPES = ['sundayService', 'youth', 'children'];

/// admin 刻意不給 zoneTypes：firestore.rules 的 canEditRosterType() 說
/// 「admin keeps every type without holding a zone」，這裡要守住同一件事。
const USERS = {
  [ADMIN_UID]: { role: 'admin', name: '王管理' },
  [MEMBER_UID]: { role: 'member', name: '路人' },
  [ROSTER_EDITOR_UID]: {
    role: 'staff',
    groups: ['roster-editors'],
    name: '服事表同工',
    zoneTypes: ALL_TYPES,
  },
  [CALENDAR_EDITOR_UID]: { role: 'staff', groups: ['calendar-editors'], name: '行事曆同工' },
};

const ROWS = [{ date: '2026-10-04', duties: [{ role: '敬拜主領', people: ['陳志明'] }] }];

/// Routes the two upstreams this function talks to and records every call, so a
/// test can assert what actually went to Gemini rather than only what came back.
function fakeFetch({
  prompts = { youth: PUBLISHED_TEMPLATE },
  gemini,
  roles = { youth: ROLES, children: ROLES, sundayService: ROLES },
  events = { youth: EVENTS },
  staff = STAFF,
  // 覆寫服事表同工的牧區，用來測「有編輯權但沒有那個牧區」。
  zones,
} = {}) {
  const calls = [];
  const impl = async (url, init = {}) => {
    const target = String(url);
    calls.push({ url: target, method: init.method ?? 'GET', body: init.body, init });

    // 列出整個 users 集合（沒有 /{uid}），跟下面讀單一使用者是兩回事。
    if (target.includes('/documents/users?')) {
      return Response.json({
        documents: staff.map((name) => ({
          name: `users/${name}`,
          fields: { name: { stringValue: name } },
        })),
      });
    }

    if (target.includes('/documents/settings/roster_templates')) {
      return Response.json({
        fields: Object.fromEntries(
          Object.entries(roles).map(([type, list]) => [
            type,
            { arrayValue: { values: list.map((r) => ({ stringValue: r })) } },
          ]),
        ),
      });
    }

    if (target.includes('/documents/settings/event_options')) {
      return Response.json({
        fields: Object.fromEntries(
          Object.entries(events).map(([type, list]) => [
            type,
            {
              arrayValue: {
                values: list.map((name) => ({
                  mapValue: { fields: { name: { stringValue: name } } },
                })),
              },
            },
          ]),
        ),
      });
    }

    if (target.includes('/documents/users/')) {
      const uid = decodeURIComponent(target.split('/documents/users/')[1].split('?')[0]);
      if (!(uid in USERS)) return new Response('{}', { status: 404 });
      const profile = USERS[uid];
      const fields = {};
      if (profile.role != null) fields.role = { stringValue: profile.role };
      if (profile.name != null) fields.name = { stringValue: profile.name };
      if (profile.groups != null) {
        fields.groups = { arrayValue: { values: profile.groups.map((g) => ({ stringValue: g })) } };
      }
      const zoneTypes = uid === ROSTER_EDITOR_UID && zones ? zones : profile.zoneTypes;
      if (zoneTypes != null) {
        fields.zoneTypes = {
          arrayValue: { values: zoneTypes.map((t) => ({ stringValue: t })) },
        };
      }
      return Response.json({ name: `users/${uid}`, fields });
    }

    if (target.includes('/documents/settings/import_prompts')) {
      if (prompts === null) return new Response('{}', { status: 404 });
      const fields = Object.fromEntries(
        Object.entries(prompts).map(([type, body]) => [type, { stringValue: body }]),
      );
      return Response.json({ name: 'settings/import_prompts', fields });
    }

    if (target.startsWith(GEMINI_HOST)) {
      if (typeof gemini === 'function') return gemini(target, init, calls);
      return Response.json({
        candidates: [{ content: { parts: [{ text: JSON.stringify(ROWS) }] } }],
      });
    }

    throw new Error(`unexpected fetch to ${target}`);
  };
  impl.calls = calls;
  impl.geminiCalls = () => calls.filter((call) => call.url.startsWith(GEMINI_HOST));
  return impl;
}

function validBody(overrides = {}) {
  return { type: 'youth', images: [{ mimeType: 'image/png', data: PIXEL }], ...overrides };
}

/// body 與 token 都給預設值，這樣只關心權限或上游的案例不必每次重寫它們。
async function post(impl, { env = ENV, body = validBody(), ...init } = {}) {
  return withFetch(impl, () =>
    onRequestPost({
      request: request('POST', {
        token: idToken(ROSTER_EDITOR_UID),
        ...init,
        body,
        path: '/api/roster/import-image',
      }),
      env,
    }),
  );
}

describe('POST /api/roster/import-image — 權限', () => {
  test('roster-editors 可以轉換', async () => {
    const impl = fakeFetch();
    const response = await post(impl);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { entries: ROWS });
  });

  test('admin 也可以（admin 是 root）', async () => {
    const impl = fakeFetch();
    const response = await post(impl, { token: idToken(ADMIN_UID) });
    assert.equal(response.status, 200);
  });

  // 兩個 group 是正交的：給了行事曆編輯權不等於能改服事表。
  test('只有 calendar-editors 的人被擋下來，而且訊息講的是服事表', async () => {
    const impl = fakeFetch();
    const response = await post(impl, { token: idToken(CALENDAR_EDITOR_UID) });
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error, '沒有編輯服事表的權限');
    assert.equal(impl.geminiCalls().length, 0, '被擋下來的人不該花掉任何辨識額度');
  });

  test('一般會眾被擋下來', async () => {
    const impl = fakeFetch();
    const response = await post(impl, { token: idToken(MEMBER_UID) });
    assert.equal(response.status, 403);
  });

  // group 說「可以改服事表」，zone 說「哪一個」—— 跟 firestore.rules 的
  // canEditRosterType() 同一套。少了這道，青崇同工寫不進主日，卻照樣可以把
  // 免費辨識額度花在主日上。
  test('有編輯權但沒有那個牧區的人被擋下來，而且不花額度', async () => {
    const impl = fakeFetch({ zones: ['youth'] });
    const response = await post(impl, { body: validBody({ type: 'sundayService' }) });
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error, '沒有編輯這個崇拜服事表的權限');
    assert.equal(impl.geminiCalls().length, 0);
  });

  test('自己牧區的照樣可以轉', async () => {
    const impl = fakeFetch({ zones: ['youth'] });
    assert.equal((await post(impl, { body: validBody({ type: 'youth' }) })).status, 200);
  });

  test('admin 不必持有牧區也能轉任何一個', async () => {
    const impl = fakeFetch({ prompts: { sundayService: PUBLISHED_TEMPLATE } });
    const response = await post(impl, {
      token: idToken(ADMIN_UID),
      body: validBody({ type: 'sundayService' }),
    });
    assert.equal(response.status, 200);
  });

  test('zoneTypes 欄位不存在時當作沒有牧區', async () => {
    const impl = fakeFetch({ zones: [] });
    assert.equal((await post(impl)).status, 403);
  });

  test('沒帶 token 就是 401', async () => {
    const impl = fakeFetch();
    const response = await post(impl, { token: null });
    assert.equal(response.status, 401);
    assert.equal(impl.geminiCalls().length, 0);
  });
});

describe('POST /api/roster/import-image — 送出去的東西', () => {
  test('帶著發佈好的 prompt 與照片，key 走 header 不走 query string', async () => {
    const impl = fakeFetch();
    await post(impl, { body: validBody() });

    const [call] = impl.geminiCalls();
    assert.equal(call.method, 'POST');
    assert.ok(
      !call.url.includes('key='),
      'API key 不可以出現在網址裡 —— query string 會進存取日誌',
    );
    assert.equal(call.init.headers['X-goog-api-key'], 'test-gemini-key');

    const sent = JSON.parse(call.body);
    const prompt = sent.contents[0].parts[0].text;
    assert.ok(!prompt.includes('{{'), `送出去的 prompt 還有沒填的欄位：${prompt}`);
    assert.ok(prompt.includes('晨禱、敬拜主領、Vocal'));
    // 排序後的順序是名單決定的，這裡在意的是「兩個都在」而不是誰先誰後。
    for (const name of STAFF) assert.ok(prompt.includes(name), `名單少了 ${name}`);
    assert.deepEqual(sent.contents[0].parts[1], {
      inline_data: { mime_type: 'image/png', data: PIXEL },
    });
    // 同一張表每次都要轉出同一份，這裡沒有創意的空間。
    assert.equal(sent.generationConfig.temperature, 0);
    assert.equal(sent.generationConfig.responseMimeType, 'application/json');
  });

  test('用的是該崇拜自己的 prompt，不是隨便一個', async () => {
    const impl = fakeFetch({
      prompts: {
        youth: `青崇用的 ${PUBLISHED_TEMPLATE}`,
        children: `兒主用的 ${PUBLISHED_TEMPLATE}`,
        sundayService: `主日用的 ${PUBLISHED_TEMPLATE}`,
      },
    });
    await post(impl, { body: validBody({ type: 'children' }) });
    assert.ok(JSON.parse(impl.geminiCalls()[0].body).contents[0].parts[0].text.startsWith('兒主用的'));
  });

  test('多張照片照順序一起送', async () => {
    const impl = fakeFetch();
    await post(impl, {
      body: validBody({
        images: [
          { mimeType: 'image/png', data: 'AAAA' },
          { mimeType: 'image/jpeg', data: 'BBBB' },
        ],
      }),
    });
    const parts = JSON.parse(impl.geminiCalls()[0].body).contents[0].parts;
    assert.equal(parts.length, 3, 'prompt 一份加上兩張圖');
    assert.equal(parts[1].inline_data.data, 'AAAA');
    assert.equal(parts[2].inline_data.data, 'BBBB');
  });

  test('讀 Firestore 用的是呼叫者自己的 token', async () => {
    const impl = fakeFetch();
    const token = idToken(ROSTER_EDITOR_UID);
    await post(impl, { token, body: validBody() });
    const reads = impl.calls.filter((c) => c.url.includes('/documents/'));
    assert.ok(reads.length >= 2);
    for (const read of reads) {
      assert.equal(
        read.init.headers.Authorization,
        `Bearer ${token}`,
        'worker 不該用自己的權限讀 —— firestore.rules 要繼續是唯一的裁判',
      );
    }
  });
});

describe('POST /api/roster/import-image — 名單是活的', () => {
  // 這一組是這個設計存在的理由。名單烤進發佈的模板裡的話，新同工建完帳號
  // 還要有人記得回來重跑腳本 —— 而沒有人會記得。
  test('新同工建了帳號就會出現在白名單，不必重新發佈', async () => {
    const impl = fakeFetch({ staff: [...STAFF, '黃雅婷'] });
    await post(impl);
    const prompt = JSON.parse(impl.geminiCalls()[0].body).contents[0].parts[0].text;
    assert.ok(prompt.includes('黃雅婷'), '名單是每次呼叫才讀的，不是發佈當下的快照');
  });

  test('新增的服事項目與活動同樣即時生效', async () => {
    const impl = fakeFetch({
      roles: { youth: [...ROLES, '報告'] },
      events: { youth: [...EVENTS, '福音 BIG DAY'] },
    });
    await post(impl);
    const prompt = JSON.parse(impl.geminiCalls()[0].body).contents[0].parts[0].text;
    assert.ok(prompt.includes('報告'));
    assert.ok(prompt.includes('福音 BIG DAY'));
  });

  // users 文件裡還有 email 與 FCM token，那些沒有理由進到送去 Google 的
  // prompt 裡 —— 所以只跟 Firestore 要 name。
  test('讀名單時只要 name 這個欄位', async () => {
    const impl = fakeFetch();
    await post(impl);
    const listing = impl.calls.find((c) => c.url.includes('/documents/users?'));
    assert.ok(listing, '應該要列一次 users');
    assert.ok(listing.url.includes('mask.fieldPaths=name'));
    assert.ok(!listing.url.includes('email'));
  });

  test('這個崇拜還沒有服事項目時擋下來，不浪費一次辨識', async () => {
    const impl = fakeFetch({ roles: {} });
    const restore = muteConsoleError();
    try {
      const response = await post(impl);
      assert.equal(response.status, 500);
      assert.equal((await response.json()).error, '這個崇拜還沒有服事項目設定，請管理員先新增');
      assert.equal(impl.geminiCalls().length, 0);
    } finally {
      restore();
    }
  });

  // 模板改了但 fillPrompt 沒跟上時，帶著 {{...}} 的字面值送出去，模型會把
  // 那串括號當成指令的一部分 —— 錯得不明顯，比直接失敗糟。
  test('模板有 worker 不認得的欄位時，寧可失敗也不送出去', async () => {
    const impl = fakeFetch({ prompts: { youth: `${PUBLISHED_TEMPLATE}\n{{SOMETHING_NEW}}` } });
    const restore = muteConsoleError();
    try {
      const response = await post(impl);
      assert.equal(response.status, 500);
      assert.equal(impl.geminiCalls().length, 0);
    } finally {
      restore();
    }
  });
});

describe('POST /api/roster/import-image — 請求驗證', () => {
  const cases = [
    ['沒有 type', { images: [{ mimeType: 'image/png', data: PIXEL }] }, 400, '不知道這是哪一個崇拜的服事表'],
    ['type 不認得', validBody({ type: 'wedding' }), 400, '不知道這是哪一個崇拜的服事表'],
    ['沒有照片', validBody({ images: [] }), 400, '請先選一張服事表照片'],
    ['images 不是陣列', validBody({ images: 'nope' }), 400, '請先選一張服事表照片'],
    [
      '照片太多張',
      validBody({ images: Array.from({ length: 4 }, () => ({ mimeType: 'image/png', data: PIXEL })) }),
      400,
      '一次最多 3 張照片',
    ],
    [
      '格式不支援',
      validBody({ images: [{ mimeType: 'application/pdf', data: PIXEL }] }),
      400,
      '照片的格式不支援，請用 JPG 或 PNG',
    ],
    ['照片沒有內容', validBody({ images: [{ mimeType: 'image/png', data: '' }] }), 400, '照片讀不到內容，請重新選一次'],
  ];

  for (const [name, body, status, message] of cases) {
    test(name, () => {
      assert.throws(() => parseImportRequest(body), { status, message });
    });
  }

  test('太大的照片擋在前面，不會先送上去才失敗', () => {
    const tooBig = 'A'.repeat(3 * 1024 * 1024);
    assert.throws(() => parseImportRequest(validBody({ images: [{ mimeType: 'image/png', data: tooBig }] })), {
      status: 413,
    });
  });

  test('整個請求太大時不讀內容就擋掉', () => {
    // 讀進來再擋就太晚了：解析一個幾 MB 的 body 本身就會用完 CPU 額度，
    // Cloudflare 會先把 worker 砍掉，使用者只看得到「忙碌中」。
    const big = new Request('https://app.example/api/roster/import-image', {
      method: 'POST',
      headers: { 'content-length': String(5 * 1024 * 1024) },
    });
    assert.throws(() => rejectOversizedBody(big), { status: 413 });

    const small = new Request('https://app.example/api/roster/import-image', {
      method: 'POST',
      headers: { 'content-length': String(900 * 1024) },
    });
    assert.doesNotThrow(() => rejectOversizedBody(small));
  });

  test('多張時訊息會講是第幾張', () => {
    assert.throws(
      () =>
        parseImportRequest(
          validBody({
            images: [
              { mimeType: 'image/png', data: PIXEL },
              { mimeType: 'text/plain', data: PIXEL },
            ],
          }),
        ),
      { message: '第 2 張照片的格式不支援，請用 JPG 或 PNG' },
    );
  });

  test('壞掉的請求不會花掉辨識額度', async () => {
    const impl = fakeFetch();
    const restore = muteConsoleError();
    try {
      const response = await post(impl, { body: validBody({ type: 'wedding' }) });
      assert.equal(response.status, 400);
      assert.equal(impl.geminiCalls().length, 0);
    } finally {
      restore();
    }
  });
});

describe('POST /api/roster/import-image — prompt 還沒發佈', () => {
  test('沒有那份文件時說去找管理員，而且不呼叫 Gemini', async () => {
    const impl = fakeFetch({ prompts: null });
    const restore = muteConsoleError();
    try {
      const response = await post(impl);
      assert.equal(response.status, 500);
      assert.equal((await response.json()).error, '辨識設定還沒建立，請聯絡管理員');
      assert.equal(impl.geminiCalls().length, 0);
    } finally {
      restore();
    }
  });

  test('文件在但少了這個崇拜，一樣擋下來', async () => {
    const impl = fakeFetch({ prompts: { youth: PUBLISHED_TEMPLATE } });
    const restore = muteConsoleError();
    try {
      const response = await post(impl, { body: validBody({ type: 'children' }) });
      assert.equal(response.status, 500);
      assert.equal(impl.geminiCalls().length, 0);
    } finally {
      restore();
    }
  });
});

describe('callGemini — 上游的各種回法', () => {
  const images = [{ mimeType: 'image/png', data: PIXEL }];

  async function call(gemini) {
    const impl = fakeFetch({ gemini });
    return callGemini(ENV, {
      prompt: PUBLISHED_TEMPLATE,
      images,
      fetchImpl: impl,
      // 正式環境會等 2 秒、5 秒；測試不必真的等。
      retryDelaysMs: [0, 0],
    });
  }

  test('503 重試兩次就停，不會一直重試下去', async () => {
    let attempts = 0;
    const restore = muteConsoleError();
    try {
      await assert.rejects(
        () =>
          call(() => {
            attempts += 1;
            return new Response('busy', { status: 503 });
          }),
        { status: 503, message: '辨識服務忙碌中，請稍後再試一次' },
      );
    } finally {
      restore();
    }
    assert.equal(attempts, 3, '一次原始呼叫加兩次重試');
  });

  test('連兩次 503、第三次成功就當作成功', async () => {
    // 2026-09-23 實際碰到的就是這個順序。
    let attempts = 0;
    const rows = await call(() => {
      attempts += 1;
      if (attempts <= 2) return new Response('busy', { status: 503 });
      return Response.json({ candidates: [{ content: { parts: [{ text: JSON.stringify(ROWS) }] } }] });
    });
    assert.deepEqual(rows, ROWS);
  });

  test('每日額度用完時叫人明天再來，而不是「稍後」', async () => {
    // Gemini 真的回的，2026-09-23 原樣貼上（retry 秒數除外，那個每次不同）。
    // 要原樣：額度名稱在第一千個字左右，一份截短的假回應測不出「讀一半就判斷」。
    const body = JSON.stringify(REAL_DAILY_QUOTA_429, null, 2);
    assert.ok(body.indexOf('PerDay') > 500, '這份樣本要能測出截斷的問題');
    const restore = muteConsoleError();
    try {
      await assert.rejects(() => call(() => new Response(body, { status: 429 })), {
        status: 429,
        message: /今天的免費辨識次數用完了/,
      });
    } finally {
      restore();
    }
  });

  test('429 不重試：額度不會在幾秒內回來，重試只是多打一次', async () => {
    let attempts = 0;
    const restore = muteConsoleError();
    try {
      await assert.rejects(
        () =>
          call(() => {
            attempts += 1;
            return new Response(JSON.stringify(REAL_DAILY_QUOTA_429), { status: 429 });
          }),
        { status: 429 },
      );
    } finally {
      restore();
    }
    assert.equal(attempts, 1);
  });

  test('每分鐘的限制說等一下就好', async () => {
    const restore = muteConsoleError();
    try {
      await assert.rejects(
        () =>
          call(
            () =>
              new Response(JSON.stringify({ error: { details: [{ violations: [{ quotaId: 'GenerateRequestsPerMinutePerProjectPerModel-FreeTier' }] }] } }), {
                status: 429,
              }),
          ),
        { status: 429, message: '辨識太頻繁了，等一分鐘再試' },
      );
    } finally {
      restore();
    }
  });

  test('模型名稱設錯時是伺服器設定問題，不是使用者的錯', async () => {
    const restore = muteConsoleError();
    try {
      await assert.rejects(() => call(() => new Response('{}', { status: 404 })), { status: 500 });
    } finally {
      restore();
    }
  });

  test('等太久是逾時，不是「連不上」', async () => {
    // 真的 fetch 被 abort 時就是這樣：帶著 signal 的請求 reject。
    const hang = (url, init) =>
      new Promise((_, reject) => {
        init.signal.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
      });
    const restore = muteConsoleError();
    try {
      await assert.rejects(
        () => callGemini(ENV, { prompt: 'x', images, fetchImpl: hang, timeoutMs: 5 }),
        { status: 504, message: '辨識太久了，請把照片裁到只剩表格再試' },
      );
    } finally {
      restore();
    }
  });

  test('沒設 GEMINI_API_KEY 就不會送出任何東西', async () => {
    const impl = fakeFetch();
    const restore = muteConsoleError();
    try {
      await assert.rejects(
        () => callGemini({ FIREBASE_PROJECT_ID: PROJECT_ID }, { prompt: 'x', images, fetchImpl: impl }),
        { status: 500 },
      );
      assert.equal(impl.geminiCalls().length, 0);
    } finally {
      restore();
    }
  });
});

describe('extractJson', () => {
  const ok = (text) => ({ candidates: [{ content: { parts: [{ text }] } }] });

  test('一般情況', () => {
    assert.deepEqual(extractJson(ok(JSON.stringify(ROWS))), ROWS);
  });

  // prompt 明講不要圍欄，但模型還是會加。為這個讓整份轉換失敗不划算。
  test('模型自己加了程式碼圍欄也接得住', () => {
    assert.deepEqual(extractJson(ok('```json\n' + JSON.stringify(ROWS) + '\n```')), ROWS);
  });

  test('分段回來的文字會接起來', () => {
    const payload = { candidates: [{ content: { parts: [{ text: '[{"date":' }, { text: '"2026-10-04"}]' }] } }] };
    assert.deepEqual(extractJson(payload), [{ date: '2026-10-04' }]);
  });

  test('被安全過濾擋掉時給的是可以照做的訊息', () => {
    const restore = muteConsoleError();
    try {
      assert.throws(() => extractJson({ promptFeedback: { blockReason: 'SAFETY' } }), {
        status: 502,
        message: '辨識沒有產生結果，請換一張照片再試',
      });
    } finally {
      restore();
    }
  });

  // 截斷的輸出是最容易誤會的一種失敗：看起來像模型壞了，其實是表太大。
  test('輸出被長度截斷時叫人裁成兩半分兩次', () => {
    const restore = muteConsoleError();
    try {
      assert.throws(() => extractJson({ candidates: [{ finishReason: 'MAX_TOKENS', content: { parts: [] } }] }), {
        message: '服事表太大，請把照片裁成上下兩半，分兩次辨識',
      });
    } finally {
      restore();
    }
  });

  test('不是 JSON 時不會把 SyntaxError 丟給使用者', () => {
    const restore = muteConsoleError();
    try {
      assert.throws(() => extractJson(ok('抱歉，我看不懂這張表')), { status: 502 });
    } finally {
      restore();
    }
  });

  // parseRosterImportJson 的最外層要求是陣列；不是陣列的話那邊會直接擋，
  // 但在這裡就說清楚，訊息才會是「再試一次」而不是「JSON 最外層需為陣列」。
  test('回的是物件而不是陣列時擋在這裡', () => {
    const restore = muteConsoleError();
    try {
      assert.throws(() => extractJson(ok('{"date":"2026-10-04"}')), { status: 502 });
    } finally {
      restore();
    }
  });
});
