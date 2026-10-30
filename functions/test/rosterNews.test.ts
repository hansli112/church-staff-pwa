import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { APP_VIAS, plannedAfter, tellsOf, viaOf } from '../src/rosterNews.js';

// testdata/roster_changes.json, which the app runs too.
const read = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8');
const data = JSON.parse(read('../../testdata/roster_changes.json')) as {
  via: { via: string; by: 'app' | 'backend'; tells: string }[];
  planned: { name: string; waiting: string[] | null; before: string[]; after: string[]; told: boolean; next: string[] | null }[];
};
const sorted = (roles: string[] | null) => (roles === null ? null : [...roles].sort());

describe('where a roster change came from (testdata/roster_changes.json)', () => {
  for (const row of data.via) {
    test(`${row.via} tells ${row.tells}`, () => {
      assert.equal(viaOf(row.via), row.via);
      assert.equal(tellsOf(viaOf(row.via)), row.tells);
    });
  }

  test('the app writes only what the table says it does', () => {
    assert.deepEqual([...APP_VIAS], data.via.filter((v) => v.by === 'app').map((v) => v.via));
  });

  test('firestore.rules takes from the app only what it writes', () => {
    const list = read('../../firestore.rules').match(/function appVia\(\)[\s\S]*? in \[([^\]]*)\]/)?.[1];
    assert.ok(list, 'appVia() in firestore.rules');
    assert.deepEqual(list.split(',').map((s) => s.trim().replaceAll("'", '')), [...APP_VIAS]);
  });

  test('a roster with no via, or one unknown, reads as the app’s', () => {
    assert.equal(viaOf(undefined), 'app');
    assert.equal(viaOf('later'), 'app');
  });
});

describe('what waits for 通知同工 (testdata/roster_changes.json)', () => {
  for (const c of data.planned) {
    test(c.name, () => {
      assert.deepEqual(sorted(plannedAfter(c.waiting, c.before, c.after, c.told)), sorted(c.next));
    });
  }
});
