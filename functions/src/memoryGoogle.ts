import { GoogleAuthRevoked, type CalendarEvent, type GoogleApi } from './calendar.js';

/**
 * Google Calendar in memory, at the same seam as googleApi: one account's
 * calendars and their events. For the Functions' tests, and for the
 * emulator (the app's contract tests, and running locally), which never
 * reaches Google.
 *
 * - Consent: code `used` is refused, as Google refuses a code twice; any
 *   other is granted, with refresh token `refresh-<code>`, until revoked.
 * - A new event gets ID `new-1`, `new-2`… A deleted one stays, cancelled,
 *   as in Google's trash: a get still finds it.
 * - goDown(): Google out of reach. revokeAll(): every grant revoked.
 *   unshare(): the calendar no longer shared with whoever connected it,
 *   so its events can be neither listed nor found.
 *
 * The emulator runs each function on its own: what one writes, another
 * does not see.
 */
export function memoryGoogle(events: CalendarEvent[] = []) {
  const calls = { events: 0, get: 0, removed: [] as string[], revoked: [] as string[] };
  const revoked = new Set<string>();
  let down = false;
  let allRevoked = false;
  let unshared = false;
  let made = 0;
  // Days of a series changed on their own, which no longer follow it.
  const alone = new Set<string>();
  const reach = () => {
    if (down) throw new Error('google unreachable');
  };
  const at = (t: string) => Date.parse(t);
  const google: GoogleApi = {
    async exchangeCode(code) {
      reach();
      if (code === 'used') throw new Error('google 400: invalid_grant');
      // Consent again grants anew.
      revoked.delete(`refresh-${code}`);
      return { refreshToken: `refresh-${code}` };
    },
    async accessToken(refreshToken) {
      if (allRevoked || revoked.has(refreshToken)) throw new GoogleAuthRevoked();
      reach();
      return 'access';
    },
    async calendars() {
      reach();
      return [{ id: 'cal-1', name: '教會行事曆', primary: false }];
    },
    async events(_token, _calendarId, from, to) {
      calls.events++;
      reach();
      if (unshared) throw new Error('google 404: calendar not found');
      return events.filter((e) => !e.cancelled && at(e.start) < to.getTime() && at(e.end || e.start) > from.getTime());
    },
    async upsert(_token, _calendarId, e) {
      reach();
      const id = e.id ?? `new-${++made}`;
      if (e.id) alone.add(id);
      const i = events.findIndex((x) => x.id === id);
      const saved = { ...(i >= 0 ? events[i] : {}), ...e, id, link: `https://calendar.google.com/event?eid=${id}` };
      if (i >= 0) events[i] = saved;
      else events.push(saved);
      return saved;
    },
    async get(_token, _calendarId, id) {
      calls.get++;
      reach();
      return unshared ? null : (events.find((e) => e.id === id) ?? null);
    },
    async remove(_token, _calendarId, id) {
      reach();
      calls.removed.push(id);
      const e = events.find((x) => x.id === id);
      if (e) e.cancelled = true;
    },
    async setGroup(_token, _calendarId, id, group) {
      reach();
      // The series and its days that were not changed on their own, which
      // in Google follow the series.
      for (const e of events) {
        if (e.id === id || (e.recurringEventId === id && !alone.has(e.id!))) {
          if (group) e.group = group;
          else delete e.group;
        }
      }
    },
    async revoke(refreshToken) {
      calls.revoked.push(refreshToken);
      revoked.add(refreshToken);
    },
  };
  return {
    google,
    events,
    calls,
    goDown: () => void (down = true),
    revokeAll: () => void (allRevoked = true),
    unshare: () => void (unshared = true),
  };
}
