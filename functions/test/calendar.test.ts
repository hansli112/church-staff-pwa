import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { beforeEach, describe, test } from 'node:test';

import {
  calendarAuthUrl,
  calendarCallback,
  calendarDisconnect,
  calendarEvents,
  calendarList,
  calendarSelect,
  calendarWrite,
  GoogleAuthRevoked,
  googleApi,
  monthOf,
  monthsOf,
  releaseCalendarIfConnector,
  type CalendarEvent,
  type GoogleApi,
  type OAuthConfig,
} from '../src/calendar.js';
import { eventRosterDays } from '../src/eventRosters.js';
import { memoryGoogle } from '../src/memoryGoogle.js';
import { seal, unseal } from '../src/sealing.js';
import { notify, webhookSave } from '../src/webhook.js';
import type { ChurchTimeZone } from '../src/timeZones.js';
import { caller, clearFirestore, db, deps as plain, fakeFetch, rejectsWith, seedChurch, setNow } from './support.js';

const config: OAuthConfig = {
  clientId: 'client',
  clientSecret: 'secret',
  redirectUri: 'https://fn/calendarCallback',
  appUrl: 'https://app.example',
  tokenKey: randomBytes(32).toString('base64'),
};
const TPE: ChurchTimeZone = 'Asia/Taipei';
/** Webhook secrets are sealed with the same key, as the wiring does. */
const deps = { ...plain, secretKey: config.tokenKey };

/** Google with one event, the 10th's 同工會. */
const fakeGoogle = () => memoryGoogle([{ id: 'e1', title: '同工會', start: '2026-10-10', end: '2026-10-11', allDay: true }]);

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
    assert.notEqual(token.get('token'), 'refresh-good');
    assert.equal(unseal(token.get('token'), config.tokenKey), 'refresh-good');
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

  test('OAuth completion refuses a connector who is no longer an active church admin before exchanging the code', async () => {
    for (const change of ['demoted', 'removed', 'suspended', 'deleted', 'purged']) {
      await clearFirestore();
      await church();
      const { google, calls } = fakeGoogle();
      let exchanges = 0;
      const exchange = google.exchangeCode;
      google.exchangeCode = async (...args) => { exchanges++; return exchange(...args); };
      const d = { ...deps, google, config };
      const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
      const state = new URL(url).searchParams.get('state')!;
      if (change === 'demoted') await db.doc('churches/C1/members/pastor').update({ role: 'staff' });
      else if (change === 'removed') await db.doc('churches/C1/members/pastor').delete();
      else if (change === 'purged') await db.doc('churches/C1').delete();
      else await db.doc('churches/C1').update({ status: change });
      assert.match(await calendarCallback(d, { state, code: 'good' }), /result=denied/, change);
      assert.equal(exchanges, 0, `${change}: no provider exchange`);
      assert.equal((await db.doc(`calendarStates/${state}`).get()).exists, false, 'the refused state is consumed');
      assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
      assert.equal((await db.doc('churches/C1/settings/calendar').get()).exists, false);
      assert.deepEqual(calls.revoked, [], 'no credential was obtained');
    }
  });

  test('OAuth completion revokes an unused credential when church or admin access changes during the provider exchange', async () => {
    for (const change of ['demoted', 'removed', 'suspended', 'deleted', 'purged']) {
      await clearFirestore();
      await church();
      const { google, calls } = fakeGoogle();
      let entered!: () => void;
      let release!: () => void;
      const exchanging = new Promise<void>((resolve) => { entered = resolve; });
      const gate = new Promise<void>((resolve) => { release = resolve; });
      google.exchangeCode = async () => { entered(); await gate; return { refreshToken: 'unused-refresh' }; };
      const d = { ...deps, google, config };
      const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
      const state = new URL(url).searchParams.get('state')!;
      const pending = calendarCallback(d, { state, code: 'good' });
      await exchanging;
      if (change === 'demoted') await db.doc('churches/C1/members/pastor').update({ role: 'staff' });
      else if (change === 'removed') await db.doc('churches/C1/members/pastor').delete();
      else if (change === 'purged') await db.doc('churches/C1').delete();
      else await db.doc('churches/C1').update({ status: change });
      release();
      assert.match(await pending, /result=denied/, change);
      assert.deepEqual(calls.revoked, ['unused-refresh'], change);
      assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
      assert.equal((await db.doc('churches/C1/settings/calendar').get()).exists, false);
      assert.equal((await db.doc(`calendarStates/${state}`).get()).exists, false);
    }
  });

  test('disconnecting while OAuth exchange waits cancels completion and revokes the unused credential', async () => {
    await church();
    const { google, calls } = fakeGoogle();
    let entered!: () => void;
    let release!: () => void;
    const exchanging = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    google.exchangeCode = async () => { entered(); await gate; return { refreshToken: 'cancelled-refresh' }; };
    const d = { ...deps, google, config };
    const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
    const state = new URL(url).searchParams.get('state')!;
    const pending = calendarCallback(d, { state, code: 'good' });
    await exchanging;
    await calendarDisconnect(d, caller('pastor'), { churchId: 'C1' });
    release();
    assert.match(await pending, /result=denied/);
    assert.deepEqual(calls.revoked, ['cancelled-refresh']);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
    assert.equal((await db.doc('churches/C1/settings/calendar').get()).exists, false);
    assert.equal((await db.doc(`calendarStates/${state}`).get()).exists, false);
  });

  test('grant persistence errors still surface, while the unused credential and reserved state are cleaned up', async () => {
    await church();
    const { google, calls } = fakeGoogle();
    const d = { ...deps, google, config: { ...config, tokenKey: 'not-a-valid-aes-key' } };
    const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
    const state = new URL(url).searchParams.get('state')!;
    await assert.rejects(calendarCallback(d, { state, code: 'good' }), /key length/i);
    assert.deepEqual(calls.revoked, ['refresh-good']);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
    assert.equal((await db.doc('churches/C1/settings/calendar').get()).exists, false);
    assert.equal((await db.doc(`calendarStates/${state}`).get()).exists, false);
  });

  test('simultaneous callbacks consume one consent once without cancelling the exchange already in progress', async () => {
    await church();
    const { google } = fakeGoogle();
    let exchanges = 0;
    let entered!: () => void;
    let release!: () => void;
    const exchanging = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    google.exchangeCode = async () => { exchanges++; entered(); await gate; return { refreshToken: 'refresh-good' }; };
    const d = { ...deps, google, config };
    const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
    const state = new URL(url).searchParams.get('state')!;
    const first = calendarCallback(d, { state, code: 'good' });
    await exchanging;
    try {
      assert.match(await calendarCallback(d, { state, code: 'good' }), /result=expired/);
      assert.equal(exchanges, 1);
    } finally {
      release();
    }
    assert.match(await first, /result=connected/);
    assert.equal((await db.doc(`calendarStates/${state}`).get()).exists, false);
  });

  test('refused grant cleanup leaves another authorized connector’s existing grant intact even if provider revocation fails', async () => {
    await church();
    const { google, calls } = fakeGoogle();
    await connect(google);
    await db.doc('churches/C1/members/editor').update({ role: 'admin' });
    const d = { ...deps, google, config };
    const { url } = await calendarAuthUrl(d, caller('editor'), { churchId: 'C1' });
    const state = new URL(url).searchParams.get('state')!;
    google.exchangeCode = async () => {
      await db.doc('churches/C1/members/editor').update({ role: 'staff' });
      return { refreshToken: 'refused-refresh' };
    };
    google.revoke = async (token) => { calls.revoked.push(token); throw new Error('Google unreachable'); };
    assert.match(await calendarCallback(d, { state, code: 'good' }), /result=denied/);
    assert.deepEqual(calls.revoked, ['refused-refresh']);
    const token = await db.doc('calendarTokens/C1').get();
    assert.equal(token.get('connectedBy'), 'pastor');
    assert.equal(unseal(token.get('token'), config.tokenKey), 'refresh-good');
    assert.equal((await db.doc('churches/C1/settings/calendar').get()).get('calendarId'), 'cal-1');
    assert.equal((await db.doc(`calendarStates/${state}`).get()).exists, false);
  });

  test('sealing round-trips and is not deterministic', () => {
    const a = seal('x', config.tokenKey);
    assert.notEqual(a, seal('x', config.tokenKey));
    assert.equal(unseal(a, config.tokenKey), 'x');
    assert.throws(() => unseal(a, randomBytes(32).toString('base64')));
  });
});

describe('reading', () => {
  test('successive calendar calls reuse the same church’s valid Google token', async () => {
    await church();
    await connect(fakeGoogle().google);
    let refreshes = 0;
    const google = googleApi({ now: deps.now, fetch: async (url) => {
      if (url === 'https://oauth2.googleapis.com/token') {
        refreshes++;
        return Response.json({ access_token: 'access', expires_in: 3600 });
      }
      return Response.json({ items: [{ id: 'cal-1', summary: '教會行事曆' }] });
    } });
    const d = { ...deps, google, config };
    assert.equal((await calendarList(d, caller('pastor'), { churchId: 'C1' })).calendars[0].id, 'cal-1');
    await calendarList(d, caller('pastor'), { churchId: 'C1' });
    assert.equal(refreshes, 1);
  });

  test('a disconnect during token refresh cannot continue using the old grant', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    let entered!: () => void;
    let release!: () => void;
    const refreshing = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    google.accessToken = async () => { entered(); await gate; return 'old-access'; };
    let lists = 0;
    google.calendars = async () => { lists++; return []; };
    const d = { ...deps, google, config };
    const pending = calendarList(d, caller('pastor'), { churchId: 'C1' });
    await refreshing;
    await calendarDisconnect(d, caller('pastor'), { churchId: 'C1' });
    release();
    await rejectsWith(pending, 'unknown');
    assert.equal(lists, 0);
  });

  test('a revoked refresh racing a reconnect reports a changed grant, not a revoked new grant', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    let entered!: () => void;
    let release!: () => void;
    const refreshing = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    google.accessToken = async () => { entered(); await gate; throw new GoogleAuthRevoked(); };
    const d = { ...deps, google, config };
    const pending = calendarList(d, caller('pastor'), { churchId: 'C1' });
    await refreshing;
    await connect(google);
    release();
    const error = await rejectsWith(pending, 'unknown');
    assert.equal((error as { details: { detail: string } }).details.detail, 'calendarChanged');
    google.accessToken = async () => 'new-access';
    google.calendars = async (token) => {
      assert.equal(token, 'new-access');
      return [{ id: 'new-calendar', name: '重新連接', primary: false }];
    };
    assert.equal((await calendarList(d, caller('pastor'), { churchId: 'C1' })).calendars[0].id, 'new-calendar');
  });

  test('warm tokens never replace sign-in, membership, church status, or calendar permissions', async () => {
    await church();
    await connect(fakeGoogle().google);
    let refreshes = 0;
    let requests = 0;
    const google = googleApi({ now: deps.now, fetch: async (url) => {
      if (url === 'https://oauth2.googleapis.com/token') {
        refreshes++;
        return Response.json({ access_token: 'access', expires_in: 3600 });
      }
      requests++;
      return Response.json({ items: [], id: 'created', summary: '活動', start: { date: '2026-10-10' }, end: { date: '2026-10-11' } });
    } });
    const d = { ...deps, google, config };
    const input = { churchId: 'C1', op: 'upsert', event: { title: '活動', start: '2026-10-10', end: '2026-10-11', allDay: true } };
    await calendarList(d, caller('pastor'), { churchId: 'C1' });
    await calendarWrite(d, caller('editor'), input);
    await rejectsWith(calendarList(d, null, { churchId: 'C1' }), 'permissionDenied');
    await rejectsWith(calendarList(d, caller('other'), { churchId: 'C1' }), 'permissionDenied');
    await rejectsWith(calendarWrite(d, caller('staff'), input), 'permissionDenied');
    await db.doc('churches/C1/members/editor').update({ groups: [] });
    await rejectsWith(calendarWrite(d, caller('editor'), input), 'permissionDenied');
    await db.doc('churches/C1').update({ status: 'suspended' });
    await rejectsWith(calendarList(d, caller('pastor'), { churchId: 'C1' }), 'churchClosed');
    await db.doc('churches/C1').update({ status: 'active' });
    await db.doc('churches/C1/members/pastor').delete();
    await rejectsWith(calendarList(d, caller('pastor'), { churchId: 'C1' }), 'permissionDenied');
    assert.equal(refreshes, 1);
    assert.equal(requests, 2);
  });

  test('selecting a calendar or reconnecting cannot reuse the previous grant revision’s token', async () => {
    await church();
    await connect(fakeGoogle().google);
    let refreshes = 0;
    const google = googleApi({ now: deps.now, fetch: async (url) => {
      if (url === 'https://oauth2.googleapis.com/token') {
        return Response.json({ access_token: `access-${++refreshes}`, expires_in: 3600 });
      }
      return Response.json({ items: [] });
    } });
    const d = { ...deps, google, config };
    await calendarList(d, caller('pastor'), { churchId: 'C1' });
    await calendarSelect(d, caller('pastor'), { churchId: 'C1', calendarId: 'cal-2', calendarName: '第二本' });
    await calendarList(d, caller('pastor'), { churchId: 'C1' });
    assert.equal(refreshes, 2);
    await connect(fakeGoogle().google);
    await calendarList(d, caller('pastor'), { churchId: 'C1' });
    assert.equal(refreshes, 3);
  });

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

  test('events without a location or description, as Google sends them, are cached', async () => {
    await church();
    const { google } = fakeGoogle();
    google.events = async () => [
      { id: 'e2', title: '主日', start: '2026-10-11T02:00:00Z', end: '2026-10-11T04:00:00Z', allDay: false, location: undefined, description: undefined, link: undefined },
    ];
    await connect(google);
    const d = { ...deps, google, config };
    const first = await calendarEvents(d, caller('staff'), { churchId: 'C1', month: '2026-10' });
    assert.equal(first.events[0].title, '主日');
    const again = await calendarEvents(d, caller('staff'), { churchId: 'C1', month: '2026-10' });
    assert.equal(again.cached, true);
    assert.deepEqual(Object.keys(again.events[0]).sort(), ['allDay', 'end', 'id', 'start', 'title']);
  });

  test("times go out on the church's clock, for its month; a copy kept for another time zone is read again", async () => {
    await church();
    const { google, calls } = fakeGoogle();
    const asked: [string, string][] = [];
    google.events = async (_t, _c, from, to) => {
      calls.events++;
      asked.push([from.toISOString(), to.toISOString()]);
      return [{ id: 'e2', title: '主日', start: '2026-10-11T17:00:00Z', end: '2026-10-11T19:00:00.000Z', allDay: false }, { id: 'e3', title: '退修會', start: '2026-10-23', end: '2026-10-26', allDay: true }];
    };
    await connect(google);
    const d = { ...deps, google, config };
    const taipei = await calendarEvents(d, caller('staff'), { churchId: 'C1', month: '2026-10' });
    assert.deepEqual(taipei.events.map((e) => [e.start, e.end]), [['2026-10-12T01:00:00+08:00', '2026-10-12T03:00:00+08:00'], ['2026-10-23', '2026-10-26']]);
    assert.deepEqual(asked.at(-1), ['2026-09-30T16:00:00.000Z', '2026-10-31T16:00:00.000Z']);

    await db.doc('churches/C1').update({ timeZone: 'America/Los_Angeles' });
    const la = await calendarEvents(d, caller('staff'), { churchId: 'C1', month: '2026-10' });
    assert.equal(la.cached, false);
    assert.deepEqual(la.events.map((e) => [e.start, e.end])[0], ['2026-10-11T10:00:00-07:00', '2026-10-11T12:00:00-07:00']);
    // October in Los Angeles: summer time throughout.
    assert.deepEqual(asked.at(-1), ['2026-10-01T07:00:00.000Z', '2026-11-01T07:00:00.000Z']);
    assert.equal((await calendarEvents(d, caller('staff'), { churchId: 'C1', month: '2026-10' })).cached, true);
  });

  test("a time from the app is on the church's clock; the event comes back on it, and its roster's days are the church's", async () => {
    await church();
    await db.doc('churches/C1').update({ timeZone: 'America/Los_Angeles' });
    const { google } = fakeGoogle();
    const sent: CalendarEvent[] = [];
    const upsert = google.upsert;
    google.upsert = async (t, c, e) => {
      sent.push(e);
      return upsert(t, c, e);
    };
    await connect(google);
    await db.doc('churches/C1/rosters/ev_e1').set({
      kind: 'event', eventId: 'e1', title: '同工會', dateKey: '2026-10-10', endDateKey: '2026-10-10', duties: [], events: [],
    });
    const d = { ...deps, google, config };
    const { event } = await calendarWrite(d, caller('editor'), {
      churchId: 'C1',
      op: 'upsert',
      event: { id: 'e1', title: '同工會', start: '2026-10-16T19:00', end: '2026-10-16T21:30:00', allDay: false },
    });
    assert.deepEqual([sent[0].start, sent[0].end], ['2026-10-17T02:00:00.000Z', '2026-10-17T04:30:00.000Z']);
    assert.deepEqual([event!.start, event!.end], ['2026-10-16T19:00:00-07:00', '2026-10-16T21:30:00-07:00']);
    const r = (await db.doc('churches/C1/rosters/ev_e1').get()).data()!;
    assert.deepEqual([r.dateKey, r.endDateKey], ['2026-10-16', '2026-10-16']);
    // An older app sends an instant: as it is.
    await calendarWrite(d, caller('editor'), {
      churchId: 'C1',
      op: 'upsert',
      event: { id: 'e1', title: '同工會', start: '2026-10-17T02:00:00.000Z', end: '2026-10-17T04:30:00.000Z', allDay: false },
    });
    assert.equal(sent[1].start, '2026-10-17T02:00:00.000Z');
    await rejectsWith(
      calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'upsert', event: { title: 'x', start: '2026-02-30T19:00', end: '2026-02-30T20:00', allDay: false } }),
      'unknown',
    );
  });

  test('the calendars to pick from say their time zones', async () => {
    await church();
    const { google } = fakeGoogle();
    google.calendars = async () => [{ id: 'cal-1', name: '教會行事曆', primary: false, timeZone: 'America/Chicago' }];
    await connect(google);
    const { calendars } = await calendarList({ ...deps, google, config }, caller('pastor'), { churchId: 'C1' });
    assert.equal(calendars[0].timeZone, 'America/Chicago');
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
    f.revokeAll();
    const err = await rejectsWith(
      calendarEvents({ ...deps, google: f.google, config }, caller('staff'), { churchId: 'C1', month: '2026-11' }),
      'unknown',
    );
    assert.equal((err as { details: { detail: string } }).details.detail, 'reconnect');
    assert.equal((await db.doc('churches/C1/settings/calendar').get()).get('needsReconnect'), true);
  });
});

describe('an event roster’s days (testdata/event_days.json, which the app runs too)', () => {
  const data = JSON.parse(readFileSync(new URL('../../testdata/event_days.json', import.meta.url), 'utf8')) as {
    cases: { name: string; timeZone?: ChurchTimeZone; event: { start: string; end: string; allDay: boolean }; dateKey: string; endDateKey: string }[];
  };
  for (const c of data.cases) {
    test(c.name, () => {
      assert.deepEqual(eventRosterDays(c.event, c.timeZone ?? 'Asia/Taipei'), { dateKey: c.dateKey, endDateKey: c.endDateKey });
    });
  }
});

describe('an event’s roster follows its event', () => {
  const roster = (extra: Record<string, unknown> = {}) => ({
    kind: 'event',
    eventId: 'e1',
    title: '同工會',
    dateKey: '2026-10-10',
    endDateKey: '2026-10-10',
    duties: [{ role: '主持', people: ['美玉'], uids: { 美玉: 'mei' } }],
    events: [],
    ...extra,
  });

  test("a new title and days are copied to it, the days the church's; a calendar editor needs no roster rights", async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    await db.doc('churches/C1/rosters/ev_e1').set(roster());
    const d = { ...deps, google, config };
    await calendarWrite(d, caller('editor'), {
      churchId: 'C1',
      op: 'upsert',
      event: { id: 'e1', title: '同工會（改期）', start: '2026-10-16T23:00:00+08:00', end: '2026-10-17T01:00:00+08:00', allDay: false },
    });
    const r = (await db.doc('churches/C1/rosters/ev_e1').get()).data()!;
    assert.deepEqual([r.title, r.dateKey, r.endDateKey], ['同工會（改期）', '2026-10-16', '2026-10-17']);
    assert.deepEqual(r.duties, roster().duties, 'the people stay');
    assert.equal(r.movedBy, 'editor', 'so the trigger does not tell them of their own move');

    await calendarWrite(d, caller('editor'), {
      churchId: 'C1',
      op: 'upsert',
      event: { id: 'e1', title: '退修會', start: '2026-10-23', end: '2026-10-26', allDay: true },
    });
    const all = (await db.doc('churches/C1/rosters/ev_e1').get()).data()!;
    assert.deepEqual([all.dateKey, all.endDateKey], ['2026-10-23', '2026-10-25'], 'an all-day end is exclusive');
  });

  test('an event with no roster gets none', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    await calendarWrite({ ...deps, google, config }, caller('editor'), {
      churchId: 'C1',
      op: 'upsert',
      event: { id: 'e1', title: '同工會', start: '2026-10-10', end: '2026-10-11', allDay: true },
    });
    assert.equal((await db.doc('churches/C1/rosters/ev_e1').get()).exists, false);
  });

  test('deleting the event cancels its roster; undoing moves it onto the event made again', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    await db.doc('churches/C1/rosters/ev_e1').set(roster());
    const d = { ...deps, google, config };
    await calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'delete', eventId: 'e1', event: { start: '2026-10-10' } });
    await db.doc('churches/C1/rosters/ev_e1').update({ calendarId: 'cal-1' });
    const cancelled = await db.doc('churches/C1/rosters/ev_e1').get();
    assert.ok(cancelled.get('cancelledAt'), 'kept, cancelled');

    const { event } = await calendarWrite(d, caller('editor'), {
      churchId: 'C1',
      op: 'upsert',
      event: { title: '同工會', start: '2026-10-10', end: '2026-10-11', allDay: true },
      restoreRosterOf: 'e1',
    });
    assert.equal(event?.id, 'new-1');
    assert.equal((await db.doc('churches/C1/rosters/ev_e1').get()).exists, false);
    const back = (await db.doc('churches/C1/rosters/ev_new-1').get()).data()!;
    assert.deepEqual(
      [back.kind, back.eventId, back.title, back.dateKey, back.via, back.cancelledAt],
      ['event', 'new-1', '同工會', '2026-10-10', 'restore', undefined],
    );
    assert.deepEqual(back.duties, roster().duties);
    assert.equal(back.calendarId, 'cal-1', 'where it is, kept');
  });

  test('undo only moves a cancelled roster of the same church', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    await db.doc('churches/C1/rosters/ev_live').set(roster({ eventId: 'live' }));
    await db.doc('churches/C2/rosters/ev_other').set(roster({ eventId: 'other', cancelledAt: new Date() }));
    const d = { ...deps, google, config };
    const event = { title: 'x', start: '2026-10-10', end: '2026-10-11', allDay: true };
    await calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'upsert', event, restoreRosterOf: 'live' });
    await calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'upsert', event, restoreRosterOf: 'other' });
    await calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'upsert', event, restoreRosterOf: '../x' });
    assert.equal((await db.doc('churches/C1/rosters/ev_live').get()).exists, true);
    assert.equal((await db.doc('churches/C2/rosters/ev_other').get()).exists, true);
    assert.equal((await db.doc('churches/C1/rosters/ev_new-1').get()).exists, false);
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
    assert.equal(r.event?.id, 'new-1');
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
    assert.deepEqual(calls.revoked, ['refresh-good']);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
    assert.equal((await db.doc('churches/C1/settings/calendar').get()).exists, false);
  });
});

describe('releasing the grant', () => {
  test('when the admin who connected it leaves, the grant is revoked; another admin leaving changes nothing', async () => {
    await church();
    await db.doc('churches/C1/members/editor').update({ role: 'admin' });
    const { google, calls } = fakeGoogle();
    await connect(google);
    const d = { ...deps, google, config };
    assert.equal(await releaseCalendarIfConnector(d, 'C1', 'editor'), false);
    assert.equal(await releaseCalendarIfConnector(d, 'C1', 'pastor'), true);
    assert.deepEqual(calls.revoked, ['refresh-good']);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
  });

  test('a reconnect while old-grant revocation waits is not deleted by the earlier disconnect', async () => {
    await church();
    const { google, calls } = fakeGoogle();
    await connect(google);
    let entered!: () => void;
    let release!: () => void;
    const revoking = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    google.revoke = async (token) => { calls.revoked.push(token); entered(); await gate; };
    const d = { ...deps, google, config };
    const disconnecting = calendarDisconnect(d, caller('pastor'), { churchId: 'C1' });
    await revoking;
    google.exchangeCode = async () => ({ refreshToken: 'new-refresh' });
    const { url } = await calendarAuthUrl(d, caller('pastor'), { churchId: 'C1' });
    assert.match(await calendarCallback(d, { state: new URL(url).searchParams.get('state'), code: 'new' }), /result=connected/);
    release();
    await disconnecting;
    const token = await db.doc('calendarTokens/C1').get();
    assert.equal(token.exists, true, 'the newer grant remains installed');
    assert.equal(unseal(token.get('token'), config.tokenKey), 'new-refresh');
    assert.equal((await db.doc('churches/C1/settings/calendar').get()).get('connected'), true);
    assert.deepEqual(calls.revoked, ['refresh-good']);
  });

  test("cache months are the church's, and a moved event clears both months", async () => {
    assert.equal(monthOf('2026-10-31T17:00:00.000Z', 'Asia/Taipei'), '2026-11');
    assert.equal(monthOf('2026-10-31T17:00:00.000Z', 'America/Los_Angeles'), '2026-10');
    assert.equal(monthOf('2026-10-31T23:00', 'America/Los_Angeles'), '2026-10');
    assert.equal(monthOf('2026-10-31', 'Asia/Taipei'), '2026-10');
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

describe('the months an event is cached in', () => {
  test('one month, or each month it spans', () => {
    assert.deepEqual(monthsOf('2026-10-10', '2026-10-11', TPE), ['2026-10']);
    assert.deepEqual(monthsOf('2026-09-30', '2026-10-03', TPE), ['2026-09', '2026-10']);
    assert.deepEqual(monthsOf('2026-12-30', '2027-02-02', TPE), ['2026-12', '2027-01', '2027-02']);
  });

  test('an all-day event ending on the 1st (exclusive) is not in that month', () => {
    assert.deepEqual(monthsOf('2026-10-30', '2026-11-01', TPE), ['2026-10']);
  });

  test("a timed event crossing the church's midnight into a new month is in both", () => {
    // 22:00 on 10/31 to 01:00 on 11/1, Taipei.
    assert.deepEqual(monthsOf('2026-10-31T14:00:00Z', '2026-10-31T17:00:00Z', TPE), ['2026-10', '2026-11']);
    assert.deepEqual(monthsOf('2026-10-31T22:00:00+08:00', '2026-11-01T00:00:00+08:00', TPE), ['2026-10'], 'ends at midnight');
    assert.deepEqual(monthsOf('2026-10-31T22:00', '2026-11-01T01:00', 'America/New_York'), ['2026-10', '2026-11'], 'on its clock');
  });

  test('without a usable end, the start month', () => {
    assert.deepEqual(monthsOf('2026-10-10', undefined, TPE), ['2026-10']);
    assert.deepEqual(monthsOf('2026-10-10', 'soon', TPE), ['2026-10']);
    assert.deepEqual(monthsOf('2026-10-10', '2026-09-01', TPE), ['2026-10']);
  });
});

describe('writing clears every month an event was or is in', () => {
  async function cached() {
    for (const m of ['2026-09', '2026-10', '2026-11', '2026-12']) {
      await db.doc(`calendarCache/C1_${m}`).set({ cid: 'C1', month: m, events: [] });
    }
  }
  const left = async () =>
    (await db.collection('calendarCache').get()).docs.map((x) => x.get('month') as string).sort();

  test('editing an event spanning Sep 30–Oct 2 clears both months', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    await cached();
    await calendarWrite({ ...deps, google, config }, caller('pastor'), {
      churchId: 'C1',
      op: 'upsert',
      previous: { start: '2026-09-30', end: '2026-10-03' },
      event: { id: 'e1', title: '退修會', start: '2026-09-30', end: '2026-10-03', allDay: true },
    });
    assert.deepEqual(await left(), ['2026-11', '2026-12']);
  });

  test('moving a spanning event clears where it was and where it is', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    await cached();
    await calendarWrite({ ...deps, google, config }, caller('pastor'), {
      churchId: 'C1',
      op: 'upsert',
      previous: { start: '2026-09-30T20:00:00+08:00', end: '2026-10-01T02:00:00+08:00' },
      event: { id: 'e1', title: '守夜禱告', start: '2026-12-01T20:00:00+08:00', end: '2026-12-01T22:00:00+08:00', allDay: false },
    });
    assert.deepEqual(await left(), ['2026-11']);
  });

  test('deleting an event spanning Sep 30–Oct 2 clears both months', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    await cached();
    await calendarWrite({ ...deps, google, config }, caller('pastor'), {
      churchId: 'C1',
      op: 'delete',
      eventId: 'gone',
      event: { start: '2026-09-30', end: '2026-10-03' },
    });
    assert.deepEqual(await left(), ['2026-11', '2026-12']);
  });

  test('a delete also clears where Google says the event was', async () => {
    await church();
    const { google } = fakeGoogle();
    await connect(google);
    await cached();
    // e1 is 10/10 on Google; an older client sends no event at all.
    await calendarWrite({ ...deps, google, config }, caller('pastor'), { churchId: 'C1', op: 'delete', eventId: 'e1' });
    assert.deepEqual(await left(), ['2026-09', '2026-11', '2026-12']);
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
    await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK, events });
    await db.doc('churches/C1').update({ name: '恩典堂' });
    await db.doc('churches/C1/members/editor').update({ name: '林同工' });
    const sent = () => f.requests.map((r) => ({ event: r.headers['x-martha-event'], body: JSON.parse(r.body) }));
    return { d, sent };
  }

  test('created and updated, after Google has them, with the editor’s name', async () => {
    const { d, sent } = await withHook();
    const event = { title: '小組聚會', start: '2026-10-20T19:00:00+08:00', end: '2026-10-20T21:00:00+08:00', allDay: false, location: '2F' };
    await calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'upsert', event });
    await calendarWrite(d, caller('editor'), { churchId: 'C1', op: 'upsert', event: { ...event, id: 'new-1', title: '小組聚會（改時間）' } });
    assert.deepEqual(sent()[0], {
      event: 'calendar.created',
      body: {
        action: 'created',
        source: 'martha',
        churchId: 'C1',
        churchName: '恩典堂',
        timeZone: 'Asia/Taipei',
        id: 'new-1',
        title: '小組聚會',
        allDay: false,
        start: '2026-10-20T19:00:00+08:00',
        end: '2026-10-20T21:00:00+08:00',
        location: '2F',
        description: '',
        link: 'https://calendar.google.com/event?eid=new-1',
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
    await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK, events: { calendar: true } });
    const r = await calendarWrite(d, caller('pastor'), { churchId: 'C1', op: 'upsert', event: { title: 'x', start: '2026-10-10', end: '2026-10-11', allDay: true } });
    assert.equal(r.event!.id, 'new-1');
    assert.equal((await db.doc('churches/C1/settings/webhook').get()).get('lastDelivery.status'), 500);
  });

  test('a suspended church sends nothing', async () => {
    const { d, sent } = await withHook();
    await db.doc('churches/C1').update({ status: 'suspended' });
    await rejectsWith(
      calendarWrite(d, caller('pastor'), { churchId: 'C1', op: 'upsert', event: { title: 'x', start: '2026-10-10', end: '2026-10-11', allDay: true } }),
      'churchClosed',
    );
    assert.equal(await notify(d, 'C1', 'calendar.created', {}), null);
    assert.equal(sent().length, 0);
  });
});
