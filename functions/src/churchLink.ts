import { randomUUID } from 'node:crypto';

import { FieldValue, Timestamp, type DocumentSnapshot, type Transaction } from 'firebase-admin/firestore';

import { churchAccess, churchClosed, isChurchOpen } from './access.js';
import { fail, type Caller, type Deps } from './common.js';
import { cutText, LIMITS, TEXT_LIMITS } from './limits.js';
import { dateKeyIn, instantOf, nextDay, timeZoneOf, type ChurchTimeZone } from './timeZones.js';

/**
 * 教會連結的每日內容來源: one JSON contract, `{date, title, body, link}`.
 * The date must be the church's today. A failure replaces content with an error,
 * never a last-good summary or a guessed manual link.
 *
 * linkSources/{cid} is the private schedule. An epoch identifies a source/
 * time configuration; an attemptId and the link document's revision bind a
 * pending fetch to the settings that started it. Only the current attempt
 * can publish content, and an admin request must still be authorized then.
 */
export const FETCH_LIMITS = { bytes: 64 * 1024, timeoutMs: 5000, redirects: 3 };
export const DEFAULT_FETCH_MINUTE = 4 * 60 + 30;

export type FetchError = 'timeout' | 'tooLarge' | 'badFormat' | 'notToday' | 'notHttps' | 'http' | 'network';

export interface LinkContent {
  date: string;
  title: string;
  body: string;
  link: string;
}

export type FetchResult = { ok: true; content: LinkContent } | { ok: false; error: FetchError; status?: number };
type PublishedResult = { ok: true; content: LinkContent & { source: string; fetchedAt: number } } | Extract<FetchResult, { ok: false }>;

const isHttps = (url: string) => {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && !!u.hostname;
  } catch {
    return false;
  }
};

/** The one source contract: a dated JSON summary and its original HTTPS link. */
export function parseContent(raw: unknown): LinkContent | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  if (Object.keys(r).length !== 4 || !['date', 'title', 'body', 'link'].every((k) => Object.hasOwn(r, k))) return null;
  if (typeof r.date !== 'string' || !/^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/.test(r.date) || r.date.startsWith('0000-')) return null;
  const day = Date.parse(`${r.date}T00:00:00Z`);
  if (Number.isNaN(day) || new Date(day).toISOString().slice(0, 10) !== r.date) return null;
  if (typeof r.title !== 'string' || !r.title.trim() || typeof r.body !== 'string') return null;
  if (typeof r.link !== 'string' || r.link.trim().length > LIMITS.url || !isHttps(r.link.trim())) return null;
  return { date: r.date, title: cutText(r.title, TEXT_LIMITS.linkTitle), body: cutText(r.body, TEXT_LIMITS.linkBody), link: r.link.trim() };
}

async function readLimited(res: Response, max: number): Promise<string | null> {
  const declared = Number(res.headers.get('content-length'));
  if (declared > max) return null;
  if (!res.body) return '';
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString('utf8');
}

/** GET [url]: 5 seconds in all, at most 64KB, HTTPS redirects only; dated today in [timeZone]. Never throws. */
export async function fetchSource(deps: Pick<Deps, 'fetch' | 'now'>, url: string, timeZone: ChurchTimeZone): Promise<FetchResult> {
  const signal = AbortSignal.timeout(FETCH_LIMITS.timeoutMs);
  let current = url;
  try {
    for (let hop = 0; hop <= FETCH_LIMITS.redirects; hop++) {
      if (!isHttps(current)) return { ok: false, error: 'notHttps' };
      const res = await deps.fetch(current, { method: 'GET', redirect: 'manual', signal, headers: { accept: 'application/json' } });
      const location = res.headers.get('location');
      if (res.status >= 300 && res.status < 400 && location) {
        current = new URL(location, current).toString();
        continue;
      }
      if (!res.ok) return { ok: false, error: 'http', status: res.status };
      const text = await readLimited(res, FETCH_LIMITS.bytes);
      if (text === null) return { ok: false, error: 'tooLarge' };
      let json: unknown;
      try {
        json = JSON.parse(text);
      } catch {
        return { ok: false, error: 'badFormat' };
      }
      const content = parseContent(json);
      if (!content) return { ok: false, error: 'badFormat' };
      return content.date === dateKeyIn(timeZone, deps.now()) ? { ok: true, content } : { ok: false, error: 'notToday' };
    }
    return { ok: false, error: 'badFormat' };
  } catch (e) {
    const name = (e as { name?: string }).name;
    return { ok: false, error: name === 'TimeoutError' || name === 'AbortError' || signal.aborted ? 'timeout' : 'network' };
  }
}

/**
 * Today at [fetchMinute] on [timeZone]'s clock if still ahead and not
 * attempted today, otherwise tomorrow's.
 */
export function nextFetchAt(now: Date, fetchMinute: number, ranToday: boolean, timeZone: ChurchTimeZone): Date {
  const hhmm = `${String(Math.floor(fetchMinute / 60)).padStart(2, '0')}:${String(fetchMinute % 60).padStart(2, '0')}`;
  const day = dateKeyIn(timeZone, now);
  const today = instantOf(timeZone, `${day}T${hhmm}`);
  if (!ranToday && today > now.getTime()) return new Date(today);
  // The next day on the calendar: 24 hours on can be two days on, or the same day, as the clocks change.
  return new Date(instantOf(timeZone, `${nextDay(day)}T${hhmm}`));
}

/** Whether the source was fetched, or tried, on [day]. */
const triedOn = (schedule: DocumentSnapshot, day: string) => schedule.get('lastDay') === day || schedule.get('lastAttemptDay') === day;

function validMinute(v: unknown): number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0 || v >= 1440 || v % 15 !== 0) fail('invalid-argument', 'unknown');
  return v;
}

function assertAdmin(church: DocumentSnapshot, member: DocumentSnapshot | undefined) {
  if (!member?.exists) fail('permission-denied', 'permissionDenied');
  if (!isChurchOpen(church)) churchClosed();
  if (member.get('role') !== 'admin') fail('permission-denied', 'permissionDenied');
}

interface FetchLease {
  cid: string;
  timeZone: ChurchTimeZone;
  source: string;
  fetchMinute: number;
  attemptId: string;
  uid?: string;
}

/** Reserve the current settings before HTTP; scheduled jobs never retry twice in one day. */
async function prepareFetch(deps: Deps, cid: string, uid?: string, expectedEpoch?: string): Promise<FetchLease | null> {
  const attemptId = randomUUID();
  return deps.db.runTransaction(async (tx) => {
    const linkRef = deps.db.doc(`churches/${cid}/settings/link`);
    const scheduleRef = deps.db.doc(`linkSources/${cid}`);
    const refs = [deps.db.doc(`churches/${cid}`), linkRef, scheduleRef];
    if (uid) refs.push(deps.db.doc(`churches/${cid}/members/${uid}`));
    const [church, link, schedule, member] = await tx.getAll(...refs);
    if (uid) assertAdmin(church, member);
    if (!church.exists || !link.exists || !link.get('source')) {
      if (uid) fail('failed-precondition', 'unknown', link.exists ? 'noSource' : 'noLink');
      tx.delete(scheduleRef);
      tx.delete(deps.db.doc(`churches/${cid}/settings/linkContent`));
      return null;
    }
    if (!schedule.exists) {
      if (uid) fail('failed-precondition', 'unknown', 'noSource');
      return null;
    }
    const source = link.get('source') as unknown;
    if (typeof source !== 'string' || source.length > LIMITS.url || !isHttps(source)) fail('failed-precondition', 'unknown', 'notHttps');
    const fetchMinute = validMinute(link.get('fetchMinute'));
    if (schedule.get('source') !== source || schedule.get('fetchMinute') !== fetchMinute
        || (expectedEpoch !== undefined && schedule.get('epoch') !== expectedEpoch)) {
      if (uid) fail('aborted', 'conflict');
      return null;
    }
    const timeZone = timeZoneOf(church);
    const now = deps.now();
    const today = dateKeyIn(timeZone, now);
    const nextAt = Timestamp.fromDate(nextFetchAt(now, fetchMinute, true, timeZone));
    if (!uid) {
      const due = schedule.get('nextAt') as Timestamp | undefined;
      if (!due || due.toMillis() > now.getTime()) return null;
      if (!isChurchOpen(church) || triedOn(schedule, today)) {
        tx.update(scheduleRef, { nextAt });
        return null;
      }
    }
    tx.update(scheduleRef, { attemptId, lastAttemptDay: today, nextAt });
    return { cid, timeZone, source, fetchMinute, attemptId, ...(uid ? { uid } : {}) };
  });
}

/** Publish content and scheduling metadata together, only for the still-current attempt. */
async function runFetch(deps: Deps, lease: FetchLease): Promise<PublishedResult | null> {
  const fetched = await fetchSource(deps, lease.source, lease.timeZone);
  return deps.db.runTransaction(async (tx) => {
    const linkRef = deps.db.doc(`churches/${lease.cid}/settings/link`);
    const scheduleRef = deps.db.doc(`linkSources/${lease.cid}`);
    const refs = [deps.db.doc(`churches/${lease.cid}`), linkRef, scheduleRef];
    if (lease.uid) refs.push(deps.db.doc(`churches/${lease.cid}/members/${lease.uid}`));
    const [church, link, schedule, member] = await tx.getAll(...refs);
    if (lease.uid) assertAdmin(church, member);
    else if (!isChurchOpen(church)) return null;
    // The source and time decide; editing the fixed title, body or link does not.
    if (!link.exists || link.get('source') !== lease.source || link.get('fetchMinute') !== lease.fetchMinute || !schedule.exists
        || schedule.get('attemptId') !== lease.attemptId || schedule.get('source') !== lease.source
        || schedule.get('fetchMinute') !== lease.fetchMinute) {
      if (lease.uid) fail('aborted', 'conflict');
      return null;
    }
    const timeZone = timeZoneOf(church);
    const now = deps.now();
    const today = dateKeyIn(timeZone, now);
    // The response may have arrived before midnight while its transaction waited.
    const result: FetchResult = fetched.ok && fetched.content.date !== today ? { ok: false, error: 'notToday' } : fetched;
    const at = Timestamp.fromDate(now);
    tx.set(deps.db.doc(`churches/${lease.cid}/settings/linkContent`), result.ok
      ? { ...result.content, source: lease.source, fetchedAt: at, error: null, errorStatus: null, errorAt: null }
      : { source: lease.source, error: result.error, errorStatus: result.status ?? null, errorAt: at });
    tx.update(scheduleRef, {
      attemptId: FieldValue.delete(), lastAttemptDay: today,
      ...(result.ok ? { lastDay: today } : {}),
      nextAt: Timestamp.fromDate(nextFetchAt(now, lease.fetchMinute, true, timeZone)),
    });
    return result.ok
      ? { ok: true, content: { ...result.content, source: lease.source, fetchedAt: now.getTime() } }
      : result;
  });
}

const reply = (result: PublishedResult) => result.ok
  ? { ok: true, content: result.content }
  : { ok: false, error: result.error, status: result.status ?? null };

/**
 * Configure or clear a source (admins), fetching a new source immediately.
 * A time-only change performs no HTTP. `{churchId, refresh:true}` retries the
 * stored source now without resaving static fields, source or fetch time.
 */
export async function setLinkSource(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'admin');
  const input = (data ?? {}) as Record<string, unknown>;
  if (input.refresh !== undefined) {
    if (input.refresh !== true || Object.keys(input).some((k) => k !== 'churchId' && k !== 'refresh')) fail('invalid-argument', 'unknown');
    const lease = await prepareFetch(deps, cid, c.uid);
    if (!lease) fail('aborted', 'conflict');
    const result = await runFetch(deps, lease);
    if (!result) fail('aborted', 'conflict');
    return reply(result);
  }
  if (Object.keys(input).some((k) => !['churchId', 'source', 'fetchMinute'].includes(k))) fail('invalid-argument', 'unknown');
  const clearing = input.source === null || input.source === '';
  if (!clearing && (typeof input.source !== 'string' || input.source.length > LIMITS.url || !isHttps(input.source.trim()))) {
    fail('invalid-argument', 'unknown', 'notHttps');
  }
  const source = clearing ? '' : (input.source as string).trim();
  const fetchMinute = clearing ? DEFAULT_FETCH_MINUTE : validMinute(input.fetchMinute ?? DEFAULT_FETCH_MINUTE);
  const epoch = randomUUID();
  const selectedEpoch = await deps.db.runTransaction(async (tx) => {
    const linkRef = deps.db.doc(`churches/${cid}/settings/link`);
    const scheduleRef = deps.db.doc(`linkSources/${cid}`);
    const [church, member, link, schedule] = await tx.getAll(
      deps.db.doc(`churches/${cid}`), deps.db.doc(`churches/${cid}/members/${c.uid}`), linkRef, scheduleRef,
    );
    assertAdmin(church, member);
    if (!link.exists) fail('failed-precondition', 'unknown', 'noLink');
    if (clearing) {
      tx.update(linkRef, { source: FieldValue.delete(), fetchMinute: FieldValue.delete() });
      tx.delete(scheduleRef);
      tx.delete(deps.db.doc(`churches/${cid}/settings/linkContent`));
      return null;
    }
    const timeZone = timeZoneOf(church);
    const now = deps.now();
    const today = dateKeyIn(timeZone, now);
    if (schedule.get('source') === source && link.get('source') === source) {
      if (link.get('fetchMinute') !== fetchMinute || schedule.get('fetchMinute') !== fetchMinute) {
        const ranToday = triedOn(schedule, today);
        tx.update(linkRef, { source, fetchMinute });
        tx.update(scheduleRef, {
          source, fetchMinute, epoch, attemptId: FieldValue.delete(),
          nextAt: Timestamp.fromDate(nextFetchAt(now, fetchMinute, ranToday, timeZone)),
        });
      }
      return null;
    }
    tx.update(linkRef, { source, fetchMinute });
    tx.set(scheduleRef, { source, fetchMinute, epoch, lastAttemptDay: today, nextAt: Timestamp.fromDate(nextFetchAt(now, fetchMinute, true, timeZone)) });
    tx.delete(deps.db.doc(`churches/${cid}/settings/linkContent`));
    return epoch;
  });
  if (clearing) return { ok: true, content: null };
  if (!selectedEpoch) return { ok: true, content: null, unchanged: true };
  const lease = await prepareFetch(deps, cid, c.uid, selectedEpoch);
  if (!lease) fail('aborted', 'conflict');
  const result = await runFetch(deps, lease);
  if (!result) fail('aborted', 'conflict');
  return reply(result);
}

/** One scheduled attempt per church/day; stale or closed contexts are never published. */
export async function fetchDueLinks(deps: Deps) {
  const due = await deps.db.collection('linkSources').where('nextAt', '<=', Timestamp.fromDate(deps.now())).get();
  let fetched = 0;
  for (const doc of due.docs) {
    const lease = await prepareFetch(deps, doc.id);
    if (lease && await runFetch(deps, lease)) fetched++;
  }
  return fetched;
}

/**
 * Moves the church's next fetch to its fetch time on [timeZone]'s clock, in
 * [tx]: the church's time zone is changing to [timeZone]. Read before any write.
 */
export async function moveLinkFetch(deps: Deps, tx: Transaction, cid: string, timeZone: ChurchTimeZone) {
  const ref = deps.db.doc(`linkSources/${cid}`);
  const schedule = await tx.get(ref);
  return () => {
    if (!schedule.exists) return;
    const fetchMinute = schedule.get('fetchMinute');
    if (typeof fetchMinute !== 'number') return;
    const now = deps.now();
    const today = dateKeyIn(timeZone, now);
    tx.update(ref, { nextAt: Timestamp.fromDate(nextFetchAt(now, fetchMinute, triedOn(schedule, today), timeZone)) });
  };
}

/** Drops the church's fetch schedule: the church is purged. */
export async function forgetLinkSource(deps: Deps, cid: string) {
  await deps.db.doc(`linkSources/${cid}`).delete();
}
