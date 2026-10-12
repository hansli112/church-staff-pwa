import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { mapMember } from '../src/importer.js';
import { LANGUAGES, words } from '../src/languages.js';
import { dutiesByUid } from '../src/rosters.js';
import { validDutyRename } from '../src/serviceSettings.js';

/** The rows app/test/domain/church_rules_test.dart runs too: both sides must agree. */
const rules = JSON.parse(readFileSync(new URL('../../testdata/church_rules.json', import.meta.url), 'utf8'));

type Row = Record<string, any>;
const rows = (name: string) => rules[name] as Row[];

test("a new church starts with the default services, in its maker's language", () => {
  assert.deepEqual(Object.keys(rules.defaultServices), LANGUAGES);
  for (const language of LANGUAGES) {
    assert.deepEqual(words(language).newChurchServices, rules.defaultServices[language], language);
  }
});

describe('dutyRename', () => {
  for (const r of rows('dutyRename')) {
    test(r.why, () => assert.equal(validDutyRename(r.before, r.after, r.from, r.to), r.ok));
  }
});

describe('rosterIdentity', () => {
  for (const r of rows('rosterIdentity')) test(r.why, () => assert.deepEqual(dutiesByUid(r.duties).get(r.uid) ?? [], r.holds));
});

describe('movedMembers', () => {
  for (const r of rows('movedMembers')) {
    test(r.why, () => {
      const m = mapMember('uid', { name: '李美玉', ...r.in }, null);
      assert.deepEqual(
        { role: m.role, groups: m.groups, zones: m.zones, muted: m.notificationPrefs.muted },
        r.out,
      );
    });
  }
});
