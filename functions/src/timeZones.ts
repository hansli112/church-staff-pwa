import type { DocumentSnapshot } from 'firebase-admin/firestore';

/**
 * A church's time zone (#73): one of these, by IANA id, east to west.
 * Cities whose clocks always agree, like New York and Toronto, list the US
 * one first: a phone in a zone not on the list gets the first city on its
 * clock (ChurchTimeZone.forDevice in the app).
 * Today, the evening reminders, the church link's fetch and the calendar's
 * months all go by it. ChurchTimeZone in app/lib/domain/church_time.dart is the
 * same list; testdata/time_zones.json holds both sides to it and to the
 * same clock changes.
 */
export const CHURCH_TIME_ZONES = [
  'Pacific/Auckland',
  'Australia/Sydney',
  'Australia/Melbourne',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Asia/Taipei',
  'Asia/Hong_Kong',
  'Asia/Singapore',
  'Asia/Kuala_Lumpur',
  'Europe/London',
  'America/New_York',
  'America/Toronto',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Vancouver',
] as const;

export type ChurchTimeZone = (typeof CHURCH_TIME_ZONES)[number];

/** Where a church made before #73 is: they were all in UTC+8. */
export const DEFAULT_TIME_ZONE: ChurchTimeZone = 'Asia/Taipei';

export const isChurchTimeZone = (v: unknown): v is ChurchTimeZone => CHURCH_TIME_ZONES.includes(v as ChurchTimeZone);

/** [church]'s time zone; one without a valid one is in [DEFAULT_TIME_ZONE]. */
export function timeZoneOf(church: DocumentSnapshot | undefined): ChurchTimeZone {
  const timeZone = church?.get('timeZone');
  return isChurchTimeZone(timeZone) ? timeZone : DEFAULT_TIME_ZONE;
}

const formats = new Map<string, Intl.DateTimeFormat>();

/** How far [timeZone]'s clock is ahead of UTC at [ms], in minutes. */
export function offsetMinutes(timeZone: string, ms: number): number {
  let format = formats.get(timeZone);
  if (!format) {
    format = new Intl.DateTimeFormat('en-US', {
      timeZone: timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric',
    });
    formats.set(timeZone, format);
  }
  const p = Object.fromEntries(format.formatToParts(new Date(ms)).map((x) => [x.type, Number(x.value)]));
  const wall = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return Math.round((wall - Math.floor(ms / 1000) * 1000) / 60e3);
}

/** What [timeZone]'s clock reads at [ms], in a UTC Date. */
export const wallClock = (timeZone: string, ms: number) => new Date(ms + offsetMinutes(timeZone, ms) * 60e3);

/** `YYYY-MM-DD` of [date] in [timeZone]. */
export const dateKeyIn = (timeZone: string, date: Date) => wallClock(timeZone, date.getTime()).toISOString().slice(0, 10);

/** The day after `YYYY-MM-DD` [day], by the calendar: never two, whatever the clocks do. */
export const nextDay = (day: string) => new Date(Date.parse(`${day}T00:00:00Z`) + 86400e3).toISOString().slice(0, 10);

/** The churches' time zones whose clock is in one of [hours] at [date]: the ones a job run every hour is for. */
export const timeZonesAt = (hours: number[], date: Date) =>
  new Set<ChurchTimeZone>(CHURCH_TIME_ZONES.filter((z) => hours.includes(wallClock(z, date.getTime()).getUTCHours())));

/** The earliest of [timeZones]' days at [date]: a day before it is past in every one of them. */
export const earliestDay = (date: Date, timeZones: Iterable<ChurchTimeZone> = CHURCH_TIME_ZONES) =>
  [...timeZones].map((z) => dateKeyIn(z, date)).sort()[0];

/** `YYYY-MM-DDTHH:mm:ss±HH:MM`: [ms] on [timeZone]'s clock, with its offset. */
export function localIso(timeZone: string, ms: number): string {
  const offset = offsetMinutes(timeZone, ms);
  const abs = Math.abs(offset);
  const sign = offset < 0 ? '-' : '+';
  const hhmm = `${String(Math.floor(abs / 60)).padStart(2, '0')}:${String(abs % 60).padStart(2, '0')}`;
  return `${new Date(ms + offset * 60e3).toISOString().slice(0, 19)}${sign}${hhmm}`;
}

/** A time on a clock, without an offset: `YYYY-MM-DDTHH:mm`, seconds optional. */
export const LOCAL_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/;

/**
 * The instant [timeZone]'s clock reads [local] (a [LOCAL_TIME], or a
 * `YYYY-MM-DD` for its midnight). A time it reads twice as the clocks go
 * back is the first; one it skips going forward is read with the offset it
 * had before, so it lands that much later, as Google Calendar does.
 */
export function instantOf(timeZone: string, local: string): number {
  const asUtc = Date.parse(/^\d{4}-\d{2}-\d{2}$/.test(local) ? `${local}T00:00:00Z` : `${local}Z`);
  // Date.parse takes a 30 February for 2 March.
  if (Number.isNaN(asUtc) || !new Date(asUtc).toISOString().startsWith(local)) return NaN;
  const before = offsetMinutes(timeZone, asUtc - 86400e3);
  const after = offsetMinutes(timeZone, asUtc + 86400e3);
  const fits = [before, after]
    .map((o) => asUtc - o * 60e3)
    .filter((t) => offsetMinutes(timeZone, t) * 60e3 === asUtc - t)
    .sort((a, b) => a - b);
  return fits[0] ?? asUtc - before * 60e3;
}

/**
 * The instant of an event's start or end as Google or the app gives it: a
 * date is its midnight in [timeZone], a [LOCAL_TIME] is on its clock,
 * anything else an instant with its offset.
 */
export function instantOfTime(timeZone: string, t: string): number {
  return /^\d{4}-\d{2}-\d{2}$/.test(t) || LOCAL_TIME.test(t) ? instantOf(timeZone, t) : Date.parse(t);
}
