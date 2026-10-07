import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { dateKeyUtc8, fail, type Caller, type Deps } from './common.js';
import { cutText, LIMITS, TEXT_LIMITS } from './limits.js';

/**
 * 教會連結的每日內容來源: an admin gives a JSON URL and a time of day; the
 * backend fetches `{title, body, link}` from it once a day after that time
 * (Asia/Taipei) and keeps the result in settings/linkContent, which the
 * home page shows instead of the fixed link while it is fresh.
 *
 * linkSources/{cid} (backend only) is the schedule: the source, the time,
 * when it is next due and the day it last ran. The scheduler reads only the
 * sources that are due.
 *
 * Only JSON is supported; scraping a page (self-host's dailyBibleHtml) is
 * not.
 */
export const FETCH_LIMITS = { bytes: 64 * 1024, timeoutMs: 5000, redirects: 3 };
export const DEFAULT_FETCH_MINUTE = 4 * 60 + 30;

export type FetchError = 'timeout' | 'tooLarge' | 'badFormat' | 'notHttps' | 'http' | 'network';

export interface LinkContent {
  title: string;
  body: string;
  link: string | null;
}

export type FetchResult = { ok: true; content: LinkContent } | { ok: false; error: FetchError; status?: number };

const isHttps = (url: string) => {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && !!u.hostname;
  } catch {
    return false;
  }
};

/** At most [max] characters, trimmed. */

/** `{title, body, link}` checked and cut to the church link's limits. */
export function parseContent(raw: unknown): LinkContent | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.title !== 'string' || !r.title.trim()) return null;
  if (r.body !== undefined && r.body !== null && typeof r.body !== 'string') return null;
  const link = typeof r.link === 'string' && isHttps(r.link.trim()) ? r.link.trim() : null;
  return { title: cutText(r.title, TEXT_LIMITS.linkTitle), body: cutText((r.body as string | undefined) ?? '', TEXT_LIMITS.linkBody), link };
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

/**
 * GET [url]: 5 seconds in all, at most 64KB, redirects followed only to
 * https. Never throws.
 */
export async function fetchSource(deps: Pick<Deps, 'fetch'>, url: string): Promise<FetchResult> {
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
      return content ? { ok: true, content } : { ok: false, error: 'badFormat' };
    }
    return { ok: false, error: 'badFormat' };
  } catch (e) {
    const name = (e as { name?: string }).name;
    return { ok: false, error: name === 'TimeoutError' || name === 'AbortError' || signal.aborted ? 'timeout' : 'network' };
  }
}

const DAY = 86400e3;
const TAIPEI = 8 * 3600e3;

/** Midnight in Asia/Taipei of the day [date] falls on, as an instant. */
function taipeiMidnight(date: Date) {
  return Math.floor((date.getTime() + TAIPEI) / DAY) * DAY - TAIPEI;
}

/**
 * When a source is next due: today at [fetchMinute] if that is still ahead
 * and it has not run today, otherwise tomorrow at [fetchMinute].
 */
export function nextFetchAt(now: Date, fetchMinute: number, ranToday: boolean): Date {
  const today = taipeiMidnight(now) + fetchMinute * 60e3;
  if (!ranToday && today > now.getTime()) return new Date(today);
  return new Date(today + DAY);
}

function validMinute(v: unknown): number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0 || v >= 1440 || v % 15 !== 0) fail('invalid-argument', 'unknown');
  return v;
}

/** Fetches [cid]'s source now and records the result. */
async function runFetch(deps: Deps, cid: string, source: string): Promise<FetchResult> {
  const result = await fetchSource(deps, source);
  const ref = deps.db.doc(`churches/${cid}/settings/linkContent`);
  const now = Timestamp.fromDate(deps.now());
  if (result.ok) {
    await ref.set({ ...result.content, source, fetchedAt: now, error: null, errorStatus: null, errorAt: null });
    return result;
  }
  const failure = { source, error: result.error, errorStatus: result.status ?? null, errorAt: now };
  // Keep the last good content of the same source; another source's
  // content must not show under this one.
  const sameSource = (await ref.get()).get('source') === source;
  await (sameSource ? ref.set(failure, { merge: true }) : ref.set(failure));
  return result;
}

/**
 * Sets or clears the content source of the church link and the time it is
 * fetched (admins). A new source is fetched at once and the result returned;
 * a new time alone takes effect from its next occurrence.
 */
export async function setLinkSource(deps: Deps, caller: Caller | null, data: unknown) {
  const { cid } = await churchAccess(deps, caller, data, 'admin');
  const input = (data ?? {}) as { source?: unknown; fetchMinute?: unknown };
  const linkRef = deps.db.doc(`churches/${cid}/settings/link`);
  if (!(await linkRef.get()).exists) fail('failed-precondition', 'unknown', 'noLink');
  const scheduleRef = deps.db.doc(`linkSources/${cid}`);

  if (input.source === null || input.source === '') {
    await linkRef.update({ source: FieldValue.delete(), fetchMinute: FieldValue.delete() });
    await scheduleRef.delete();
    await deps.db.doc(`churches/${cid}/settings/linkContent`).delete();
    return { ok: true, content: null };
  }
  if (typeof input.source !== 'string' || input.source.length > LIMITS.url || !isHttps(input.source.trim())) {
    fail('invalid-argument', 'unknown', 'notHttps');
  }
  const source = input.source.trim();
  const fetchMinute = validMinute(input.fetchMinute ?? DEFAULT_FETCH_MINUTE);
  const schedule = await scheduleRef.get();
  const today = dateKeyUtc8(deps.now());

  await linkRef.update({ source, fetchMinute });
  if (schedule.get('source') === source) {
    // Only the time changed: no fetch now, the next run moves.
    const ranToday = schedule.get('lastDay') === today;
    await scheduleRef.set({ source, fetchMinute, nextAt: Timestamp.fromDate(nextFetchAt(deps.now(), fetchMinute, ranToday)) }, { merge: true });
    return { ok: true, content: null, unchanged: true };
  }
  const result = await runFetch(deps, cid, source);
  await scheduleRef.set({
    source,
    fetchMinute,
    lastDay: today,
    nextAt: Timestamp.fromDate(nextFetchAt(deps.now(), fetchMinute, true)),
  });
  return result.ok ? { ok: true, content: result.content } : { ok: false, error: result.error, status: result.status ?? null };
}

/**
 * Every 15 minutes: fetches each source whose time has come today and that
 * has not run today. Closed churches are skipped (and wait for tomorrow);
 * a source whose link was removed is dropped.
 */
export async function fetchDueLinks(deps: Deps) {
  const now = deps.now();
  const today = dateKeyUtc8(now);
  const due = await deps.db.collection('linkSources').where('nextAt', '<=', Timestamp.fromDate(now)).get();
  let fetched = 0;
  for (const doc of due.docs) {
    const cid = doc.id;
    const fetchMinute = (doc.get('fetchMinute') as number | undefined) ?? DEFAULT_FETCH_MINUTE;
    const next = { nextAt: Timestamp.fromDate(nextFetchAt(now, fetchMinute, true)), lastDay: today };
    if (doc.get('lastDay') === today) {
      await doc.ref.update({ nextAt: next.nextAt });
      continue;
    }
    const [church, link] = await Promise.all([
      deps.db.doc(`churches/${cid}`).get(),
      deps.db.doc(`churches/${cid}/settings/link`).get(),
    ]);
    const source = link.get('source') as string | undefined;
    if (!church.exists || !source) {
      await doc.ref.delete();
      continue;
    }
    if (church.get('status') === 'active') {
      await runFetch(deps, cid, source);
      fetched++;
    }
    await doc.ref.update(next);
  }
  return fetched;
}
