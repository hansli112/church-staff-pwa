import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { fail, requireCaller, type Caller, type Deps } from './common.js';
import { deliver } from './webhook.js';

/**
 * 行事曆: a church admin connects one Google Calendar. The backend keeps the
 * refresh token (AES-256-GCM encrypted, in calendarTokens/{cid}, which no
 * client can read), reads through a 10-minute cache shared by everyone in
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
  /** 32-byte key, base64. */
  tokenKey: string;
}

/** Google's HTTP APIs, injectable for tests. */
export interface GoogleApi {
  exchangeCode(code: string, config: OAuthConfig): Promise<{ refreshToken: string | null }>;
  /** Throws GoogleAuthRevoked when the refresh token no longer works. */
  accessToken(refreshToken: string, config: OAuthConfig): Promise<string>;
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
}

export function encrypt(plain: string, keyB64: string) {
  const key = Buffer.from(keyB64, 'base64');
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const body = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), body].map((b) => b.toString('base64')).join('.');
}

export function decrypt(sealed: string, keyB64: string) {
  const [iv, tag, body] = sealed.split('.').map((p) => Buffer.from(p, 'base64'));
  const decipher = createDecipheriv('aes-256-gcm', Buffer.from(keyB64, 'base64'), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(body), decipher.final()]).toString('utf8');
}

export type CalDeps = Deps & { google: GoogleApi; config: OAuthConfig };

const cid = (data: unknown) => {
  const v = (data as { churchId?: unknown })?.churchId;
  if (typeof v !== 'string' || !/^[A-Za-z0-9]{1,64}$/.test(v)) fail('invalid-argument', 'unknown');
  return v;
};

async function membership(deps: Deps, churchId: string, c: Caller) {
  const [church, member] = await Promise.all([
    deps.db.doc(`churches/${churchId}`).get(),
    deps.db.doc(`churches/${churchId}/members/${c.uid}`).get(),
  ]);
  if (church.get('status') !== 'active' || !member.exists) fail('permission-denied', 'permissionDenied');
  const admin = member.get('role') === 'admin';
  const editor = admin || ((member.get('groups') as string[]) ?? []).includes('calendar-editors');
  return { admin, editor, name: (member.get('name') as string | undefined) || null, churchName: church.get('name') as string };
}

/** Starts connecting: a Google consent URL bound to this admin and church. */
export async function calendarAuthUrl(deps: CalDeps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const churchId = cid(data);
  if (!(await membership(deps, churchId, c)).admin) fail('permission-denied', 'permissionDenied');
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
    token: encrypt(refreshToken, deps.config.tokenKey),
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

async function access(deps: CalDeps, churchId: string) {
  const tokenDoc = await deps.db.doc(`calendarTokens/${churchId}`).get();
  if (!tokenDoc.exists) fail('failed-precondition', 'unknown', 'notConnected');
  try {
    const token = await deps.google.accessToken(decrypt(tokenDoc.get('token') as string, deps.config.tokenKey), deps.config);
    return { token, calendarId: tokenDoc.get('calendarId') as string | null };
  } catch (e) {
    if (e instanceof GoogleAuthRevoked) {
      await deps.db.doc(`churches/${churchId}/settings/calendar`).set({ needsReconnect: true }, { merge: true });
      fail('failed-precondition', 'unknown', 'reconnect');
    }
    throw e;
  }
}

export async function calendarList(deps: CalDeps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const churchId = cid(data);
  if (!(await membership(deps, churchId, c)).admin) fail('permission-denied', 'permissionDenied');
  const { token } = await access(deps, churchId);
  return { calendars: await deps.google.calendars(token) };
}

export async function calendarSelect(deps: CalDeps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const churchId = cid(data);
  if (!(await membership(deps, churchId, c)).admin) fail('permission-denied', 'permissionDenied');
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
  const c = requireCaller(caller);
  const churchId = cid(data);
  if (!(await membership(deps, churchId, c)).admin) fail('permission-denied', 'permissionDenied');
  await forgetCalendar(deps, churchId);
  return {};
}

/**
 * Revokes the church's Google grant and deletes the token, settings and
 * cache. Used when an admin disconnects, when the church is purged, and
 * when the person who connected it stops being an admin there (their
 * Google account must not stay reachable through the church).
 */
export async function forgetCalendar(deps: CalDeps, churchId: string) {
  const tokenDoc = await deps.db.doc(`calendarTokens/${churchId}`).get();
  if (tokenDoc.exists) {
    try {
      await deps.google.revoke(decrypt(tokenDoc.get('token') as string, deps.config.tokenKey));
    } catch {
      // Already revoked on Google's side; still forget it here.
    }
    await tokenDoc.ref.delete();
  }
  await deps.db.doc(`churches/${churchId}/settings/calendar`).delete();
  await clearCache(deps, churchId);
}

/** forgetCalendar when [uid] is the admin who connected the church's calendar. */
export async function releaseCalendarIfConnector(deps: CalDeps, churchId: string, uid: string) {
  const tokenDoc = await deps.db.doc(`calendarTokens/${churchId}`).get();
  if (!tokenDoc.exists || tokenDoc.get('connectedBy') !== uid) return false;
  await forgetCalendar(deps, churchId);
  return true;
}

async function clearCache(deps: Deps, churchId: string, month?: string) {
  const q = deps.db.collection('calendarCache').where('cid', '==', churchId);
  const snap = await (month ? q.where('month', '==', month) : q).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

function monthRange(month: string) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) fail('invalid-argument', 'unknown');
  const [y, m] = month.split('-').map(Number);
  // UTC+8 month boundaries, with a day of slack on both sides for timed
  // events near midnight.
  return { from: new Date(Date.UTC(y, m - 1, 1) - 8 * 3600e3), to: new Date(Date.UTC(y, m, 1) - 8 * 3600e3) };
}

/**
 * Events of one month. Everyone in the church shares one cached copy, so
 * many people opening the calendar at once make one Google call.
 */
export async function calendarEvents(deps: CalDeps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const churchId = cid(data);
  await membership(deps, churchId, c);
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
  const events = await deps.google.events(token, calendarId, from, to);
  await cacheRef.set({ cid: churchId, month, events, fetchedAt: Timestamp.fromDate(deps.now()) });
  return { events, cached: false };
}

/** Create, update or delete one event (admins and calendar-editors). */
export async function calendarWrite(deps: CalDeps, caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const churchId = cid(data);
  const me = await membership(deps, churchId, c);
  if (!me.editor) fail('permission-denied', 'permissionDenied');
  const input = data as { op?: unknown; event?: Partial<CalendarEvent>; eventId?: unknown };
  const { token, calendarId } = await access(deps, churchId);
  if (!calendarId) fail('failed-precondition', 'unknown', 'noCalendar');
  let result: CalendarEvent | null = null;
  let notice: { action: 'created' | 'updated' | 'deleted'; event: Partial<CalendarEvent> } | null = null;
  const months = new Set<string>();
  const previous = (data as { previousStart?: unknown })?.previousStart;
  if (typeof previous === 'string') months.add(monthOf(previous));
  if (input.op === 'delete') {
    if (typeof input.eventId !== 'string') fail('invalid-argument', 'unknown');
    const start = typeof input.event?.start === 'string' ? input.event.start : '';
    // What it was, for the webhook: Google's DELETE returns nothing.
    const before = await deps.google.get(token, calendarId, input.eventId).catch(() => null);
    await deps.google.remove(token, calendarId, input.eventId);
    if (start) months.add(monthOf(start));
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
    months.add(monthOf(e.start));
    notice = { action: typeof e.id === 'string' ? 'updated' : 'created', event: result };
  } else {
    fail('invalid-argument', 'unknown');
  }
  // Drop the cached months (old and new, for a moved event) so everyone
  // sees the change on their next read.
  await Promise.all([...months].map((m) => deps.db.doc(`calendarCache/${churchId}_${m}`).delete()));
  if (notice) {
    // After Google has it. A webhook failure is recorded, never thrown.
    await deliver(
      { ...deps, secretKey: deps.config.tokenKey },
      churchId,
      `calendar.${notice.action}`,
      calendarPayload(notice.action, notice.event, {
        churchId,
        churchName: me.churchName,
        actorUid: c.uid,
        actorName: me.name,
      }),
    );
  }
  return { event: result };
}

/** The time zone every church's calendar is shown in. */
export const CHURCH_TIME_ZONE = 'Asia/Taipei';

/**
 * The webhook body for a calendar change, in the self-host version's shape
 * so existing n8n flows keep working: every key always present, an
 * all-day event's end the last day it covers (Google's is the day after).
 */
export function calendarPayload(
  action: 'created' | 'updated' | 'deleted',
  e: Partial<CalendarEvent>,
  who: { churchId: string; churchName: string; actorUid: string; actorName: string | null },
) {
  const allDay = e.allDay === true;
  return {
    action,
    source: 'martha',
    churchId: who.churchId,
    churchName: who.churchName,
    timeZone: CHURCH_TIME_ZONE,
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
  return new Date(Date.parse(`${end}T00:00:00Z`) - 86400e3).toISOString().slice(0, 10);
}

/** The real Google APIs over fetch. */
export function googleApi(): GoogleApi {
  const api = 'https://www.googleapis.com/calendar/v3';
  const json = async (res: Response) => {
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
    summary?: string;
    location?: string;
    description?: string;
    htmlLink?: string;
    start: { date?: string; dateTime?: string };
    end: { date?: string; dateTime?: string };
  }): CalendarEvent => ({
    id: g.id,
    title: g.summary ?? '',
    start: g.start.date ?? g.start.dateTime ?? '',
    end: g.end.date ?? g.end.dateTime ?? '',
    allDay: !!g.start.date,
    location: g.location,
    description: g.description,
    link: g.htmlLink,
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
    async accessToken(refreshToken, config) {
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
      return ((await json(res)) as { access_token: string }).access_token;
    },
    async calendars(token) {
      const res = await fetch(`${api}/users/me/calendarList?minAccessRole=writer`, {
        headers: { authorization: `Bearer ${token}` },
      });
      const body = (await json(res)) as { items?: { id: string; summary: string; primary?: boolean }[] };
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
      const body = (await json(res)) as { items?: Parameters<typeof fromGoogle>[0][] };
      return (body.items ?? []).map(fromGoogle);
    },
    async upsert(token, calendarId, event) {
      const base = `${api}/calendars/${encodeURIComponent(calendarId)}/events`;
      const res = await fetch(event.id ? `${base}/${encodeURIComponent(event.id)}` : base, {
        method: event.id ? 'PATCH' : 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
        body: JSON.stringify(toGoogle(event)),
      });
      return fromGoogle((await json(res)) as Parameters<typeof fromGoogle>[0]);
    },
    async get(token, calendarId, eventId) {
      const res = await fetch(
        `${api}/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`,
        { headers: { authorization: `Bearer ${token}` } },
      );
      if (res.status === 404 || res.status === 410) return null;
      return fromGoogle((await json(res)) as Parameters<typeof fromGoogle>[0]);
    },
    async remove(token, calendarId, eventId) {
      const res = await fetch(
        `${api}/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`,
        { method: 'DELETE', headers: { authorization: `Bearer ${token}` } },
      );
      if (res.status !== 404 && res.status !== 410) await json(res);
    },
    async revoke(refreshToken) {
      await fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(refreshToken)}`, { method: 'POST' });
    },
  };
}

/** `YYYY-MM` of an event start, in UTC+8 like the cache months. */
export function monthOf(start: string): string {
  if (/^\d{4}-\d{2}-\d{2}$/.test(start)) return start.slice(0, 7);
  const t = Date.parse(start);
  return Number.isNaN(t) ? start.slice(0, 7) : new Date(t + 8 * 3600e3).toISOString().slice(0, 7);
}
