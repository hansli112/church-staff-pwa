import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { purgeDeletedChurches } from '../src/church.js';
import { diffDuties, onRosterWritten } from '../src/rosterChange.js';
import { sendQueued, webhookSave, type WebhookDeps } from '../src/webhook.js';
import { caller, clearFirestore, db, deps, fakeFetch, purgeDeps, seedChurch, setNow } from './support.js';

const HOOK = 'https://n8n.example/roster';
const key = randomBytes(32).toString('base64');
const appUrl = 'https://app.example';

let f: ReturnType<typeof fakeFetch>;
let d: WebhookDeps;
let pushed: { tokens: string[]; body: string; link?: string }[];
/** Set to make every push fail like FCM out of reach. */
let fcmDown = false;

const messaging = {
  sendEachForMulticast: async (m: { tokens: string[]; notification: { body: string }; data?: { link?: string } }) => {
    if (fcmDown) throw new Error('fcm unreachable');
    pushed.push({ tokens: m.tokens, body: m.notification.body, link: m.data?.link });
    return { successCount: m.tokens.length, failureCount: 0, responses: m.tokens.map(() => ({ success: true })) };
  },
} as never;

const triggerDeps = () => ({ ...d, messaging, appUrl });

/** 美玉 (mei) and 志豪 (hao) have accounts; 林同工 does not. */
async function church(cid = 'C1', events: { calendar: boolean; roster: boolean } | null = { calendar: false, roster: true }) {
  await seedChurch(cid, { pastor: 'admin', mei: 'staff', hao: 'staff' }, { name: '恩典堂' });
  await db.doc(`churches/${cid}/members/pastor`).update({ name: '王牧師' });
  await db.doc(`churches/${cid}/settings/services`).set({ services: [{ id: 'sunday', name: '主日崇拜' }], ids: ['sunday'] });
  await db.doc('users/mei').set({ fcm: { phone: 'tok-mei', tablet: 'tok-mei-2' } });
  await db.doc('users/hao').set({ fcm: { phone: 'tok-hao' } });
  if (events) await webhookSave(d, caller('pastor'), { churchId: cid, url: HOOK, events });
}

const UIDS: Record<string, string> = { 美玉: 'mei', 志豪: 'hao' };
const duty = (role: string, people: string[]) => ({
  role,
  people,
  uids: Object.fromEntries(people.filter((p) => UIDS[p]).map((p) => [p, UIDS[p]])),
});

let n = 0;
/** Writes a roster day and runs the trigger on it, as [editedBy]. */
async function write(
  cid: string,
  day: string,
  duties: ReturnType<typeof duty>[],
  opts: { via?: string; editedBy?: string } = {},
) {
  const ref = db.doc(`churches/${cid}/rosters/${day}_sunday`);
  const before = await ref.get();
  await ref.set({ type: 'sunday', dateKey: day, duties, ...(opts.via ? { via: opts.via } : {}) });
  return onRosterWritten(triggerDeps(), cid, before, await ref.get(), opts.editedBy ?? 'pastor', `ev${++n}`);
}

/** Writes (or with null deletes) event x1's roster and runs the trigger, as [editedBy]. */
async function writeEvent(
  cid: string,
  data: Record<string, unknown> | null,
  opts: { editedBy?: string | null } = {},
) {
  const ref = db.doc(`churches/${cid}/rosters/ev_x1`);
  const before = await ref.get();
  if (data) {
    await ref.set({ kind: 'event', eventId: 'x1', title: '聖誕晚會', dateKey: '2026-12-24', endDateKey: '2026-12-24', ...data });
  } else {
    await ref.delete();
  }
  const by = opts.editedBy === undefined ? 'pastor' : (opts.editedBy ?? undefined);
  return onRosterWritten(triggerDeps(), cid, before, await ref.get(), by, `ev${++n}`);
}

const queued = async (cid = 'C1') => (await db.collection(`webhookOutbox/${cid}/rosterChanges`).get()).docs.map((x) => x.data());
const bodies = () => f.requests.map((r) => JSON.parse(r.body));

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-03T19:00:00+08:00')); // Saturday evening
  f = fakeFetch({ [HOOK]: { status: 200 } });
  d = { ...deps, fetch: f.fetch, secretKey: key };
  pushed = [];
  fcmDown = false;
});

describe('reading a roster change', () => {
  test('who was put on and taken off which duty, by account and by name', () => {
    const c = diffDuties(
      [duty('司琴', ['美玉']), duty('招待', ['林同工'])],
      [duty('司琴', ['志豪']), duty('招待', ['美玉', '林同工']), duty('音控', ['林同工'])],
    );
    assert.deepEqual([...c.added], [['hao', ['司琴']], ['mei', ['招待']]]);
    assert.deepEqual([...c.removed], [['mei', ['司琴']]]);
    assert.deepEqual(c.duties, [
      { duty: '司琴', added: ['志豪'], removed: ['美玉'] },
      { duty: '招待', added: ['美玉'], removed: [] },
      { duty: '音控', added: ['林同工'], removed: [] },
    ]);
  });

  test('a uid whose name is no longer listed holds nothing', () => {
    const c = diffDuties([], [{ role: '司琴', people: [], uids: { 美玉: 'mei' } }]);
    assert.equal(c.added.size, 0);
    assert.deepEqual(c.duties, []);
  });

  test('nothing to tell: a past day, a closed church, or nobody moved', async () => {
    await church();
    assert.equal(await write('C1', '2026-09-27', [duty('司琴', ['美玉'])]), null, 'past day');
    await write('C1', '2026-10-04', [duty('司琴', ['美玉'])]);
    assert.equal(await write('C1', '2026-10-04', [duty('司琴', ['美玉'])]), null, 'same people');
    await db.doc('churches/C1').update({ status: 'suspended' });
    assert.equal(await write('C1', '2026-10-11', [duty('司琴', ['美玉'])]), null, 'suspended');
    assert.equal(pushed.length, 1);
    assert.equal((await queued()).length, 1);
  });
});

describe('push', () => {
  test('both of a member’s devices hear about it; the editor does not', async () => {
    await church();
    const r = await write('C1', '2026-10-04', [duty('司琴', ['美玉']), duty('招待', ['志豪'])], { editedBy: 'hao' });
    assert.deepEqual(r, { push: 2, webhook: true });
    assert.equal(pushed.length, 1);
    assert.deepEqual(pushed[0].tokens, ['tok-mei', 'tok-mei-2']);
    assert.match(pushed[0].body, /10\/4 主日崇拜：司琴/);
  });

  test('taken off: told someone else has it now', async () => {
    await church();
    await write('C1', '2026-10-04', [duty('司琴', ['美玉'])]);
    await write('C1', '2026-10-04', [duty('司琴', ['志豪'])]);
    assert.equal(pushed.at(-1)!.body, '10/4 主日崇拜 的司琴已改由別人負責');
  });

  test('muted members get nothing', async () => {
    await church();
    await db.doc('churches/C1/members/mei').update({ 'notificationPrefs.muted': ['rosterChange'] });
    await write('C1', '2026-10-04', [duty('司琴', ['美玉'])]);
    assert.equal(pushed.length, 0);
  });
});

describe('imports', () => {
  test('an imported day sends no push but is queued for the webhook, marked imported', async () => {
    await church();
    const r = await write('C1', '2026-10-04', [duty('司琴', ['美玉'])], { via: 'import' });
    assert.deepEqual(r, { push: 0, webhook: true });
    assert.equal(pushed.length, 0);
    assert.equal((await queued())[0].via, 'import');
  });

  test('deleting a day as it was imported (undoing the import) sends no push either', async () => {
    await church();
    await write('C1', '2026-10-04', [duty('司琴', ['美玉'])], { via: 'import' });
    const ref = db.doc('churches/C1/rosters/2026-10-04_sunday');
    const before = await ref.get();
    await ref.delete();
    const r = await onRosterWritten(triggerDeps(), 'C1', before, await ref.get(), 'pastor', 'undo');
    assert.deepEqual(r, { push: 0, webhook: true });
    assert.equal(pushed.length, 0);
    assert.deepEqual((await queued()).map((q) => q.via), ['import', 'import']);
  });

  test('deleting a day someone edited by hand tells the people taken off', async () => {
    await church();
    await write('C1', '2026-10-04', [duty('司琴', ['美玉'])]);
    const ref = db.doc('churches/C1/rosters/2026-10-04_sunday');
    const before = await ref.get();
    await ref.delete();
    await onRosterWritten(triggerDeps(), 'C1', before, await ref.get(), 'pastor', 'del');
    assert.equal(pushed.length, 2, 'once for being put on, once for being taken off');
  });

  test('a whole import is one webhook notice', async () => {
    await church();
    for (let day = 4; day <= 25; day += 7) {
      await write('C1', `2026-10-${String(day).padStart(2, '0')}`, [duty('司會', ['王牧師'])], { via: 'import' });
    }
    await sendQueued(d);
    assert.equal(f.requests.length, 1);
    assert.equal(bodies()[0].count, 4);
    assert.equal(bodies()[0].imported, true);
  });
});

describe('push and webhook are independent', () => {
  test('push fails: the webhook entry is still queued, and the trigger fails', async () => {
    await church();
    fcmDown = true;
    await assert.rejects(write('C1', '2026-10-04', [duty('司琴', ['美玉'])]), /fcm unreachable/);
    assert.equal((await queued()).length, 1);
  });

  test('webhook outbox unreachable: the push still goes out', async () => {
    await church();
    const ref = db.doc('churches/C1/rosters/2026-10-04_sunday');
    await ref.set({ type: 'sunday', dateKey: '2026-10-04', duties: [duty('司琴', ['美玉'])] });
    // An event id Firestore refuses as a document ID.
    await assert.rejects(onRosterWritten(triggerDeps(), 'C1', undefined, await ref.get(), 'pastor', '__bad__'));
    assert.equal(pushed.length, 1);
  });

  test('roster notices off: the push goes out, nothing is queued', async () => {
    await church('C1', { calendar: true, roster: false });
    assert.deepEqual(await write('C1', '2026-10-04', [duty('司琴', ['美玉'])]), { push: 2, webhook: false });
  });

  test('someone without an account moved: no push, but the webhook hears it', async () => {
    await church();
    assert.deepEqual(await write('C1', '2026-10-04', [duty('音控', ['林同工'])]), { push: 0, webhook: true });
  });
});

describe('an event’s roster', () => {
  test('put on or taken off: told by the event’s title, and the link opens it', async () => {
    await church();
    await writeEvent('C1', { duties: [duty('主持', ['美玉'])] });
    await writeEvent('C1', { duties: [duty('主持', ['志豪'])] });
    assert.deepEqual(
      pushed.map((p) => [p.body, p.link]),
      [
        ['你被排進 12/24 聖誕晚會：主持', '/c/C1?to=%2Frosters%2Fevent%2Fx1'],
        ['你被排進 12/24 聖誕晚會：主持', '/c/C1?to=%2Frosters%2Fevent%2Fx1'],
        ['12/24 聖誕晚會 的主持已改由別人負責', '/c/C1?to=%2Frosters%2Fevent%2Fx1'],
      ],
    );
  });

  test('moved to another day: everyone on it is told the new date, by nobody in particular', async () => {
    await church();
    await writeEvent('C1', { duties: [duty('主持', ['美玉']), duty('招待', ['志豪', '林同工'])] });
    pushed = [];
    // calendarWrite moves it as the backend, naming who moved it: 美玉 is not told.
    await writeEvent(
      'C1',
      { dateKey: '2026-12-23', endDateKey: '2026-12-23', movedBy: 'mei', duties: [duty('主持', ['美玉']), duty('招待', ['志豪', '林同工'])] },
      { editedBy: null },
    );
    assert.deepEqual(pushed.map((p) => [p.tokens, p.body]), [[['tok-hao'], '聖誕晚會改到 12/23（週三）']]);
  });

  test('cancelled with its event, or later purged, it tells nobody; deleted by an editor, as any day', async () => {
    await church();
    await writeEvent('C1', { duties: [duty('主持', ['美玉'])] });
    pushed = [];
    await writeEvent('C1', { duties: [duty('主持', ['美玉'])], cancelledAt: Timestamp.now() }, { editedBy: null });
    await writeEvent('C1', null, { editedBy: null });
    assert.equal(pushed.length, 0);
    await writeEvent('C1', { duties: [duty('主持', ['美玉'])] });
    pushed = [];
    await writeEvent('C1', null);
    assert.deepEqual(pushed.map((p) => p.body), ['12/24 聖誕晚會 的主持已改由別人負責']);
  });

  test('put back by undoing a delete (via restore): no push, no webhook', async () => {
    await church();
    assert.equal(await writeEvent('C1', { duties: [duty('主持', ['美玉'])], via: 'restore' }, { editedBy: null }), null);
    assert.equal(pushed.length, 0);
    assert.equal((await queued()).length, 0);
  });

  test('a two-day event started yesterday is still news; one that ended is not', async () => {
    await church();
    setNow(new Date('2026-12-25T10:00:00+08:00'));
    await writeEvent('C1', { endDateKey: '2026-12-25', duties: [duty('主持', ['美玉'])] });
    assert.equal(pushed.length, 1);
    setNow(new Date('2026-12-26T10:00:00+08:00'));
    assert.equal(await writeEvent('C1', { endDateKey: '2026-12-25', duties: [duty('主持', ['志豪'])] }), null);
  });

  test('the webhook names the event, with no service', async () => {
    await church();
    await writeEvent('C1', { duties: [duty('主持', ['美玉'])] });
    await sendQueued(d);
    assert.deepEqual(bodies()[0].changes[0], {
      date: '2026-12-24',
      serviceId: null,
      serviceName: '聖誕晚會',
      eventId: 'x1',
      title: '聖誕晚會',
      duties: [{ duty: '主持', added: ['美玉'], removed: [] }],
      actorUid: 'pastor',
      actorName: '王牧師',
      via: 'app',
    });
  });
});

describe('roster webhooks', () => {
  test('changes within the window go out as one notice, then the outbox is empty', async () => {
    await church();
    await write('C1', '2026-10-04', [duty('司琴', ['美玉'])]);
    await write('C1', '2026-10-04', [duty('司琴', ['志豪'])]);
    await write('C1', '2026-10-11', [duty('招待', ['美玉', '志豪'])]);
    assert.equal(await sendQueued(d), 1);
    assert.equal(f.requests.length, 1);
    assert.equal(f.requests[0].headers['x-martha-event'], 'roster.changed');
    const body = bodies()[0];
    assert.deepEqual(Object.keys(body), [
      'action', 'source', 'churchId', 'churchName', 'timeZone', 'count', 'imported', 'changes', 'more',
    ]);
    assert.equal(body.action, 'changed');
    assert.equal(body.source, 'martha');
    assert.equal(body.churchId, 'C1');
    assert.equal(body.churchName, '恩典堂');
    assert.equal(body.timeZone, 'Asia/Taipei');
    assert.equal(body.count, 3);
    assert.equal(body.imported, false);
    assert.equal(body.more, 0);
    assert.deepEqual(body.changes[1], {
      date: '2026-10-04',
      serviceId: 'sunday',
      serviceName: '主日崇拜',
      eventId: null,
      title: null,
      duties: [{ duty: '司琴', added: ['志豪'], removed: ['美玉'] }],
      actorUid: 'pastor',
      actorName: '王牧師',
      via: 'app',
    });
    assert.equal((await queued()).length, 0);
    assert.equal(await sendQueued(d), 0, 'nothing left to send');
  });

  test('each church gets its own single notice', async () => {
    await church('C1');
    await church('C2');
    await write('C1', '2026-10-04', [duty('司琴', ['甲'])]);
    await write('C2', '2026-10-04', [duty('司琴', ['乙'])]);
    await write('C2', '2026-10-11', [duty('司琴', ['丙'])]);
    assert.equal(await sendQueued(d), 2);
    const byChurch = Object.fromEntries(bodies().map((b) => [b.churchId, b.count]));
    assert.deepEqual(byChurch, { C1: 1, C2: 2 });
  });

  test('a church suspended after queueing sends nothing and its outbox is dropped', async () => {
    await church();
    await write('C1', '2026-10-04', [duty('司琴', ['甲'])]);
    await db.doc('churches/C1').update({ status: 'suspended' });
    assert.equal(await sendQueued(d), 0);
    assert.equal(f.requests.length, 0);
    assert.equal((await queued()).length, 0);
  });

  test('purging a church clears its outbox', async () => {
    await church('Old');
    await write('Old', '2026-10-04', [duty('司琴', ['甲'])]);
    await db.doc('churches/Old').update({ status: 'deleted', deletedAt: Timestamp.fromDate(new Date('2026-08-01T00:00:00Z')) });
    await purgeDeletedChurches(purgeDeps);
    assert.equal((await queued('Old')).length, 0);
  });
});
