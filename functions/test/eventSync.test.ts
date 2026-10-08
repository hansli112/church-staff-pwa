import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { beforeEach, describe, test } from 'node:test';

import {
  calendarAuthUrl,
  calendarCallback,
  calendarSelect,
  GoogleAuthRevoked,
  type CalendarEvent,
  type GoogleApi,
  type OAuthConfig,
} from '../src/calendar.js';
import { syncEventRosters } from '../src/eventSync.js';
import { caller, clearFirestore, db, deps as plain, seedChurch, setNow } from './support.js';

const config: OAuthConfig = {
  clientId: 'client',
  clientSecret: 'secret',
  redirectUri: 'https://fn/calendarCallback',
  appUrl: 'https://app.example',
  tokenKey: randomBytes(32).toString('base64'),
};

/** A calendar with [events]; a get of a deleted one says cancelled, of a purged one nothing. */
function fakeGoogle(events: CalendarEvent[]) {
  const calls = { get: 0, events: 0 };
  let down = false;
  let revoked = false;
  let unshared = false;
  const google: GoogleApi = {
    exchangeCode: async () => ({ refreshToken: 'refresh-123' }),
    accessToken: async () => {
      if (revoked) throw new GoogleAuthRevoked();
      if (down) throw new Error('google unreachable');
      return 'access';
    },
    calendars: async () => [{ id: 'cal-1', name: '教會行事曆', primary: false }],
    events: async () => {
      calls.events++;
      if (unshared) throw new Error('google 404: calendar not found');
      return events.filter((e) => !e.cancelled);
    },
    upsert: async (_t, _c, e) => e,
    get: async (_t, _c, id) => {
      calls.get++;
      return unshared ? null : (events.find((e) => e.id === id) ?? null);
    },
    remove: async () => {},
    revoke: async () => {},
  };
  return {
    google,
    calls,
    events,
    goDown: () => (down = true),
    revoke: () => (revoked = true),
    unshare: () => (unshared = true),
  };
}

const d = (google: GoogleApi) => ({ ...plain, secretKey: config.tokenKey, google, config });

async function connect(google: GoogleApi, calendarId = 'cal-1') {
  const { url } = await calendarAuthUrl(d(google), caller('pastor'), { churchId: 'C1' });
  await calendarCallback(d(google), { state: new URL(url).searchParams.get('state')!, code: 'good' });
  await calendarSelect(d(google), caller('pastor'), { churchId: 'C1', calendarId, calendarName: '教會行事曆' });
}

/** Event [id]'s roster; an [extra] field set to undefined is left out. */
const roster = (id: string, extra: Record<string, unknown> = {}) =>
  db.doc(`churches/C1/rosters/ev_${id}`).set(
    Object.fromEntries(
      Object.entries({
        kind: 'event',
        eventId: id,
        title: '聖誕晚會',
        dateKey: '2026-12-24',
        endDateKey: '2026-12-24',
        calendarId: 'cal-1',
        duties: [{ role: '主持', people: ['美玉'], uids: { 美玉: 'mei' } }],
        events: [],
        ...extra,
      }).filter(([, v]) => v !== undefined),
    ),
  );
const get = async (id: string) => (await db.doc(`churches/C1/rosters/ev_${id}`).get()).data();

const party: CalendarEvent = { id: 'x1', title: '聖誕晚會', start: '2026-12-24T11:00:00.000Z', end: '2026-12-24T13:00:00.000Z', allDay: false };

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-12-01T18:30:00+08:00'));
  await seedChurch('C1', { pastor: 'admin', mei: 'staff' });
});

describe('syncing events’ rosters with Google Calendar', () => {
  test('a title or day changed in Google is copied; an unchanged one is left alone', async () => {
    const g = fakeGoogle([{ ...party, title: '聖誕感恩晚會', start: '2026-12-23T11:00:00.000Z', end: '2026-12-23T13:00:00.000Z' }]);
    await connect(g.google);
    await roster('x1');
    const first = await syncEventRosters(d(g.google));
    assert.equal(first.updated, 1);
    const r = (await get('x1'))!;
    assert.deepEqual([r.title, r.dateKey, r.endDateKey, r.via], ['聖誕感恩晚會', '2026-12-23', '2026-12-23', 'calendar']);
    assert.equal((await syncEventRosters(d(g.google))).updated, 0);
  });

  test('deleted in Google: cancelled; back from the trash within 30 days: on again; after 30 days: gone', async () => {
    const g = fakeGoogle([{ ...party, cancelled: true }]);
    await connect(g.google);
    await roster('x1');
    assert.equal((await syncEventRosters(d(g.google))).cancelled, 1);
    assert.ok((await get('x1'))!.cancelledAt);

    g.events[0] = party;
    assert.equal((await syncEventRosters(d(g.google))).restored, 1);
    const back = (await get('x1'))!;
    assert.equal(back.cancelledAt, undefined);
    assert.equal(back.via, 'restore', 'quiet, as it went');

    g.events.length = 0;
    await syncEventRosters(d(g.google));
    assert.ok((await get('x1'))!.cancelledAt, 'purged from Google: cancelled again');
    setNow(new Date('2027-01-05T18:30:00+08:00'));
    assert.equal((await syncEventRosters(d(g.google))).purged, 1);
    assert.equal(await get('x1'), undefined);
  });

  test('another calendar picked, or a roster from before calendars were recorded: never taken for deleted', async () => {
    const g = fakeGoogle([]);
    await connect(g.google, 'cal-2');
    await roster('x1');
    await roster('x2', { calendarId: undefined });
    const counts = await syncEventRosters(d(g.google));
    assert.equal(counts.cancelled, 0);
    assert.equal((await get('x1'))!.cancelledAt, undefined);
    assert.equal((await get('x2'))!.cancelledAt, undefined);
  });

  test('Google out of reach, or not connected: nothing changes', async () => {
    const g = fakeGoogle([]);
    await roster('x1');
    assert.equal((await syncEventRosters(d(g.google))).cancelled, 0, 'not connected');
    await connect(g.google);
    g.goDown();
    assert.equal((await syncEventRosters(d(g.google))).cancelled, 0);
    assert.equal((await get('x1'))!.cancelledAt, undefined);
  });

  test('moved in Google after a move in the app: whoever moved it then is told this time', async () => {
    const g = fakeGoogle([{ ...party, start: '2026-12-23T11:00:00.000Z', end: '2026-12-23T13:00:00.000Z' }]);
    await connect(g.google);
    await roster('x1', { movedBy: 'mei' });
    await syncEventRosters(d(g.google));
    const r = (await get('x1'))!;
    assert.equal(r.dateKey, '2026-12-23');
    assert.equal(r.movedBy, undefined);
  });

  test('the grant revoked, or the calendar no longer shared with whoever connected it: never taken for deleted', async () => {
    const g = fakeGoogle([party]);
    await connect(g.google);
    await roster('x1');
    g.unshare();
    assert.equal((await syncEventRosters(d(g.google))).cancelled, 0);
    g.revoke();
    assert.equal((await syncEventRosters(d(g.google))).cancelled, 0);
    assert.equal((await get('x1'))!.cancelledAt, undefined);
    assert.equal((await db.doc('churches/C1/settings/calendar').get()).get('needsReconnect'), true);
  });

  test('the whole series moved a day later: the roster moves to the nearest day of it', async () => {
    const g = fakeGoogle([
      {
        id: 'pray_20261225T110000Z',
        title: '禱告會',
        start: '2026-12-25T11:00:00.000Z',
        end: '2026-12-25T12:00:00.000Z',
        allDay: false,
        recurringEventId: 'pray',
        originalStart: '2026-12-25T11:00:00.000Z',
      },
    ]);
    await connect(g.google);
    await roster('pray_20261224T110000Z', { title: '禱告會', recurringEventId: 'pray', originalStart: '2026-12-24T11:00:00.000Z' });
    assert.equal((await syncEventRosters(d(g.google))).relinked, 1);
    assert.equal((await get('pray_20261225T110000Z'))!.dateKey, '2026-12-25');
  });

  test('a recurring day under a new id ("this and following"): the roster moves to it', async () => {
    const g = fakeGoogle([
      {
        id: 'pray_R20261201_20261224T110000Z',
        title: '禱告會',
        start: '2026-12-24T11:30:00.000Z',
        end: '2026-12-24T13:00:00.000Z',
        allDay: false,
        recurringEventId: 'pray_R20261201',
        originalStart: '2026-12-24T11:30:00.000Z',
      },
    ]);
    await connect(g.google);
    await roster('pray_20261224T110000Z', {
      title: '禱告會',
      recurringEventId: 'pray',
      originalStart: '2026-12-24T11:00:00.000Z',
    });
    assert.equal((await syncEventRosters(d(g.google))).relinked, 1);
    assert.equal(await get('pray_20261224T110000Z'), undefined);
    const moved = (await get('pray_R20261201_20261224T110000Z'))!;
    assert.deepEqual(
      [moved.eventId, moved.recurringEventId, moved.duties[0].people],
      ['pray_R20261201_20261224T110000Z', 'pray_R20261201', ['美玉']],
    );
  });

  test('past rosters and services’ days are not read; a closed church is skipped', async () => {
    const g = fakeGoogle([party]);
    await connect(g.google);
    await roster('old', { dateKey: '2026-11-01', endDateKey: '2026-11-01' });
    await db.doc('churches/C1/rosters/2026-12-06_sunday').set({ type: 'sunday', dateKey: '2026-12-06' });
    assert.equal((await syncEventRosters(d(g.google))).checked, 0);
    await roster('x1');
    await db.doc('churches/C1').update({ status: 'suspended' });
    assert.equal((await syncEventRosters(d(g.google))).checked, 0);
    assert.equal(g.calls.get, 0);
  });
});

