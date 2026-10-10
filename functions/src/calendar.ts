import { createHash, randomBytes } from 'node:crypto';

import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { DAY_MS, dateKeyUtc8, fail, type Caller, type Deps } from './common.js';
import { cutText, TEXT_LIMITS } from './limits.js';
import { seal, unseal } from './sealing.js';
import { notify, type WebhookDeps } from './webhook.js';

/**
 * 行事曆: a church admin connects one Google Calendar. The backend keeps the
 * refresh token (sealed, in calendarTokens/{cid}, which no client can
 * read), reads through a 10-minute cache shared by everyone in
 * the church, and writes for admins and calendar-editors.
 *
 * Scopes: calendar.events (read/write events), calendar.calendarlist.readonly
 * (let the admin pick which calendar). Sign-in with Google never asks for
 * these; only the admin who connects sees the consent screen.
 */
export const SCOPES = [
  'https://www.googleapis.com/auth/calendar.events',
  'https://www.googleapis.com/auth/calendar.calendarlist.readonly',
];
export const CACHE_MINUTES = 10;
const STATE_MINUTES = 15;

export interface OAuthConfig {
  clientId: string;
  clientSecret: string;
  /** The calendarCallback function URL. */
  redirectUri: string;
  /** Where the browser goes after connecting (the web app). */
  appUrl: string;
  /** 32-byte key, base64, that seals the refresh token. */
  tokenKey: string;
}

/** Google's HTTP APIs, injectable for tests. */
export interface GoogleApi {
  exchangeCode(code: string, config: OAuthConfig): Promise<{ refreshToken: string | null }>;
  /** Throws GoogleAuthRevoked when the refresh token no longer works. */
  accessToken(refreshToken: string, config: OAuthConfig, grant?: { churchId: string; revision: string }): Promise<string>;
  calendars(accessToken: string): Promise<{ id: string; name: string; primary: boolean }[]>;
  events(accessToken: string, calendarId: string, from: Date, to: Date): Promise<CalendarEvent[]>;
  upsert(accessToken: string, calendarId: string, event: CalendarEvent): Promise<CalendarEvent>;
  /** One event, or null when it is gone. */
  get(accessToken: string, calendarId: string, eventId: string): Promise<CalendarEvent | null>;
  remove(accessToken: string, calendarId: string, eventId: string): Promise<void>;
  revoke(refreshToken: string): Promise<void>;
}

export class GoogleAuthRevoked extends Error {}

/** The fields the app shows and edits. */
export interface CalendarEvent {
  id?: string;
  title: string;
  /** All-day: `YYYY-MM-DD`; timed: ISO instant. */
  start: string;
  end: string;
  allDay: boolean;
  location?: string;
  description?: string;
  /** Google Calendar's page for the event (htmlLink); read only. */
  link?: string;
  /** Deleted (Google's status `cancelled`), as a get of it may still say. */
  cancelled?: boolean;
  /** For one day of a recurring event: the series, and the start it had in it. */
  recurringEventId?: string;
  originalStart?: string;
}

/** Changes go out to the church's webhook, hence WebhookDeps. */
export type CalDeps = WebhookDeps & { google: GoogleApi; config: OAuthConfig };

/** Starts connecting: a Google consent URL bound to this admin and church. */
export async function calendarAuthUrl(deps: CalDeps, caller: Caller | null, data: unknown) {
  const { cid: churchId, caller: c } = await churchAccess(deps, caller, data, 'admin');
  const state = randomBytes(24).toString('base64url');
  await deps.db.doc(`calendarStates/${state}`).set({
    cid: churchId,
    uid: c.uid,
    expiresAt: Timestamp.fromMillis(deps.now().getTime() + STATE_MINUTES * 60e3),
  });
  const params = new URLSearchParams({
    client_id: deps.config.clientId,
    redirect_uri: deps.config.redirectUri,
    response_type: 'code',
    scope: SCOPES.join(' '),
    access_type: 'offline',
    prompt: 'consent',
    include_granted_scopes: 'false',
    state,
  });
  return { url: `https://accounts.google.com/o/oauth2/v2/auth?${params}` };
}

/** OAuth redirect: stores the refresh token and sends the browser back. */
export async function calendarCallback(deps: CalDeps, query: Record<string, unknown>) {
  const back = (result: string) => `${deps.config.appUrl}/me/calendar?result=${result}`;
  const state = typeof query.state === 'string' ? query.state : '';
  const code = typeof query.code === 'string' ? query.code : '';
  if (!state || !/^[A-Za-z0-9_-]{16,64}$/.test(state)) return back('invalid');
  const ref = deps.db.doc(`calendarStates/${state}`);
  const snap = await ref.get();
  await ref.delete();
  const expiresAt = snap.get('expiresAt') as Timestamp | undefined;
  if (!snap.exists || !expiresAt || expiresAt.toMillis() < deps.now().getTime()) return back('expired');
  if (!code) return back('denied');
  let refreshToken: string | null;
  try {
    ({ refreshToken } = await deps.google.exchangeCode(code, deps.config));
  } catch (e) {
    // A used or stale code (a reloaded page, a double tap): let them try again.
    console.warn('calendarCallback: code refused', e);
    return back('failed');
  }
  if (!refreshToken) return back('failed');
  const churchId = snap.get('cid') as string;
  await deps.db.doc(`calendarTokens/${churchId}`).set({
    token: seal(refreshToken, deps.config.tokenKey),
    connectedBy: snap.get('uid'),
    connectedAt: FieldValue.serverTimestamp(),
    calendarId: null,
  });
  await deps.db.doc(`churches/${churchId}/settings/calendar`).set({
    connected: true,
    needsReconnect: false,
    calendarId: null,
    calendarName: null,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return back('connected');
}

/**
 * The church's access token and calendar for a scheduled job, or null when
 * there is none to use now (not connected, the grant revoked, Google out
 * of reach): the job leaves the church alone until there is.
 */
export async function calendarAccess(deps: CalDeps, churchId: string) {
  try {
    return await access(deps, churchId);
  } catch (e) {
    console.warn(`calendar access ${churchId}`, e);
    return null;
  }
}

async function access(deps: CalDeps, churchId: string) {
  const tokenDoc = await deps.db.doc(`calendarTokens/${churchId}`).get();
  if (!tokenDoc.exists) fail('failed-precondition', 'unknown', 'notConnected');
  try {
    const revision = tokenDoc.updateTime!;
    const token = await deps.google.accessToken(
      unseal(tokenDoc.get('token') as string, deps.config.tokenKey), deps.config,
      { churchId, revision: `${revision.seconds}:${revision.nanoseconds}` },
    );
    const current = await tokenDoc.ref.get();
    if (!current.exists) fail('failed-precondition', 'unknown', 'notConnected');
    if (!current.updateTime?.isEqual(revision)) fail('aborted', 'unknown', 'calendarChanged');
    return { token, calendarId: tokenDoc.get('calendarId') as string | null };
  } catch (e) {
    if (e instanceof GoogleAuthRevoked) {
      const sameGrant = await deps.db.runTransaction(async (tx) => {
        const current = await tx.get(tokenDoc.ref);
        if (!current.updateTime?.isEqual(tokenDoc.updateTime!)) return false;
        tx.set(deps.db.doc(`churches/${churchId}/settings/calendar`), { needsReconnect: true }, { merge: true });
        return true;
      });
      if (!sameGrant) fail('aborted', 'unknown', 'calendarChanged');
      fail('failed-precondition', 'unknown', 'reconnect');
    }
    throw e;
  }
}

export async function calendarList(deps: CalDeps, caller: Caller | null, data: unknown) {
  const { cid: churchId } = await churchAccess(deps, caller, data, 'admin');
  const { token } = await access(deps, churchId);
  return { calendars: await deps.google.calendars(token) };
}

export async function calendarSelect(deps: CalDeps, caller: Caller | null, data: unknown) {
  const { cid: churchId } = await churchAccess(deps, caller, data, 'admin');
  const input = data as { calendarId?: unknown; calendarName?: unknown };
  if (typeof input.calendarId !== 'string' || typeof input.calendarName !== 'string') fail('invalid-argument', 'unknown');
  await deps.db.doc(`calendarTokens/${churchId}`).update({ calendarId: input.calendarId });
  await deps.db.doc(`churches/${churchId}/settings/calendar`).set(
    { calendarId: input.calendarId, calendarName: input.calendarName.slice(0, 100), updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await clearCache(deps, churchId);
  return {};
}

export async function calendarDisconnect(deps: CalDeps, caller: Caller | null, data: unknown) {
  const { cid: churchId } = await churchAccess(deps, caller, data, 'admin');
  await forgetCalendar(deps, churchId);
  return {};
}

/**
 * Revokes the church's Google grant and deletes the token, settings, cache
 * and any connecting still in progress. Used when an admin disconnects,
 * when the church is purged, and when the person who connected it stops
 * being an admin there (their Google account must not stay reachable
 * through the church).
 */
export async function forgetCalendar(deps: CalDeps, churchId: string) {
  const tokenDoc = await deps.db.doc(`calendarTokens/${churchId}`).get();
  if (tokenDoc.exists) {
    try {
      await deps.google.revoke(unseal(tokenDoc.get('token') as string, deps.config.tokenKey));
    } catch {
      // Already revoked on Google's side; still forget it here.
    }
    await tokenDoc.ref.delete();
  }
  await deps.db.doc(`churches/${churchId}/settings/calendar`).delete();
  await clearCache(deps, churchId);
  const states = await deps.db.collection('calendarStates').where('cid', '==', churchId).get();
  await Promise.all(states.docs.map((d) => d.ref.delete()));
}

/** forgetCalendar when [uid] is the admin who connected the church's calendar. */
export async function releaseCalendarIfConnector(deps: CalDeps, churchId: string, uid: string) {
  const tokenDoc = await deps.db.doc(`calendarTokens/${churchId}`).get();
  if (!tokenDoc.exists || tokenDoc.get('connectedBy') !== uid) return false;
  await forgetCalendar(deps, churchId);
  return true;
}

/** Drops the church's cached [months], or every cached month. */
async function clearCache(deps: Deps, churchId: string, months?: Iterable<string>) {
  if (months) {
    await Promise.all([...months].map((m) => deps.db.doc(`calendarCache/${churchId}_${m}`).delete()));
    return;
  }
  const snap = await deps.db.collection('calendarCache').where('cid', '==', churchId).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

function monthRange(month: string) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) fail('invalid-argument', 'unknown');
  const [y, m] = month.split('-').map(Number);
  // UTC+8 month boundaries. Google returns every event that overlaps them
  // (ends after `from`, starts before `to`), so one event can be in the
  // cache of several months: see monthsOf.
  return { from: new Date(Date.UTC(y, m - 1, 1) - 8 * 3600e3), to: new Date(Date.UTC(y, m, 1) - 8 * 3600e3) };
}

/**
 * Events of one month. Everyone in the church shares a 10-minute cached
 * copy; simultaneous cold misses can still make separate Google calls.
 */
export async function calendarEvents(deps: CalDeps, caller: Caller | null, data: unknown) {
  const { cid: churchId } = await churchAccess(deps, caller, data, 'member');
  const month = String((data as { month?: unknown })?.month ?? '');
  const { from, to } = monthRange(month);
  const cacheRef = deps.db.doc(`calendarCache/${churchId}_${month}`);
  const cached = await cacheRef.get();
  const fetchedAt = cached.get('fetchedAt') as Timestamp | undefined;
  if (fetchedAt && deps.now().getTime() - fetchedAt.toMillis() < CACHE_MINUTES * 60e3) {
    return { events: cached.get('events') as CalendarEvent[], cached: true };
  }
  const { token, calendarId } = await access(deps, churchId);
  if (!calendarId) fail('failed-precondition', 'unknown', 'noCalendar');
  // Google leaves out what an event does not have; Firestore refuses undefined.
  const events = (await deps.google.events(token, calendarId, from, to)).map(
    (e) => Object.fromEntries(Object.entries(e).filter(([, v]) => v !== undefined)) as unknown as CalendarEvent,
  );
  await cacheRef.set({ cid: churchId, month, events, fetchedAt: Timestamp.fromDate(deps.now()) });
  return { events, cached: false };
}

/** An event's start and end as the app sends them (CalendarEvent's). */
interface Span {
  start: string;
  end?: string;
}

const span = (v: unknown): Span | null => {
  const o = v as { start?: unknown; end?: unknown } | null | undefined;
  if (typeof o?.start !== 'string') return null;
  return { start: o.start, end: typeof o.end === 'string' ? o.end : undefined };
};

/** More months than this and a write drops the church's whole cache instead. */
const MAX_CLEARED_MONTHS = 12;

/**
 * Create, update or delete one event (admins and calendar-editors).
 *
 * `{ churchId, op: 'upsert', event, previous?: { start, end },
 * restoreRosterOf? }`, where `previous` is where an edited event was before
 * (older web clients send `previousStart` instead), or `{ churchId, op:
 * 'delete', eventId, event: { start, end } }`. Every cached month the event
 * was or is in is dropped, so everyone sees the change on their next read.
 *
 * The event's roster (活動的服事表), if it has one, goes with it, written
 * here because a calendar editor may not hold roster rights: an edit copies
 * the title and days, a delete cancels it (kept for undo), and an upsert
 * with `restoreRosterOf` (undoing a delete, which makes the event again
 * under a new id) moves the cancelled roster onto the new event.
 */
export async function calendarWrite(deps: CalDeps, caller: Caller | null, data: unknown) {
  const me = await churchAccess(deps, caller, data, { group: 'calendar-editors' });
  const churchId = me.cid;
  const input = data as {
    op?: unknown;
    event?: Partial<CalendarEvent>;
    eventId?: unknown;
    previous?: unknown;
    previousStart?: unknown;
    restoreRosterOf?: unknown;
  };
  const { token, calendarId } = await access(deps, churchId);
  if (!calendarId) fail('failed-precondition', 'unknown', 'noCalendar');
  let result: CalendarEvent | null = null;
  let notice: { action: 'created' | 'updated' | 'deleted'; event: Partial<CalendarEvent> } | null = null;
  const spans: (Span | null)[] = [span(input.previous), span({ start: input.previousStart })];
  if (input.op === 'delete') {
    if (typeof input.eventId !== 'string') fail('invalid-argument', 'unknown');
    // What it was, for the webhook: Google's DELETE returns nothing.
    const before = await deps.google.get(token, calendarId, input.eventId).catch(() => null);
    await deps.google.remove(token, calendarId, input.eventId);
    await rosterStep(`cancel ${churchId}/ev_${input.eventId}`, () => cancelEventRoster(deps, churchId, input.eventId as string));
    spans.push(span(input.event), span(before));
    notice = { action: 'deleted', event: before ?? { ...input.event, id: input.eventId } };
  } else if (input.op === 'upsert') {
    const e = input.event;
    if (!e || typeof e.title !== 'string' || !e.title.trim() || typeof e.start !== 'string' || typeof e.end !== 'string') {
      fail('invalid-argument', 'unknown');
    }
    result = await deps.google.upsert(token, calendarId, {
      id: typeof e.id === 'string' ? e.id : undefined,
      title: e.title.trim().slice(0, 200),
      start: e.start,
      end: e.end,
      allDay: e.allDay === true,
      location: typeof e.location === 'string' ? e.location.slice(0, 300) : undefined,
      description: typeof e.description === 'string' ? e.description.slice(0, 4000) : undefined,
    });
    spans.push(span(e));
    const done = result;
    if (typeof e.id === 'string') {
      await rosterStep(`follow ${churchId}/ev_${e.id}`, () => followEvent(deps, churchId, done, me.caller.uid));
    }
    const restore = input.restoreRosterOf;
    if (typeof restore === 'string') {
      await rosterStep(`restore ${churchId}/ev_${restore}`, () => restoreEventRoster(deps, churchId, restore, done));
    }
    notice = { action: typeof e.id === 'string' ? 'updated' : 'created', event: result };
  } else {
    fail('invalid-argument', 'unknown');
  }
  const months = new Set(spans.flatMap((s) => (s ? monthsOf(s.start, s.end) : [])));
  await clearCache(deps, churchId, months.size > MAX_CLEARED_MONTHS ? undefined : months);
  if (notice) {
    // After Google has it. A webhook failure is recorded, never thrown.
    await notify(deps, me.church, `calendar.${notice.action}`, eventDetails(notice.event, {
      actorUid: me.caller.uid,
      actorName: (me.member.get('name') as string | undefined) || null,
    }));
  }
  return { event: result };
}

/** The days an event's roster is on (`dateKey`s): UTC+8, an all-day end exclusive. */
export function eventRosterDays(e: { start: string; end?: string; allDay?: boolean }) {
  const ymd = /^\d{4}-\d{2}-\d{2}$/;
  if (e.allDay === true || ymd.test(e.start)) {
    const last = inclusiveEnd(e.end);
    return { dateKey: e.start, endDateKey: last && last > e.start ? last : e.start };
  }
  const start = Date.parse(e.start);
  const end = e.end === undefined ? NaN : Date.parse(e.end);
  const dateKey = dateKeyUtc8(new Date(start));
  return { dateKey, endDateKey: end > start ? dateKeyUtc8(new Date(end - 1)) : dateKey };
}

const eventRosterRef = (deps: Deps, churchId: string, eventId: string) =>
  deps.db.doc(`churches/${churchId}/rosters/ev_${eventId}`);

/**
 * Runs a step on an event's roster after Google has the change. A failure
 * is logged, never thrown: the event changed, so the call must not look
 * failed (an undo retried would make the event twice).
 */
async function rosterStep(what: string, step: () => Promise<void>) {
  try {
    await step();
  } catch (e) {
    console.error(`event roster: ${what} failed`, e);
  }
}

/** What an event's roster copies from [e]. `via` clears a `restore`, so a later move is told. */
export const fromEvent = (e: CalendarEvent) => ({
  title: cutText(e.title, TEXT_LIMITS.eventTitle),
  ...eventRosterDays(e),
  via: 'calendar',
  updatedAt: FieldValue.serverTimestamp(),
});

/**
 * Copies [e]'s title and days to its roster, if it has one still on.
 * [by] made the change: the trigger tells them nothing of it.
 */
async function followEvent(deps: Deps, churchId: string, e: CalendarEvent, by: string) {
  if (!e.id) return;
  const ref = eventRosterRef(deps, churchId, e.id);
  await deps.db.runTransaction(async (tx) => {
    const r = await tx.get(ref);
    if (!r.exists || r.get('kind') !== 'event' || r.get('cancelledAt') != null) return;
    const next = fromEvent(e);
    if (r.get('title') === next.title && r.get('dateKey') === next.dateKey && r.get('endDateKey') === next.endDateKey) return;
    tx.update(ref, { ...next, movedBy: by });
  });
}

/** Marks the roster of deleted event [eventId] cancelled: not shown, not reminded, kept for undo. */
async function cancelEventRoster(deps: Deps, churchId: string, eventId: string) {
  const ref = eventRosterRef(deps, churchId, eventId);
  await deps.db.runTransaction(async (tx) => {
    const r = await tx.get(ref);
    if (r.exists && r.get('kind') === 'event') tx.update(ref, { cancelledAt: Timestamp.fromDate(deps.now()) });
  });
}

/** Moves the cancelled roster of deleted event [fromId] onto [e], the event made again. */
async function restoreEventRoster(deps: Deps, churchId: string, fromId: string, e: CalendarEvent) {
  if (!/^[A-Za-z0-9_-]{1,1024}$/.test(fromId) || !e.id || fromId === e.id) return;
  const from = eventRosterRef(deps, churchId, fromId);
  const to = eventRosterRef(deps, churchId, e.id);
  await deps.db.runTransaction(async (tx) => {
    const r = await tx.get(from);
    if (!r.exists || r.get('kind') !== 'event' || r.get('cancelledAt') == null) return;
    // As a restore: the trigger tells nobody, they were never told it went.
    const keep = (k: string) => (r.get(k) === undefined ? {} : { [k]: r.get(k) });
    tx.set(to, {
      kind: 'event',
      eventId: e.id,
      duties: r.get('duties') ?? [],
      events: [],
      ...keep('calendarId'),
      ...keep('recurringEventId'),
      ...keep('originalStart'),
      ...fromEvent(e),
      via: 'restore',
    });
    tx.delete(from);
  });
}

/**
 * What a calendar notice says about the event (webhook.ts adds the church
 * and the action), in the self-host version's shape so existing n8n flows
 * keep working: every key always present, an all-day event's end the last
 * day it covers (Google's is the day after).
 */
export function eventDetails(e: Partial<CalendarEvent>, who: { actorUid: string; actorName: string | null }) {
  const allDay = e.allDay === true;
  return {
    id: e.id ?? null,
    title: e.title ?? null,
    allDay,
    start: e.start ?? null,
    end: allDay ? inclusiveEnd(e.end) : (e.end ?? null),
    location: e.location ?? '',
    description: e.description ?? '',
    link: e.link ?? null,
    actorUid: who.actorUid,
    actorName: who.actorName,
  };
}

/** Google's exclusive all-day end date → the last day covered. */
function inclusiveEnd(end: string | undefined): string | null {
  if (typeof end !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(end)) return null;
  return new Date(Date.parse(`${end}T00:00:00Z`) - DAY_MS).toISOString().slice(0, 10);
}

/** The real Google APIs over fetch. */
export function googleApi(options: Partial<Pick<Deps, 'fetch' | 'now'>> = {}): GoogleApi {
  const fetch = options.fetch ?? globalThis.fetch;
  const now = options.now ?? (() => new Date());
  const tokens = new Map<string, { token: string; expiresAt: number }>();
  const refreshes = new Map<string, { pending: Promise<string>; until: number }>();
  const grantHash = (refreshToken: string) => createHash('sha256').update(refreshToken).digest('hex');
  const api = 'https://www.googleapis.com/calendar/v3';
  const json = async (res: Response, token?: string) => {
    if (res.status === 401 && token) {
      for (const [key, cached] of tokens) if (cached.token === token) tokens.delete(key);
    }
    if (!res.ok) throw new Error(`google ${res.status}: ${(await res.text()).slice(0, 300)}`);
    return res.status === 204 ? {} : res.json();
  };
  const toGoogle = (e: CalendarEvent) => ({
    summary: e.title,
    location: e.location,
    description: e.description,
    start: e.allDay ? { date: e.start } : { dateTime: e.start },
    end: e.allDay ? { date: e.end } : { dateTime: e.end },
  });
  const fromGoogle = (g: {
    id: string;
    status?: string;
    summary?: string;
    location?: string;
    description?: string;
    htmlLink?: string;
    start?: { date?: string; dateTime?: string };
    end?: { date?: string; dateTime?: string };
    recurringEventId?: string;
    originalStartTime?: { date?: string; dateTime?: string };
  }): CalendarEvent => ({
    id: g.id,
    title: g.summary ?? '',
    start: g.start?.date ?? g.start?.dateTime ?? '',
    end: g.end?.date ?? g.end?.dateTime ?? '',
    allDay: !!g.start?.date,
    location: g.location,
    description: g.description,
    link: g.htmlLink,
    ...(g.status === 'cancelled' ? { cancelled: true } : {}),
    recurringEventId: g.recurringEventId,
    originalStart: g.originalStartTime?.date ?? g.originalStartTime?.dateTime,
  });
  return {
    async exchangeCode(code, config) {
      const res = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          code,
          client_id: config.clientId,
          client_secret: config.clientSecret,
          redirect_uri: config.redirectUri,
          grant_type: 'authorization_code',
        }),
      });
      const body = (await json(res)) as { refresh_token?: string };
      return { refreshToken: body.refresh_token ?? null };
    },
    async accessToken(refreshToken, config, grant) {
      // Unscoped callers never reuse a grant belonging to another church.
      const key = grant && `${grantHash(refreshToken)}:${createHash('sha256').update(JSON.stringify([grant, config])).digest('hex')}`;
      const cached = key ? tokens.get(key) : undefined;
      if (cached && cached.expiresAt > now().getTime()) return cached.token;
      for (const [k, value] of tokens) if (value.expiresAt <= now().getTime()) tokens.delete(k);
      for (const [k, flight] of refreshes) if (flight.until <= now().getTime()) refreshes.delete(k);
      const inProgress = key ? refreshes.get(key) : undefined;
      if (inProgress) return inProgress.pending;
      const refresh = async () => {
        const startedAt = now().getTime();
        const res = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: { 'content-type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            refresh_token: refreshToken,
            client_id: config.clientId,
            client_secret: config.clientSecret,
            grant_type: 'refresh_token',
          }),
        });
        if (res.status === 400 || res.status === 401) {
          const text = await res.text();
          if (text.includes('invalid_grant')) throw new GoogleAuthRevoked();
          throw new Error(`token ${res.status}: ${text.slice(0, 200)}`);
        }
        const body = (await json(res)) as { access_token?: string; expires_in?: number };
        if (typeof body.access_token !== 'string' || !body.access_token) throw new Error('Google returned no access token');
        const expiresAt = typeof body.expires_in === 'number' ? startedAt + body.expires_in * 1000 - 60_000 : NaN;
        if (key && refreshes.get(key)?.pending === pending && Number.isFinite(expiresAt) && expiresAt > now().getTime()) {
          if (tokens.size >= 128) tokens.delete(tokens.keys().next().value!);
          tokens.set(key, { token: body.access_token, expiresAt });
        }
        return body.access_token;
      };
      const pending = refresh();
      if (key) refreshes.set(key, { pending, until: now().getTime() + 60_000 });
      try {
        return await pending;
      } finally {
        if (key && refreshes.get(key)?.pending === pending) refreshes.delete(key);
      }
    },
    async calendars(token) {
      const res = await fetch(`${api}/users/me/calendarList?minAccessRole=writer`, {
        headers: { authorization: `Bearer ${token}` },
      });
      const body = (await json(res, token)) as { items?: { id: string; summary: string; primary?: boolean }[] };
      return (body.items ?? []).map((c) => ({ id: c.id, name: c.summary, primary: c.primary === true }));
    },
    async events(token, calendarId, from, to) {
      const params = new URLSearchParams({
        timeMin: from.toISOString(),
        timeMax: to.toISOString(),
        singleEvents: 'true',
        orderBy: 'startTime',
        maxResults: '250',
      });
      const res = await fetch(`${api}/calendars/${encodeURIComponent(calendarId)}/events?${params}`, {
        headers: { authorization: `Bearer ${token}` },
      });
      const body = (await json(res, token)) as { items?: Parameters<typeof fromGoogle>[0][] };
      return (body.items ?? []).map(fromGoogle);
    },
    async upsert(token, calendarId, event) {
      const base = `${api}/calendars/${encodeURIComponent(calendarId)}/events`;
      const res = await fetch(event.id ? `${base}/${encodeURIComponent(event.id)}` : base, {
        method: event.id ? 'PATCH' : 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
        body: JSON.stringify(toGoogle(event)),
      });
      return fromGoogle((await json(res, token)) as Parameters<typeof fromGoogle>[0]);
    },
    async get(token, calendarId, eventId) {
      const res = await fetch(
        `${api}/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`,
        { headers: { authorization: `Bearer ${token}` } },
      );
      if (res.status === 404 || res.status === 410) return null;
      return fromGoogle((await json(res, token)) as Parameters<typeof fromGoogle>[0]);
    },
    async remove(token, calendarId, eventId) {
      const res = await fetch(
        `${api}/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`,
        { method: 'DELETE', headers: { authorization: `Bearer ${token}` } },
      );
      if (res.status !== 404 && res.status !== 410) await json(res, token);
    },
    async revoke(refreshToken) {
      const prefix = `${grantHash(refreshToken)}:`;
      const clearGrant = () => {
        for (const key of tokens.keys()) if (key.startsWith(prefix)) tokens.delete(key);
        for (const key of refreshes.keys()) if (key.startsWith(prefix)) refreshes.delete(key);
      };
      clearGrant();
      try {
        await fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(refreshToken)}`, { method: 'POST' });
      } finally {
        // A refresh started while revoke was waiting must not refill the grant.
        clearGrant();
      }
    },
  };
}

/** `YYYY-MM` of an event start, in UTC+8 like the cache months. */
export function monthOf(start: string): string {
  if (/^\d{4}-\d{2}-\d{2}$/.test(start)) return start.slice(0, 7);
  const t = Date.parse(start);
  return Number.isNaN(t) ? start.slice(0, 7) : new Date(t + 8 * 3600e3).toISOString().slice(0, 7);
}

/**
 * Every cache month (UTC+8 `YYYY-MM`) an event from [start] to [end]
 * overlaps, the way Google matches it to a month: the end is exclusive, so
 * an all-day event ending on the 1st, or a timed one ending at midnight,
 * is not in that month. Without a usable end, the start's month.
 */
export function monthsOf(start: string, end?: string): string[] {
  const first = monthOf(start);
  if (!/^\d{4}-\d{2}$/.test(first)) return [first];
  const t = end === undefined ? NaN : /^\d{4}-\d{2}-\d{2}$/.test(end) ? Date.parse(`${end}T00:00:00+08:00`) : Date.parse(end);
  const last = Number.isNaN(t) ? first : monthOf(new Date(t - 1).toISOString());
  const months = [first];
  let [y, m] = first.split('-').map(Number);
  for (;;) {
    [y, m] = m === 12 ? [y + 1, 1] : [y, m + 1];
    const next = `${y}-${String(m).padStart(2, '0')}`;
    if (next > last) return months;
    months.push(next);
  }
}
