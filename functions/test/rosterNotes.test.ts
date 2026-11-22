import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { getStorage } from 'firebase-admin/storage';

import { forgetOldRosterNotes, onRosterNoteWritten, saveRosterNote, type NoteDeps } from '../src/rosterNotes.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch, setNow } from './support.js';

const bucket = getStorage().bucket('demo-martha.appspot.com');
const d: NoteDeps = { ...deps, bucket };

const ROSTER = '2026-11-22_sunday';
const urlOf = (path: string, site = 'https://firebasestorage.googleapis.com') =>
  `${site}/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=t`;

async function upload(rosterId: string, id: string, type = 'application/pdf', bytes = 3) {
  const path = `churches/C1/rosterNotes/${rosterId}/${id}`;
  await bucket.file(path).save(Buffer.alloc(bytes), { contentType: type });
  return { id, name: `${id}.pdf`, url: urlOf(path) };
}

const exists = async (rosterId: string, id: string) => (await bucket.file(`churches/C1/rosterNotes/${rosterId}/${id}`).exists())[0];

beforeEach(async () => {
  await clearFirestore();
  await bucket.deleteFiles({ prefix: 'churches/' });
  setNow(new Date('2026-11-20T10:00:00+08:00'));
  // 陳負責人 leads 主日崇拜; 美玉 leads 敬拜事工, linked to its 司琴; 志豪 serves.
  await seedChurch('C1', { lead: 'staff', mei: 'staff', hao: 'staff', admin: 'admin' }, { name: '恩典堂' });
  await db.doc('churches/C1/settings/services').set({ services: [], ids: ['sunday', 'youth'] });
  await db.doc('churches/C1/settings/ministries').set({
    ministries: [{ id: 'worship', name: '敬拜', duties: [{ service: 'sunday', duty: '司琴' }] }],
    ids: ['worship'],
  });
  await db.doc('churches/C1/members/lead').update({ leadTypes: ['sunday'] });
  await db.doc('churches/C1/members/mei').update({ leadMinistries: ['worship'] });
});

describe('備註 (saveRosterNote)', () => {
  test('keeps the text and the files uploaded for it, their size and type from Storage', async () => {
    const pdf = await upload(ROSTER, 'f1', 'application/pdf', 5);
    await saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: '歌單：奇異恩典', files: [pdf] });
    const note = await db.doc(`churches/C1/rosterNotes/${ROSTER}`).get();
    assert.equal(note.get('text'), '歌單：奇異恩典');
    assert.equal(note.get('dateKey'), '2026-11-22');
    assert.equal(note.get('by'), 'lead');
    assert.deepEqual(note.get('files'), [{ ...pdf, type: 'application/pdf', size: 5 }]);
  });

  test("a 事工's 負責人 writes it on a day of a service they arrange in; others do not", async () => {
    await saveRosterNote(d, caller('mei'), { churchId: 'C1', rosterId: ROSTER, text: '7:30 到', files: [] });
    await rejectsWith(saveRosterNote(d, caller('mei'), { churchId: 'C1', rosterId: '2026-11-22_youth', text: 'x', files: [] }), 'permissionDenied');
    await rejectsWith(saveRosterNote(d, caller('hao'), { churchId: 'C1', rosterId: ROSTER, text: 'x', files: [] }), 'permissionDenied');
    await rejectsWith(saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: '2026-11-22_youth', text: 'x', files: [] }), 'permissionDenied');
  });

  test("an event's roster: who arranges it, and its last day", async () => {
    await db.doc('churches/C1/rosters/ev_e1').set({ kind: 'event', eventId: 'e1', title: '退修會', dateKey: '2026-12-01', endDateKey: '2026-12-03', duties: [], group: 'service:sunday' });
    await saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: 'ev_e1', text: '帶睡袋', files: [] });
    assert.equal((await db.doc('churches/C1/rosterNotes/ev_e1').get()).get('dateKey'), '2026-12-03');
    await rejectsWith(saveRosterNote(d, caller('hao'), { churchId: 'C1', rosterId: 'ev_e1', text: 'x', files: [] }), 'permissionDenied');
    await rejectsWith(saveRosterNote(d, caller('admin'), { churchId: 'C1', rosterId: 'ev_none', text: 'x', files: [] }), 'permissionDenied');
  });

  test('nothing in it deletes it', async () => {
    await saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: 'x', files: [] });
    await saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: ' ', files: [] });
    assert.equal((await db.doc(`churches/C1/rosterNotes/${ROSTER}`).get()).exists, false);
  });

  test('refuses files not uploaded for this roster, too many, and too much text', async () => {
    const save = (files: unknown[], text = '') => saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text, files });
    const other = await upload('2026-11-29_sunday', 'f9');
    await rejectsWith(save([{ ...other, url: urlOf(`churches/C1/rosterNotes/${ROSTER}/f9`) }]), 'unknown');
    await rejectsWith(save([other]), 'unknown');
    const six = await Promise.all(['a', 'b', 'c', 'd', 'e', 'f'].map((id) => upload(ROSTER, id)));
    await rejectsWith(save(six), 'unknown');
    await rejectsWith(save([six[0], six[0]]), 'unknown');
    await rejectsWith(save([], 'x'.repeat(501)), 'unknown');
    await save(six.slice(0, 5), 'x'.repeat(500));
  });

  test('refuses a file Storage has over 20 MB, and one with no type', async () => {
    const save = (files: unknown[]) => saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: '', files });
    const big = await upload(ROSTER, 'big', 'application/pdf', 20 * 1024 * 1024 + 1);
    await rejectsWith(save([big]), 'unknown');
    const path = `churches/C1/rosterNotes/${ROSTER}/bare`;
    await bucket.file(path).save(Buffer.alloc(3));
    await bucket.file(path).setMetadata({ contentType: null });
    await rejectsWith(save([{ id: 'bare', name: 'bare', url: urlOf(path) }]), 'unknown');
    await rejectsWith(saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: 'x', files: [], by: 'mei' }), 'unknown');
  });

  test("a file's address is Storage's own, not another site's", async () => {
    const pdf = await upload(ROSTER, 'f1');
    const path = `churches/C1/rosterNotes/${ROSTER}/f1`;
    const save = (url: string) => saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: '', files: [{ ...pdf, url }] });
    await rejectsWith(save(urlOf(path, 'https://evil.example')), 'unknown');
    await rejectsWith(save(`https://evil.example/x?u=/o/${encodeURIComponent(path)}?`), 'unknown');
    await rejectsWith(save('not a url'), 'unknown');
    // The emulator's, by the name the app reached it.
    await save(urlOf(path, `http://localhost:${process.env.FIREBASE_STORAGE_EMULATOR_HOST!.split(':').pop()}`));
    // Storage's own, for a file not on the note yet.
    const other = await upload(ROSTER, 'f2');
    await saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: '', files: [other] });
  });

  test('a day gone is not changed', async () => {
    await rejectsWith(saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: '2026-11-15_sunday', text: 'x', files: [] }), 'unknown');
    // Yesterday, somewhere it is still the day.
    await saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: '2026-11-19_sunday', text: 'x', files: [] });
  });

  test("an event's cancelled roster takes no note", async () => {
    await db.doc('churches/C1/rosters/ev_e2').set({ kind: 'event', eventId: 'e2', title: '退修會', dateKey: '2026-12-01', endDateKey: '2026-12-01', duties: [], group: 'service:sunday', cancelledAt: '2026-11-19' });
    await rejectsWith(saveRosterNote(d, caller('admin'), { churchId: 'C1', rosterId: 'ev_e2', text: 'x', files: [] }), 'permissionDenied');
  });

  test('any kind of file: a Word file is kept as it is', async () => {
    const docx = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    const word = await upload(ROSTER, 'w1', docx);
    await saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: '', files: [word] });
    assert.equal((await db.doc(`churches/C1/rosterNotes/${ROSTER}`).get()).get('files')[0].type, docx);
  });

  test('a file kept keeps what was read of it; its name may change', async () => {
    const pdf = await upload(ROSTER, 'f1', 'application/pdf', 5);
    await saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: '', files: [pdf] });
    await bucket.file(`churches/C1/rosterNotes/${ROSTER}/f1`).delete();
    await saveRosterNote(d, caller('lead'), { churchId: 'C1', rosterId: ROSTER, text: '', files: [{ ...pdf, name: '恩典.pdf' }] });
    const [file] = (await db.doc(`churches/C1/rosterNotes/${ROSTER}`).get()).get('files');
    assert.deepEqual([file.name, file.size, file.type], ['恩典.pdf', 5, 'application/pdf']);
  });
});

describe('備註的檔案', () => {
  test('a file taken off is deleted; all of them when the note is', async () => {
    const [a, b] = [await upload(ROSTER, 'a'), await upload(ROSTER, 'b')];
    await onRosterNoteWritten(d, 'C1', ROSTER, { files: [a, b] }, { files: [b] });
    assert.deepEqual([await exists(ROSTER, 'a'), await exists(ROSTER, 'b')], [false, true]);
    await onRosterNoteWritten(d, 'C1', ROSTER, { files: [b] }, null);
    assert.equal(await exists(ROSTER, 'b'), false);
  });

  test('a note goes 30 days after its last day, with its files; so do files picked but not kept', async () => {
    const kept = await upload('2026-10-19_sunday', 'old');
    await db.doc('churches/C1/rosterNotes/2026-10-19_sunday').set({ text: 'x', files: [kept], dateKey: '2026-10-19' });
    await db.doc('churches/C1/rosterNotes/2026-10-22_sunday').set({ text: 'y', files: [], dateKey: '2026-10-22' });
    const keep = await upload(ROSTER, 'keep');
    await db.doc(`churches/C1/rosterNotes/${ROSTER}`).set({ text: 'z', files: [keep], dateKey: '2026-11-22' });
    await upload(ROSTER, 'dropped');
    setNow(new Date('2026-11-21T10:00:00+08:00'));
    assert.equal(await forgetOldRosterNotes(d), 1);
    assert.equal((await db.doc('churches/C1/rosterNotes/2026-10-19_sunday').get()).exists, false);
    assert.equal((await db.doc('churches/C1/rosterNotes/2026-10-22_sunday').get()).exists, true);
    assert.equal(await exists('2026-10-19_sunday', 'old'), false);
    // Uploaded just now: a day later, as nobody kept it, it goes.
    assert.deepEqual([await exists(ROSTER, 'keep'), await exists(ROSTER, 'dropped')], [true, true]);
    // A day after the upload, which the emulator times by the real clock.
    setNow(new Date(Date.now() + 25 * 60 * 60 * 1000));
    await forgetOldRosterNotes(d);
    assert.deepEqual([await exists(ROSTER, 'keep'), await exists(ROSTER, 'dropped')], [true, false]);
  });

  test("an event moved later keeps its note until its new last day", async () => {
    await db.doc('churches/C1/rosters/ev_e1').set({ kind: 'event', eventId: 'e1', title: '退修會', dateKey: '2027-02-15', endDateKey: '2027-02-15', duties: [], group: 'service:sunday' });
    await db.doc('churches/C1/rosterNotes/ev_e1').set({ text: '帶睡袋', files: [], dateKey: '2026-10-01' });
    await db.doc('churches/C1/rosterNotes/ev_gone').set({ text: 'x', files: [], dateKey: '2026-10-01' });
    assert.equal(await forgetOldRosterNotes(d), 1);
    assert.equal((await db.doc('churches/C1/rosterNotes/ev_e1').get()).get('dateKey'), '2027-02-15');
    assert.equal((await db.doc('churches/C1/rosterNotes/ev_gone').get()).exists, false);
  });
});
