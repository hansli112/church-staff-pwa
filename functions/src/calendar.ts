import { createHash, randomBytes } from 'node:crypto';

import { FieldValue, Timestamp, type DocumentSnapshot } from 'firebase-admin/firestore';

import { churchAccess, isChurchOpen } from './access.js';
import { fail, type Caller, type Deps } from './common.js';
import { isEventGroup, powersOf } from './powers.js';
import { cancelWithEvent, followEdit, inclusiveEnd, isEvent, restoreOnto } from './eventRosters.js';
import { seal, unseal } from './sealing.js';
import { notify, type WebhookDeps } from './webhook.js';
import { dateKeyIn, instantOf, instantOfTime, LOCAL_TIME, localIso, timeZoneOf, type ChurchTimeZone } from './timeZones.js';
import { loggable } from './redact.js';

/**
 * 行事曆: a church admin connects one Google Calendar. The backend keeps the
 * refresh token (sealed, in calendarTokens/{cid}, which no client can
 * read), reads through a 10-minute cache shared by everyone in
 * the church, and writes for admins and calendar-editors.
 *
 * Times go to the app on the church's clock, with its offset, so the app
 * shows them as they are; the app sends them on that clock without one
 * (older apps: with one), and they are read in the church's time zone.
 *
 * Scopes: calendar.events (read/write events), calendar.calendarlist.readonly
 * (let the admin pick which calendar). Sign-in with Google never asks for
 * these; only the admin who connects sees the consent screen, where each
 * can be ticked off: a grant without both is not kept.
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
  /** [scopes]: what the consent granted, when Google says. */
  exchangeCode(code: string, config: OAuthConfig): Promise<{ refreshToken: string | null; scopes?: string[] }>;
  /** Throws GoogleAuthRevoked when the refresh token no longer works, or no longer grants SCOPES. */
  accessToken(refreshToken: string, config: OAuthConfig, grant?: { churchId: string; revision: string }): Promise<string>;
  calendars(accessToken: string): Promise<{ id: string; name: string; primary: boolean; timeZone?: string }[]>;
  events(accessToken: string, calendarId: string, from: Date, to: Date): Promise<CalendarEvent[]>;
  upsert(accessToken: string, calendarId: string, event: CalendarEvent): Promise<CalendarEvent>;
  /** One event, or null when it is gone. */
  get(accessToken: string, calendarId: string, eventId: string): Promise<CalendarEvent | null>;
  remove(accessToken: string, calendarId: string, eventId: string): Promise<void>;
  /** Gives an event, or a whole recurring series, to [group] ('' the church's). */
  setGroup(accessToken: string, calendarId: string, eventId: string, group: string): Promise<void>;
  revoke(refreshToken: string): Promise<void>;
}

export class GoogleAuthRevoked extends Error {}

/** False when Google says what [scope] (space-separated) grants and it is not all of SCOPES. */
const grantsAll = (scope: unknown) => typeof scope !== 'string' || SCOPES.every((s) => scope.split(' ').includes(s));

/** The fields the app shows and edits. */
export interface CalendarEvent {
  id?: string;
  title: string;
  /** All-day: `YYYY-MM-DD`; timed: ISO instant (see [inZone]). */
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
  /** Whose it is (powers.ts isEventGroup): '' or missing the church's, else a group's. */
  group?: string;
}

/** Changes go out to the church's webhook, hence WebhookDeps. */
export type CalDeps = WebhookDeps & { google: GoogleApi; config: OAuthConfig };

/** The OAuth state's first letter: where the browser goes back to. */
const startedIn = { app: 'a', web: 'w' } as const;

/**
 * Starts connecting: a Google consent URL bound to this admin and church.
 * `from: 'app'` when the phone app opens it in its own browser sheet, which
 * then ends on a page saying to go back rather than on the web app.
 */
export async function calendarAuthUrl(deps: CalDeps, caller: Caller | null, data: unknown) {
  const { cid: churchId, caller: c } = await churchAccess(deps, caller, data, 'admin');
  // Even when the state has expired by then, it says where to go back.
  const from = (data as { from?: unknown })?.from === 'app' ? startedIn.app : startedIn.web;
  const state = from + randomBytes(24).toString('base64url');
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
  const state = typeof query.state === 'string' ? query.state : '';
  const back = (result: string) =>
    state.startsWith(startedIn.app)
      ? `${deps.config.appUrl}/calendar-done.html?result=${result}`
      : `${deps.config.appUrl}/me/calendar?result=${result}`;
  const code = typeof query.code === 'string' ? query.code : '';
  if (!state || !/^[A-Za-z0-9_-]{16,64}$/.test(state)) return back('invalid');
  const ref = deps.db.doc(`calendarStates/${state}`);
  const grant = await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const expiresAt = snap.get('expiresAt') as Timestamp | undefined;
    // A repeated callback cannot exchange again or cancel the first callback.
    if (snap.get('exchanging') === true) return null;
    if (!snap.exists || !expiresAt || expiresAt.toMillis() < deps.now().getTime()) {
      tx.delete(ref);
      return null;
    }
    const churchId = snap.get('cid') as string;
    const uid = snap.get('uid') as string;
    const [church, member] = await tx.getAll(
      deps.db.doc(`churches/${churchId}`), deps.db.doc(`churches/${churchId}/members/${uid}`),
    );
    const authorized = isChurchOpen(church) && member.get('role') === 'admin';
    // Reserve once, but keep it cancellable while the provider is pending.
    if (authorized && code) tx.update(ref, { exchanging: true });
    else tx.delete(ref);
    return { churchId, uid, authorized };
  });
  if (!grant) return back('expired');
  if (!code || !grant.authorized) return back('denied');
  let refreshToken: string | null;
  let scopes: string[] | undefined;
  try {
    ({ refreshToken, scopes } = await deps.google.exchangeCode(code, deps.config));
  } catch (e) {
    await ref.delete();
    // A used or stale code (a reloaded page, a double tap): let them try again.
    console.warn('calendarCallback: code refused', loggable(e));
    return back('failed');
  }
  if (!refreshToken) {
    await ref.delete();
    return back('failed');
  }
  // A permission ticked off on Google's consent screen: the calendar would
  // connect and then fail to read (or list) anything.
  if (scopes && !grantsAll(scopes.join(' '))) {
    await ref.delete();
    try {
      await deps.google.revoke(refreshToken);
    } catch (e) {
      console.warn('calendarCallback: partial grant revocation failed', loggable(e));
    }
    return back('scopes');
  }
  const { churchId, uid } = grant;
  let installed = false;
  try {
    installed = await deps.db.runTransaction(async (tx) => {
      const [current, church, member] = await tx.getAll(
        ref, deps.db.doc(`churches/${churchId}`), deps.db.doc(`churches/${churchId}/members/${uid}`),
      );
      // The provider exchange can take time. These reads serialize the grant
      // installation with cancellation, demotion, removal or church closure.
      tx.delete(ref);
      if (!current.exists || !isChurchOpen(church) || member.get('role') !== 'admin') return false;
      tx.set(deps.db.doc(`calendarTokens/${churchId}`), {
        token: seal(refreshToken, deps.config.tokenKey),
        connectedBy: uid,
        connectedAt: FieldValue.serverTimestamp(),
        calendarId: null,
      });
      tx.set(deps.db.doc(`churches/${churchId}/settings/calendar`), {
        connected: true,
        needsReconnect: false,
        calendarId: null,
        calendarName: null,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    return back(installed ? 'connected' : 'denied');
  } finally {
    if (!installed) {
      try {
        await ref.delete();
      } finally {
        try {
          await deps.google.revoke(refreshToken);
        } catch (e) {
          // Never install an unauthorized token, even when Google is unreachable.
          console.warn('calendarCallback: unused grant revocation failed', loggable(e));
        }
      }
    }
  }
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
    console.warn(`calendar access ${churchId}`, loggable(e));
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
  await forgetGrant(deps, churchId);
}

async function forgetGrant(deps: CalDeps, churchId: string, connectorUid?: string) {
  const tokenDoc = await deps.db.runTransaction(async (tx) => {
    const ref = deps.db.doc(`calendarTokens/${churchId}`);
    const current = await tx.get(ref);
    if (connectorUid && (!current.exists || current.get('connectedBy') !== connectorUid)) return null;
    // Unlink before waiting on Google, and never unlink a newer connector's
    // grant because a delayed member trigger read an older token earlier.
    tx.delete(ref);
    tx.delete(deps.db.doc(`churches/${churchId}/settings/calendar`));
    return current;
  });
  if (!tokenDoc) return false;
  await clearCache(deps, churchId);
  const states = await deps.db.collection('calendarStates').where('cid', '==', churchId).get();
  await Promise.all(states.docs.map((d) => d.ref.delete()));
  if (tokenDoc.exists) {
    try {
      await deps.google.revoke(unseal(tokenDoc.get('token') as string, deps.config.tokenKey));
    } catch {
      // Already revoked on Google's side; it has still been forgotten here.
    }
  }
  return tokenDoc.exists;
}

/** Clears [uid]'s unfinished consents, and releases a grant they connected. */
export async function releaseCalendarIfConnector(deps: CalDeps, churchId: string, uid: string) {
  const states = await deps.db.collection('calendarStates').where('cid', '==', churchId).get();
  await Promise.all(states.docs.filter((d) => d.get('uid') === uid).map((d) => d.ref.delete()));
  return forgetGrant(deps, churchId, uid);
}

/** Drops the church's cached [months], or every cached month. */
export async function clearCache(deps: Deps, churchId: string, months?: Iterable<string>) {
  if (months) {
    await Promise.all([...months].map((m) => deps.db.doc(`calendarCache/${churchId}_${m}`).delete()));
    return;
  }
  const snap = await deps.db.collection('calendarCache').where('cid', '==', churchId).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

function monthRange(month: string, timeZone: ChurchTimeZone) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) fail('invalid-argument', 'unknown');
  const [y, m] = month.split('-').map(Number);
  const next = m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`;
  // The church's month. Google returns every event that overlaps it (ends
  // after `from`, starts before `to`), so one event can be in the cache of
  // several months: see monthsOf.
  return { from: new Date(instantOf(timeZone, `${month}-01`)), to: new Date(instantOf(timeZone, `${next}-01`)) };
}

/** [e] with its times on [timeZone]'s clock, with the offset: what the app and the webhook get. */
export function inZone(e: CalendarEvent, timeZone: ChurchTimeZone): CalendarEvent {
  if (e.allDay) return e;
  const local = (t: string) => (Number.isNaN(Date.parse(t)) ? t : localIso(timeZone, Date.parse(t)));
  return { ...e, start: local(e.start), end: local(e.end) };
}

/** A timed event's start or end from the app: on the church's clock, or (older apps) an instant. */
function fromApp(t: string, allDay: boolean, timeZone: ChurchTimeZone) {
  if (allDay || !LOCAL_TIME.test(t)) return t;
  const at = instantOf(timeZone, t);
  if (Number.isNaN(at)) fail('invalid-argument', 'unknown');
  return new Date(at).toISOString();
}

/**
 * Events of one month. Everyone in the church shares a 10-minute cached
 * copy; simultaneous cold misses can still make separate Google calls.
 */
export async function calendarEvents(deps: CalDeps, caller: Caller | null, data: unknown) {
  const { cid: churchId, church } = await churchAccess(deps, caller, data, 'member');
  const timeZone = timeZoneOf(church);
  const month = String((data as { month?: unknown })?.month ?? '');
  const { from, to } = monthRange(month, timeZone);
  const cacheRef = deps.db.doc(`calendarCache/${churchId}_${month}`);
  const cached = await cacheRef.get();
  const fetchedAt = cached.get('fetchedAt') as Timestamp | undefined;
  // One kept before the church's time zone changed (or before there were
  // any) has other times and another month.
  if (fetchedAt && deps.now().getTime() - fetchedAt.toMillis() < CACHE_MINUTES * 60e3 && cached.get('timeZone') === timeZone) {
    return { events: cached.get('events') as CalendarEvent[], cached: true };
  }
  const { token, calendarId } = await access(deps, churchId);
  if (!calendarId) fail('failed-precondition', 'unknown', 'noCalendar');
  // Google leaves out what an event does not have; Firestore refuses undefined.
  const events = (await deps.google.events(token, calendarId, from, to)).map(
    (e) => Object.fromEntries(Object.entries(inZone(e, timeZone)).filter(([, v]) => v !== undefined)) as unknown as CalendarEvent,
  );
  await cacheRef.set({ cid: churchId, month, timeZone, events, fetchedAt: Timestamp.fromDate(deps.now()) });
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
 * Create, update or delete one event: admins and calendar-editors (行政)
 * any, a group's 負責人 that group's (powers.ts, mayWriteEvent).
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
  const me = await churchAccess(deps, caller, data, 'member');
  // Admins and 行政 write any event; a 負責人 only their groups'. Anyone
  // else is refused before the calendar is asked anything.
  const editor = me.powers.writesAnyEvent;
  if (!me.powers.makesEvents) fail('permission-denied', 'permissionDenied');
  const churchId = me.cid;
  const timeZone = timeZoneOf(me.church);
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
  const may = (before: string | null, after: string | null) => {
    if (!me.powers.mayWriteEvent(before, after)) fail('permission-denied', 'permissionDenied');
  };
  // Whose an event is now, as Google has it: an edit or a delete is
  // judged by that, not by what the app says it was.
  const groupNow = async (id: string) => {
    const found = await deps.google.get(token, calendarId, id);
    if (!found || found.cancelled) fail('not-found', 'notFound');
    return { found, group: found.group ?? '' };
  };
  if (input.op === 'delete') {
    if (typeof input.eventId !== 'string') fail('invalid-argument', 'unknown');
    // What it was, for the webhook: Google's DELETE returns nothing.
    const found = editor
      ? await deps.google.get(token, calendarId, input.eventId).catch(() => null)
      : (await groupNow(input.eventId)).found;
    if (!editor) may(found?.group ?? '', null);
    const before = found && inZone(found, timeZone);
    await deps.google.remove(token, calendarId, input.eventId);
    await rosterStep(`cancel ${churchId}/ev_${input.eventId}`, () => cancelWithEvent(deps, churchId, input.eventId as string));
    spans.push(span(input.event), span(before));
    notice = { action: 'deleted', event: before ?? { ...input.event, id: input.eventId } };
  } else if (input.op === 'upsert') {
    const e = input.event;
    if (!e || typeof e.title !== 'string' || !e.title.trim() || typeof e.start !== 'string' || typeof e.end !== 'string') {
      fail('invalid-argument', 'unknown');
    }
    const allDay = e.allDay === true;
    if (e.group !== undefined && !isEventGroup(e.group)) fail('invalid-argument', 'unknown');
    // Left out (an older app, which knows no groups), an edit keeps whose
    // it is and a new event is the church's.
    const group = e.group;
    const before = typeof e.id === 'string' && (!editor || group !== undefined) ? await groupNow(e.id) : null;
    if (!editor) may(before?.group ?? null, group ?? before?.group ?? '');
    // Undoing a delete takes the cancelled roster along: only one of an
    // event the caller could have deleted.
    if (!editor && typeof input.restoreRosterOf === 'string' && /^[A-Za-z0-9_-]{1,1024}$/.test(input.restoreRosterOf)) {
      const r = await deps.db.doc(`churches/${churchId}/rosters/ev_${input.restoreRosterOf}`).get();
      if (r.exists) may((r.get('group') as string | undefined) ?? '', null);
    }
    // As Google gives it back; the app and the webhook get it on the church's clock.
    const saved = await deps.google.upsert(token, calendarId, {
      id: typeof e.id === 'string' ? e.id : undefined,
      title: e.title.trim().slice(0, 200),
      start: fromApp(e.start, allDay, timeZone),
      end: fromApp(e.end, allDay, timeZone),
      allDay,
      location: typeof e.location === 'string' ? e.location.slice(0, 300) : undefined,
      description: typeof e.description === 'string' ? e.description.slice(0, 4000) : undefined,
      ...(group !== undefined ? { group } : {}),
    });
    // A day of a recurring event given to another group: the series goes
    // with it (重複活動照系列存), so its other days are that group's too.
    const series = saved.recurringEventId;
    if (series && group !== undefined && group !== (before?.group ?? '')) {
      await deps.google.setGroup(token, calendarId, series, group);
    }
    result = inZone(saved, timeZone);
    spans.push(span(e));
    if (typeof e.id === 'string') {
      await rosterStep(`follow ${churchId}/ev_${e.id}`, () => followEdit(deps, churchId, timeZone, saved, me.caller.uid));
    }
    const restore = input.restoreRosterOf;
    if (typeof restore === 'string') {
      await rosterStep(`restore ${churchId}/ev_${restore}`, () => restoreOnto(deps, churchId, timeZone, restore, saved));
    }
    notice = { action: typeof e.id === 'string' ? 'updated' : 'created', event: result };
  } else {
    fail('invalid-argument', 'unknown');
  }
  const months = new Set(spans.flatMap((s) => (s ? monthsOf(s.start, s.end, timeZone) : [])));
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

/**
 * An event's roster just made in the app by [by] (#84). The rules let a
 * group's 負責人 make one for their group's events by the group it says,
 * which only the backend can check against the event in Google: one made
 * by someone who may not write every event, saying a group its event does
 * not have (or of an event deleted), is removed.
 */
export async function checkEventRosterGroup(deps: CalDeps, churchId: string, r: DocumentSnapshot, by: string | undefined) {
  const group = r.get('group');
  if (!by || !isEvent(r) || typeof group !== 'string' || !group) return;
  const member = await deps.db.doc(`churches/${churchId}/members/${by}`).get();
  if (powersOf(member.data() ?? {}).writesAnyEvent) return;
  const { token, calendarId } = await access(deps, churchId);
  const e = calendarId ? await deps.google.get(token, calendarId, r.get('eventId') as string) : null;
  // Not found, the sync cancels it as it does any roster whose event went.
  if (!e || (!e.cancelled && (e.group ?? '') === group)) return;
  console.warn(`event roster ${churchId}/${r.id}: says ${group}, its event does not; removed`);
  await deps.db.runTransaction(async (tx) => {
    const now = await tx.get(r.ref);
    if (now.exists && now.createTime?.isEqual(r.createTime!)) tx.delete(r.ref);
  });
}

/**
 * Runs a step on an event's roster after Google has the change. A failure
 * is logged, never thrown: the event changed, so the call must not look
 * failed (an undo retried would make the event twice).
 */
async function rosterStep(what: string, step: () => Promise<void>) {
  try {
    await step();
  } catch (e) {
    console.error(`event roster: ${what} failed`, loggable(e));
  }
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
    // Whose it is, kept with the event so an edit in Google keeps it; left
    // out, a PATCH keeps what it had.
    ...(e.group !== undefined ? { extendedProperties: { private: { marthaGroup: e.group } } } : {}),
    // PATCH merges nested objects: clear the opposite type explicitly.
    // New events have no previous date type, so POST keeps the normal shape.
    start: e.allDay ? { date: e.start, ...(e.id ? { dateTime: null } : {}) } : { dateTime: e.start, ...(e.id ? { date: null } : {}) },
    end: e.allDay ? { date: e.end, ...(e.id ? { dateTime: null } : {}) } : { dateTime: e.end, ...(e.id ? { date: null } : {}) },
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
    extendedProperties?: { private?: { marthaGroup?: string } };
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
    ...(isEventGroup(g.extendedProperties?.private?.marthaGroup) && g.extendedProperties.private.marthaGroup
      ? { group: g.extendedProperties.private.marthaGroup }
      : {}),
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
      const body = (await json(res)) as { refresh_token?: string; scope?: string };
      return {
        refreshToken: body.refresh_token ?? null,
        ...(typeof body.scope === 'string' ? { scopes: body.scope.split(' ').filter(Boolean) } : {}),
      };
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
        const body = (await json(res)) as { access_token?: string; expires_in?: number; scope?: string };
        if (typeof body.access_token !== 'string' || !body.access_token) throw new Error('Google returned no access token');
        // Connected before the callback checked what was ticked: it cannot
        // read the calendar, so it is reconnected like a revoked one.
        if (!grantsAll(body.scope)) throw new GoogleAuthRevoked();
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
      const body = (await json(res, token)) as { items?: { id: string; summary: string; primary?: boolean; timeZone?: string }[] };
      return (body.items ?? []).map((c) => ({ id: c.id, name: c.summary, primary: c.primary === true, timeZone: c.timeZone }));
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
    async setGroup(token, calendarId, eventId, group) {
      const res = await fetch(
        `${api}/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`,
        {
          method: 'PATCH',
          headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
          body: JSON.stringify({ extendedProperties: { private: { marthaGroup: group } } }),
        },
      );
      await json(res, token);
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

/** `YYYY-MM` of an event start in the church's time zone, like the cache months. */
export function monthOf(start: string, timeZone: ChurchTimeZone): string {
  const t = instantOfTime(timeZone, start);
  return Number.isNaN(t) ? start.slice(0, 7) : dateKeyIn(timeZone, new Date(t)).slice(0, 7);
}

/**
 * Every cache month (the church's `YYYY-MM`) an event from [start] to
 * [end] overlaps, the way Google matches it to a month: the end is
 * exclusive, so an all-day event ending on the 1st, or a timed one ending
 * at midnight, is not in that month. Without a usable end, the start's
 * month.
 */
export function monthsOf(start: string, end: string | undefined, timeZone: ChurchTimeZone): string[] {
  const first = monthOf(start, timeZone);
  if (!/^\d{4}-\d{2}$/.test(first)) return [first];
  const t = end === undefined ? NaN : instantOfTime(timeZone, end);
  const last = Number.isNaN(t) ? first : dateKeyIn(timeZone, new Date(t - 1)).slice(0, 7);
  const months = [first];
  let [y, m] = first.split('-').map(Number);
  for (;;) {
    [y, m] = m === 12 ? [y + 1, 1] : [y, m + 1];
    const next = `${y}-${String(m).padStart(2, '0')}`;
    if (next > last) return months;
    months.push(next);
  }
}
