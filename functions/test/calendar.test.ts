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
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch, setNow } from './support.js';

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
    exchangeCode: async (code) => ({ refreshToken: code === 'good' ? 'refresh-123' : null }),
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
    upsert: async (_t, _c, e) => ({ ...e, id: e.id ?? 'new-id' }),
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
