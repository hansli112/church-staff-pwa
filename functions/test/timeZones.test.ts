import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { test } from 'node:test';

import { CHURCH_TIME_ZONES, dateKeyIn, instantOf, localIso, offsetMinutes } from '../src/timeZones.js';

/**
 * Every clock change of the churches' zones, 2020 to 2040, as Node's time
 * zone database has them: app/test/domain/church_time_test.dart holds the
 * app's own rules to these. After a tz database update changes one, run
 * `UPDATE_TESTDATA=1 npm test` and fix the app's rules to match.
 */
const file = new URL('../../testdata/time_zones.json', import.meta.url);
const FROM = Date.UTC(2020, 0, 1);
const TO = Date.UTC(2041, 0, 1);
const DAY = 86400e3;

function changes(timeZone: string) {
  const found: [string, number][] = [];
  for (let t = FROM; t < TO; t += DAY) {
    if (offsetMinutes(timeZone, t) === offsetMinutes(timeZone, t + DAY)) continue;
    let [lo, hi] = [t, t + DAY];
    while (hi - lo > 60e3) {
      const mid = lo + Math.floor((hi - lo) / 120e3) * 60e3;
      if (offsetMinutes(timeZone, mid) === offsetMinutes(timeZone, lo)) lo = mid;
      else hi = mid;
    }
    found.push([new Date(hi).toISOString(), offsetMinutes(timeZone, hi)]);
  }
  return found;
}

test('testdata/time_zones.json is what the time zone database says', () => {
  const expected = {
    about:
      "Churches' time zones (functions/src/zones.ts, app/lib/domain/church_time.dart) and every clock change from 2020 to 2040: offset is minutes ahead of UTC on 2020-01-01, changes are [instant, offset from then]. Written by functions/test/zones.test.ts with UPDATE_TESTDATA=1.",
    zones: CHURCH_TIME_ZONES.map((id) => ({ id, offset: offsetMinutes(id, FROM), changes: changes(id) })),
  };
  if (process.env.UPDATE_TESTDATA) writeFileSync(file, `${JSON.stringify(expected, null, 2)}\n`);
  assert.deepEqual(JSON.parse(readFileSync(file, 'utf8')), expected);
});

test('a time on the clock, and back', () => {
  assert.equal(localIso('America/Los_Angeles', Date.parse('2026-10-18T17:00:00Z')), '2026-10-18T10:00:00-07:00');
  assert.equal(localIso('Asia/Taipei', Date.parse('2026-10-18T17:00:00Z')), '2026-10-19T01:00:00+08:00');
  assert.equal(localIso('Europe/London', Date.parse('2026-12-01T09:30:00Z')), '2026-12-01T09:30:00+00:00');
  assert.equal(instantOf('America/Los_Angeles', '2026-10-18T10:00'), Date.parse('2026-10-18T17:00:00Z'));
  assert.equal(instantOf('Asia/Taipei', '2026-10-19'), Date.parse('2026-10-18T16:00:00Z'));
  assert.equal(dateKeyIn('America/New_York', new Date('2026-10-19T03:59:00Z')), '2026-10-18');
});

test('the clocks going forward and back, as Google Calendar reads them', () => {
  // 2026-03-08 02:30 never happens in Los Angeles: an hour later.
  assert.equal(localIso('America/Los_Angeles', instantOf('America/Los_Angeles', '2026-03-08T02:30')), '2026-03-08T03:30:00-07:00');
  // 2026-11-01 01:30 happens twice: the first.
  assert.equal(localIso('America/Los_Angeles', instantOf('America/Los_Angeles', '2026-11-01T01:30')), '2026-11-01T01:30:00-07:00');
  assert.ok(Number.isNaN(instantOf('Asia/Taipei', 'soon')));
  assert.ok(Number.isNaN(instantOf('Asia/Taipei', '2026-02-30T19:00')));
});
