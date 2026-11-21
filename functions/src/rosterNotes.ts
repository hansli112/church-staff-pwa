import type { Storage } from 'firebase-admin/storage';
import { FieldValue } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { DAY_MS, fail, record, type Caller, type Deps } from './common.js';
import { LIMITS, TEXT_LIMITS, withinTextLimit } from './limits.js';
import { ledDuties, ministriesOf } from './ministries.js';
import { groupOf } from './powers.js';

/**
 * 備註 of a day's roster: some text and up to LIMITS.noteFiles files of any
 * kind (樂譜, 練唱音檔, 投影片…), at churches/{cid}/rosterNotes/{rosterId}, the files in
 * Storage under [notePrefix]. Whoever arranges any of that roster writes
 * it, through [saveRosterNote]; everyone in the church reads it. It goes
 * LIMITS.noteDays after the roster's last day ([forgetOldRosterNotes]).
 */

export type NoteDeps = Deps & { bucket: Pick<ReturnType<Storage['bucket']>, 'file' | 'deleteFiles' | 'getFiles'> };

/** A file on a note, as the doc keeps it. */
export interface NoteFile {
  id: string;
  name: string;
  type: string;
  size: number;
  url: string;
}

const ROSTER_ID = /^(\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01]))_([A-Za-z0-9_-]{1,64})$/;
const EVENT_ROSTER_ID = /^ev_[A-Za-z0-9_-]{1,1024}$/;
const FILE_ID = /^[A-Za-z0-9_-]{1,64}$/;

/** A content type as Storage keeps one: any kind of file may be on a note. */
export const noteFileType = (type: unknown): type is string =>
  typeof type === 'string' && /^[\w.+-]+\/[\w.+-]+$/.test(type) && type.length <= 200;

/** Where the files of roster [rosterId]'s note are, each at its id. */
export const notePrefix = (cid: string, rosterId: string) => `churches/${cid}/rosterNotes/${rosterId}/`;

function filesOf(value: unknown): NoteFile[] {
  return Array.isArray(value) ? (value as NoteFile[]) : [];
}

/**
 * Keeps `data.text` and `data.files` as the 備註 of roster `data.rosterId`,
 * or deletes it when both are empty. A file already there is kept as it
 * was; a new one must have been uploaded under [notePrefix] (by its id),
 * and its size and type are read from Storage. `url` is its download URL.
 */
export async function saveRosterNote(deps: NoteDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'rosterId', 'text', 'files'].includes(k))) fail('invalid-argument', 'unknown');
  const { rosterId, text } = input;
  if (typeof rosterId !== 'string' || !(ROSTER_ID.test(rosterId) || EVENT_ROSTER_ID.test(rosterId))) {
    fail('invalid-argument', 'unknown');
  }
  if (typeof text !== 'string' || !withinTextLimit(text, TEXT_LIMITS.rosterNote)) fail('invalid-argument', 'unknown');
  if (!Array.isArray(input.files) || input.files.length > LIMITS.noteFiles) fail('invalid-argument', 'unknown');
  const asked = input.files.map((f) => record(f));
  const ids = asked.map((f) => f.id);
  if (ids.some((id) => typeof id !== 'string' || !FILE_ID.test(id)) || new Set(ids).size !== ids.length) {
    fail('invalid-argument', 'unknown');
  }
  for (const f of asked) {
    if (typeof f.name !== 'string' || f.name.trim() === '' || f.name.length > LIMITS.noteFileName
        || typeof f.url !== 'string' || f.url.length > LIMITS.noteFileUrl) fail('invalid-argument', 'unknown');
  }

  const service = ROSTER_ID.exec(rosterId);
  const access = await churchAccess(deps, caller, data, service ? { arranges: service[4] } : 'member');
  const { cid } = access;
  let lastDay: string;
  if (service) {
    lastDay = service[1];
  } else {
    // An event's roster: whoever arranges all of it, or a 事工's 負責人
    // with a duty to arrange on events (Member.arrangesEvent).
    const roster = await deps.db.doc(`churches/${cid}/rosters/${rosterId}`).get();
    if (!roster.exists || roster.get('kind') !== 'event' || roster.get('cancelledAt') !== undefined) {
      fail('permission-denied', 'permissionDenied');
    }
    const g = groupOf(roster.get('group'));
    let arranges = access.powers.inGroup('roster-editors') || (g !== null && access.powers.leads(g));
    if (!arranges && access.powers.ministries.length > 0) {
      const ministries = ministriesOf(await deps.db.doc(`churches/${cid}/settings/ministries`).get());
      arranges = ledDuties(ministries, access.powers.ministries, null).size > 0;
    }
    if (!arranges) fail('permission-denied', 'permissionDenied');
    lastDay = roster.get('endDateKey') as string;
  }

  const ref = deps.db.doc(`churches/${cid}/rosterNotes/${rosterId}`);
  const before = filesOf((await ref.get()).get('files'));
  const prefix = notePrefix(cid, rosterId);
  const files: NoteFile[] = [];
  for (const f of asked) {
    const kept = before.find((b) => b.id === f.id);
    if (kept) {
      files.push({ ...kept, name: f.name as string });
      continue;
    }
    const path = prefix + (f.id as string);
    // The URL Storage gave the uploader, for this very file.
    if (!(f.url as string).includes(`/o/${encodeURIComponent(path)}?`)) fail('invalid-argument', 'unknown');
    const [exists] = await deps.bucket.file(path).exists();
    if (!exists) fail('invalid-argument', 'unknown');
    const [meta] = await deps.bucket.file(path).getMetadata();
    const size = Number(meta.size);
    if (!noteFileType(meta.contentType) || !(size <= LIMITS.noteFileBytes)) fail('invalid-argument', 'unknown');
    files.push({ id: f.id as string, name: f.name as string, type: meta.contentType as string, size, url: f.url as string });
  }

  if (text.trim() === '' && files.length === 0) {
    await ref.delete();
    return;
  }
  await ref.set({ text, files, dateKey: lastDay, by: access.caller.uid, updatedAt: FieldValue.serverTimestamp() });
}

/**
 * After note [rosterId] changed from [before] to [after] (null: deleted):
 * deletes the files it no longer has.
 */
export async function onRosterNoteWritten(
  deps: Pick<NoteDeps, 'bucket'>,
  cid: string,
  rosterId: string,
  before: Record<string, unknown> | null,
  after: Record<string, unknown> | null,
) {
  const prefix = notePrefix(cid, rosterId);
  if (after === null) {
    await deps.bucket.deleteFiles({ prefix });
    return;
  }
  const kept = new Set(filesOf(after.files).map((f) => f.id));
  await Promise.all(
    filesOf(before?.files)
      .filter((f) => !kept.has(f.id))
      .map((f) => deps.bucket.file(prefix + f.id).delete({ ignoreNotFound: true })),
  );
}

/**
 * Daily: deletes the notes whose roster's last day is LIMITS.noteDays
 * gone, and files uploaded over a day ago that no note has (picked, then
 * not kept). Returns how many notes.
 */
export async function forgetOldRosterNotes(deps: NoteDeps) {
  const now = deps.now().getTime();
  // A day early for nobody: the cut is in UTC, a day after the last day anywhere.
  const cut = new Date(now - (LIMITS.noteDays + 1) * DAY_MS).toISOString().slice(0, 10);
  const old = await deps.db.collectionGroup('rosterNotes').where('dateKey', '<', cut).get();
  const writer = deps.db.bulkWriter();
  for (const d of old.docs) void writer.delete(d.ref);
  await writer.close();
  await Promise.all(
    old.docs.map((d) => deps.bucket.deleteFiles({ prefix: notePrefix(d.ref.parent.parent!.id, d.id) })),
  );

  const [uploaded] = await deps.bucket.getFiles({ matchGlob: 'churches/*/rosterNotes/**' });
  const notes = new Map<string, Set<string> | null>();
  for (const file of uploaded) {
    const [, cid, , rosterId, id] = file.name.split('/');
    if (!cid || !rosterId || !id) continue;
    const made = Date.parse(String(file.metadata.timeCreated ?? ''));
    if (!(now - made > DAY_MS)) continue;
    const key = `${cid}/${rosterId}`;
    if (!notes.has(key)) {
      const note = await deps.db.doc(`churches/${cid}/rosterNotes/${rosterId}`).get();
      notes.set(key, note.exists ? new Set(filesOf(note.get('files')).map((f) => f.id)) : null);
    }
    if (!notes.get(key)?.has(id)) await file.delete({ ignoreNotFound: true });
  }
  return old.size;
}
