import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { beforeEach, describe, test } from 'node:test';

import {
  calendarAuthUrl,
  calendarCallback,
  calendarDisconnect,
  calendarEvents,
  calendarSelect,
  calendarWrite,
  decrypt,
  encrypt,
  GoogleAuthRevoked,
  type CalendarEvent,
  type GoogleApi,
  type OAuthConfig,
} from '../src/calendar.js';
import { deliver, webhookSave } from '../src/webhook.js';
import { caller, clearFirestore, db, deps, fakeFetch, rejectsWith, seedChurch, setNow } from './support.js';

const config: OAuthConfig = {
  clientId: 'client',
  clientSecret: 'secret',
  redirectUri: 'https://fn/calendarCallback',
  appUrl: 'https://app.example',
  tokenKey: randomBytes(32).toString('base64'),
};

function fakeGoogle() {
  const calls = { events: 0, revoked: [] as string[], removed: [] as string[] };
  let revoked = false;
  const stored: CalendarEvent[] = [{ id: 'e1', title: '同工會', start: '2026-10-10', end: '2026-10-11', allDay: true }];
  const google: GoogleApi = {
    exchangeCode: async (code) => {
      if (code === 'used') throw new Error('google 400: invalid_grant');
      return { refreshToken: code === 'good' ? 'refresh-123' : null };
    },
    accessToken: async (rt) => {
      if (revoked) throw new GoogleAuthRevoked();
      assert.equal(rt, 'refresh-123');
      return 'access';
    },
    calendars: async () => [{ id: 'cal-1', name: '教會行事曆', primary: false }],
    events: async () => {
      calls.events++;
      return stored;
    },
    upsert: async (_t, _c, e) => ({ ...e, id: e.id ?? 'new-id', link: `https://calendar.google.com/event?eid=${e.id ?? 'new-id'}` }),
    get: async (_t, _c, id) => stored.find((e) => e.id === id) ?? null,
    remove: async (_t, _c, id) => {
      calls.removed.push(id);
    },
    revoke: async (rt) => {
      calls.revoked.push(rt);
    },
  };
  return { google, calls, revoke: () => (revoked = true) };
}

async function church() {
  await seedChurch('C1', { pastor: 'admin', editor: 'staff', staff: 'staff' });
  await seedChurch('C2', { other: 'admin' });
  await db.doc('churches/C1/members/editor').update({ groups: ['calendar-editors'] });
}

async function connect(g: GoogleApi) {
  const d = { ...deps, google: g, config };
  const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
  const state = new URL(url).searchParams.get('state')!;
  const back = await calendarCallback(d, { state, code: 'good' });
  await calendarSelect(d, caller('pastor'), { churchId: 'C1', calendarId: 'cal-1', calendarName: '教會行事曆' });
  return back;
}

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-02T10:00:00+08:00'));
});

describe('connecting', () => {
  test('only an admin gets a consent URL, with the calendar scopes and offline access', async () => {
    await church();
    const { google } = fakeGoogle();
    const d = { ...deps, google, config };
    const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
    const u = new URL(url);
    assert.match(u.searchParams.get('scope')!, /calendar\.events/);
    assert.equal(u.searchParams.get('access_type'), 'offline');
    await rejectsWith(calendarAuthUrl(d, caller('editor'), { churchId: 'C1' }), 'permissionDenied');
    await rejectsWith(calendarAuthUrl(d, caller('other'), { churchId: 'C1' }), 'permissionDenied');
  });

  test('the callback stores the token encrypted, never in the church tree', async () => {
    await church();
    const { google } = fakeGoogle();
    const back = await connect(google);
    assert.equal(back, 'https://app.example/me/calendar?result=connected');
    const token = await db.doc('calendarTokens/C1').get();
    assert.notEqual(token.get('token'), 'refresh-123');
    assert.equal(decrypt(token.get('token'), config.tokenKey), 'refresh-123');
    const settings = await db.doc('churches/C1/settings/calendar').get();
    assert.deepEqual(Object.keys(settings.data()!).sort(), ['calendarId', 'calendarName', 'connected', 'needsReconnect', 'updatedAt']);
  });

  test('an expired or reused state is refused', async () => {
    await church();
    const { google } = fakeGoogle();
    const d = { ...deps, google, config };
    const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
    const state = new URL(url).searchParams.get('state')!;
    setNow(new Date('2026-10-02T10:30:00+08:00'));
    assert.match(await calendarCallback(d, { state, code: 'good' }), /result=expired/);
    assert.match(await calendarCallback(d, { state, code: 'good' }), /result=expired/);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
  });

  test('a code Google refuses (used twice, page reloaded) sends the admin back to try again', async () => {
    await church();
    const { google } = fakeGoogle();
    const d = { ...deps, google, config };
    const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
    const state = new URL(url).searchParams.get('state')!;
    assert.match(await calendarCallback(d, { state, code: 'used' }), /result=failed/);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
  });

  test('encryption round-trips and is not deterministic', () => {
    const a = encrypt('x', config.tokenKey);
    assert.notEqual(a, encrypt('x', config.tokenKey));
    assert.equal(decrypt(a, config.tokenKey), 'x');
  });
});

describe('reading', () => {
  test('members share one cached copy for 10 minutes', async () => {
    await church();
    const { google, calls } = fakeGoogle();
    await connect(google);
    const d = { ...deps, google, config };
    const a = await calendarEvents(d, caller('staff'), { churchId: 'C1', month: '2026-10' });
    const b = await calendarEvents(d, caller('editor'), { churchId: 'C1', month: '2026-10' });
    assert.equal(a.events.length, 1);
    assert.equal(b.cached, true);
    assert.equal(calls.events, 1);
    setNow(new Date('2026-10-02T10:11:00+08:00'));
    await calendarEvents(d, caller('staff'), { churchId: 'C1', month: '2026-10' });
    assert.equal(calls.events, 2);
  });

  test('another church cannot read it', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    await rejectsWith(
      calendarEvents({ ...deps, google, config }, caller('other'), { churchId: 'C1', month: '2026-10' }),
      'permissionDenied',
    );
  });

  test('a revoked grant marks the church as needing to reconnect', async () => {
    await church();
    const f = fakeGoogle();
    await connect(f.google);
    f.revoke();
    const err = await rejectsWith(
      calendarEvents({ ...deps, google: f.google, config }, caller('staff'), { churchId: 'C1', month: '2026-11' }),
      'unknown',
    );
    assert.equal((err as { details: { detail: string } }).details.detail, 'reconnect');
    assert.equal((await db.doc('churches/C1/settings/calendar').get()).get('needsReconnect'), true);
  });
});

describe('writing', () => {
  test('calendar-editors and admins write; staff are refused', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    const d = { ...deps, google, config };
    const event = { title: '禱告會', start: '2026-10-14T19:30:00+08:00', end: '2026-10-14T21:00:00+08:00', allDay: false };
    const r = await calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'upsert', event });
    assert.equal(r.event?.id, 'new-id');
    await rejectsWith(calendarWrite(d, caller('staff'), { churchId: 'C1', op: 'upsert', event }), 'permissionDenied');
  });

  test('a write drops that month from the cache', async () => {
    await church();
    const { google, calls } = fakeGoogle();
    await connect(google);
    const d = { ...deps, google, config };
    await calendarEvents(d, caller('staff'), { churchId: 'C1', month: '2026-10' });
    await calendarWrite(d, caller('pastor'), {
      churchId: 'C1',
      op: 'delete',
      eventId: 'e1',
      event: { start: '2026-10-10' },
    });
    assert.deepEqual(calls.removed, ['e1']);
    await calendarEvents(d, caller('staff'), { churchId: 'C1', month: '2026-10' });
    assert.equal(calls.events, 2);
  });

  test('disconnecting revokes and forgets the token', async () => {
    await church();
    const { google, calls } = fakeGoogle();
    await connect(google);
    await calendarDisconnect({ ...deps, google, config }, caller('pastor'), { churchId: 'C1' });
    assert.deepEqual(calls.revoked, ['refresh-123']);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
    assert.equal((await db.doc('churches/C1/settings/calendar').get()).exists, false);
  });
});

describe('releasing the grant', () => {
  test('when the admin who connected it leaves, the grant is revoked; another admin leaving changes nothing', async () => {
    const { releaseCalendarIfConnector } = await import('../src/calendar.js');
    await church();
    await db.doc('churches/C1/members/editor').update({ role: 'admin' });
    const { google, calls } = fakeGoogle();
    await connect(google);
    const d = { ...deps, google, config };
    assert.equal(await releaseCalendarIfConnector(d, 'C1', 'editor'), false);
    assert.equal(await releaseCalendarIfConnector(d, 'C1', 'pastor'), true);
    assert.deepEqual(calls.revoked, ['refresh-123']);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
  });

  test('cache months follow UTC+8, and a moved event clears both months', async () => {
    const { monthOf } = await import('../src/calendar.js');
    assert.equal(monthOf('2026-10-31T17:00:00.000Z'), '2026-11');
    assert.equal(monthOf('2026-10-31'), '2026-10');
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    const d = { ...deps, google, config };
    await db.doc('calendarCache/C1_2026-10').set({ cid: 'C1', month: '2026-10', events: [] });
    await db.doc('calendarCache/C1_2026-11').set({ cid: 'C1', month: '2026-11', events: [] });
    await calendarWrite(d, caller('pastor'), {
      churchId: 'C1',
      op: 'upsert',
      previousStart: '2026-10-10',
      event: { id: 'e1', title: 'x', start: '2026-11-07', end: '2026-11-08', allDay: true },
    });
    assert.equal((await db.doc('calendarCache/C1_2026-10').get()).exists, false);
    assert.equal((await db.doc('calendarCache/C1_2026-11').get()).exists, false);
  });
});

describe('calendar webhooks', () => {
  const HOOK = 'https://n8n.example/hook';

  async function withHook(events = { calendar: true, roster: false }) {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    const f = fakeFetch({ [HOOK]: { status: 200 } });
    const d = { ...deps, fetch: f.fetch, google, config };
    await webhookSave({ ...d, secretKey: config.tokenKey }, caller('pastor'), { churchId: 'C1', url: HOOK, events });
    await db.doc('churches/C1').update({ name: '恩典堂' });
    await db.doc('churches/C1/members/editor').update({ name: '林同工' });
    const sent = () => f.requests.map((r) => ({ event: r.headers['x-martha-event'], body: JSON.parse(r.body) }));
    return { d, sent };
  }

  test('created and updated, after Google has them, with the editor’s name', async () => {
    const { d, sent } = await withHook();
    const event = { title: '小組聚會', start: '2026-10-20T19:00:00+08:00', end: '2026-10-20T21:00:00+08:00', allDay: false, location: '2F' };
    await calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'upsert', event });
    await calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'upsert', event: { ...event, id: 'new-id', title: '小組聚會（改時間）' } });
    assert.deepEqual(sent()[0], {
      event: 'calendar.created',
      body: {
        action: 'created',
        source: 'martha',
        churchId: 'C1',
        churchName: '恩典堂',
        timeZone: 'Asia/Taipei',
        id: 'new-id',
        title: '小組聚會',
        allDay: false,
        start: '2026-10-20T19:00:00+08:00',
        end: '2026-10-20T21:00:00+08:00',
        location: '2F',
        description: '',
        link: 'https://calendar.google.com/event?eid=new-id',
        actorUid: 'editor',
        actorName: '林同工',
      },
    });
    assert.equal(sent()[1].event, 'calendar.updated');
    assert.equal(sent()[1].body.action, 'updated');
    assert.equal(sent()[1].body.title, '小組聚會（改時間）');
  });

  test('an all-day event ends on its last day', async () => {
    const { d, sent } = await withHook();
    await calendarWrite(d, caller('pastor'), {
      churchId: 'C1',
      op: 'upsert',
      event: { title: '退修會', start: '2026-10-10', end: '2026-10-13', allDay: true },
    });
    assert.equal(sent()[0].body.start, '2026-10-10');
    assert.equal(sent()[0].body.end, '2026-10-12');
  });

  test('deleted sends what the event was before', async () => {
    const { d, sent } = await withHook();
    await calendarWrite(d, caller('pastor'), { churchId: 'C1', op: 'delete', eventId: 'e1', event: { start: '2026-10-10' } });
    assert.equal(sent()[0].event, 'calendar.deleted');
    assert.equal(sent()[0].body.action, 'deleted');
    assert.equal(sent()[0].body.title, '同工會');
    assert.equal(sent()[0].body.allDay, true);
    assert.equal(sent()[0].body.end, '2026-10-10');
  });

  test('nothing is sent when calendar notices are off', async () => {
    const { d, sent } = await withHook({ calendar: false, roster: true });
    await calendarWrite(d, caller('pastor'), { churchId: 'C1', op: 'upsert', event: { title: 'x', start: '2026-10-10', end: '2026-10-11', allDay: true } });
    assert.equal(sent().length, 0);
  });

  test('a failing webhook does not fail the edit', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    const f = fakeFetch({ [HOOK]: { status: 500 } });
    const d = { ...deps, fetch: f.fetch, google, config };
    await webhookSave({ ...d, secretKey: config.tokenKey }, caller('pastor'), { churchId: 'C1', url: HOOK, events: { calendar: true } });
    const r = await calendarWrite(d, caller('pastor'), { churchId: 'C1', op: 'upsert', event: { title: 'x', start: '2026-10-10', end: '2026-10-11', allDay: true } });
    assert.equal(r.event!.id, 'new-id');
    assert.equal((await db.doc('churches/C1/settings/webhook').get()).get('lastDelivery.status'), 500);
  });

  test('a suspended church sends nothing', async () => {
    const { d, sent } = await withHook();
    await db.doc('churches/C1').update({ status: 'suspended' });
    await rejectsWith(
      calendarWrite(d, caller('pastor'), { churchId: 'C1', op: 'upsert', event: { title: 'x', start: '2026-10-10', end: '2026-10-11', allDay: true } }),
      'permissionDenied',
    );
    assert.equal(await deliver({ ...d, secretKey: config.tokenKey }, 'C1', 'calendar.created', {}), null);
    assert.equal(sent().length, 0);
  });
});
