import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import type { CalendarEvent } from '../src/calendar.js';
import {
  cancelGone,
  cancelWithEvent,
  followEdit,
  followGoogle,
  relinkTo,
  restoreOnto,
  takeTimeZone,
} from '../src/eventRosters.js';
import { readRosterChange } from '../src/rosterChange.js';
import type { ChurchTimeZone } from '../src/timeZones.js';
import { clearFirestore, db, deps, recordWrites, seedChurch, setNow } from './support.js';

const TPE: ChurchTimeZone = 'Asia/Taipei';
const party: CalendarEvent & { id: string } = {
  id: 'x1',
  title: '聖誕晚會',
  start: '2026-12-24T11:00:00.000Z',
  end: '2026-12-24T13:00:00.000Z',
  allDay: false,
  recurringEventId: 's1',
};
/** [e] a day earlier. */
const dayBefore = (e: CalendarEvent) => ({ ...e, start: '2026-12-23T11:00:00.000Z', end: '2026-12-23T13:00:00.000Z' });

const ref = (id = 'x1') => db.doc(`churches/C1/rosters/ev_${id}`);
const snap = (id = 'x1') => ref(id).get();

/**
 * Runs [change], then the roster trigger on each roster write it made, as
 * the backend (no signed-in writer): per write, null when nobody is told.
 */
async function told(change: () => Promise<unknown>) {
  const writes = (await recordWrites(change)).filter((w) => w.path.includes('/rosters/'));
  assert.ok(writes.length, 'wrote nothing');
  const out = [];
  for (const w of writes) {
    const c = await readRosterChange(deps, 'C1', w.before, w.after, undefined);
    out.push(c && { roster: w.path.split('/').pop(), movedFrom: c.movedFrom, editor: c.editor?.uid ?? null });
  }
  return out;
}

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-12-01T18:30:00+08:00'));
  await seedChurch('C1', { pastor: 'admin', mei: 'staff' });
  await ref().set({
    kind: 'event',
    eventId: 'x1',
    title: '聖誕晚會',
    dateKey: '2026-12-24',
    endDateKey: '2026-12-24',
    calendarId: 'cal-1',
    recurringEventId: 's1',
    duties: [{ role: '主持', people: ['美玉'], uids: { 美玉: 'mei' } }],
    events: [],
    via: 'app',
  });
});

describe("an event's roster, changed with its event, and who is told", () => {
  test('moved in the app: told, naming who moved it; a new title alone tells nothing', async () => {
    assert.deepEqual(await told(() => followEdit(deps, 'C1', TPE, dayBefore(party), 'pastor')), [
      { roster: 'ev_x1', movedFrom: '2026-12-24', editor: 'pastor' },
    ]);
    assert.deepEqual(await told(() => followEdit(deps, 'C1', TPE, { ...dayBefore(party), title: '聖誕感恩晚會' }, 'pastor')), [null]);
  });

  test('deleted in the app, or gone from Google: cancelled, and nobody told; nor of its purge', async () => {
    assert.deepEqual(await told(() => cancelWithEvent(deps, 'C1', 'x1')), [null]);
    assert.deepEqual(await told(() => ref().delete()), [null]);
    await ref('x2').set({ kind: 'event', eventId: 'x2', title: '退修會', dateKey: '2026-12-26', endDateKey: '2026-12-27', duties: [] });
    assert.deepEqual(await told(async () => cancelGone(deps, await snap('x2'))), [null]);
  });

  test('the delete undone: moved onto the event made again, and nobody told of either', async () => {
    await cancelWithEvent(deps, 'C1', 'x1');
    assert.deepEqual(await told(() => restoreOnto(deps, 'C1', TPE, 'x1', { ...party, id: 'x9' })), [null, null]);
    assert.equal((await snap()).exists, false);
    assert.equal((await snap('x9')).get('via'), 'restore');
  });

  test("back from Google's trash: on again quietly; moved in Google later: told", async () => {
    await cancelWithEvent(deps, 'C1', 'x1');
    assert.equal(await followGoogle(await snap(), party, 'cal-1', TPE), 'restored');
    await cancelWithEvent(deps, 'C1', 'x1');
    assert.deepEqual(await told(async () => followGoogle(await snap(), party, 'cal-1', TPE)), [null]);
    assert.deepEqual(await told(async () => followGoogle(await snap(), dayBefore(party), 'cal-1', TPE)), [
      { roster: 'ev_x1', movedFrom: '2026-12-24', editor: null },
    ]);
  });

  test('moved in the app, then in Google: whoever moved it in the app is told this time', async () => {
    await followEdit(deps, 'C1', TPE, dayBefore(party), 'pastor');
    assert.deepEqual(await told(async () => followGoogle(await snap(), party, 'cal-1', TPE)), [
      { roster: 'ev_x1', movedFrom: '2026-12-23', editor: null },
    ]);
    assert.equal(await followGoogle(await snap(), party, 'cal-1', TPE), null, 'nothing changed');
  });

  test("moved to its event's new id: neither the old one going nor the new one is told", async () => {
    const split = { ...party, id: 'x1_R20261224', recurringEventId: 's1_R20261224' };
    assert.deepEqual(await told(async () => assert.equal(await relinkTo(deps, await snap(), split, 'cal-1', TPE), true)), [
      null,
      null,
      null,
      null,
    ]);
    assert.equal((await snap()).exists, false);
    assert.equal((await snap(split.id)).get('eventId'), split.id);
  });

  test('moved to its event’s new id on another day (the series moved): the move is told', async () => {
    const moved = { ...dayBefore(party), id: 'x1_new' };
    const said = await told(() => snap().then((r) => relinkTo(deps, r, moved, 'cal-1', TPE)));
    assert.deepEqual(said.filter(Boolean), [{ roster: 'ev_x1_new', movedFrom: '2026-12-24', editor: null }]);
  });

  test("the church's new time zone: its days on the new clock, and nobody told", async () => {
    const early = { ...party, start: '2026-12-24T02:00:00.000Z', end: '2026-12-24T04:00:00.000Z' };
    assert.deepEqual(await told(async () => assert.equal(await takeTimeZone(await snap(), early, 'America/Los_Angeles'), true)), [null]);
    assert.equal((await snap()).get('dateKey'), '2026-12-23');
    assert.equal(await takeTimeZone(await snap(), early, 'America/Los_Angeles'), false, 'already there');
  });
});
