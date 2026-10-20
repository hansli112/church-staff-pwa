import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { churchAccess } from '../src/access.js';

import { mayWriteEvent } from '../src/eventGroups.js';
import { mayMoveMember } from '../src/groupMembers.js';
import { mapMember } from '../src/importer.js';
import { ledChangeAllowed } from '../src/ledDuties.js';
import { LANGUAGES, words } from '../src/languages.js';
import { dutiesByUid } from '../src/rosters.js';
import { validDutyRename } from '../src/serviceSettings.js';
import { caller, db, deps, seedChurch } from './support.js';

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

describe('rosterEditing', () => {
  // The backend gates only services' rosters (photo recognition); an event's is the app's and the rules'.
  for (const r of rows('rosterEditing').filter((r) => r.roster !== 'event')) {
    test(r.why, async () => {
      await seedChurch('Rules', { u: r.role });
      await db
        .doc('churches/Rules/members/u')
        .update({ groups: r.groups, zoneTypes: r.zoneTypes, leadTypes: r.leadTypes, leadMinistries: r.leadMinistries });
      await db.doc('churches/Rules/settings/services').set({ services: [], ids: ['sunday', 'youth'] });
      const may = await churchAccess(deps, caller('u'), { churchId: 'Rules' }, { rosterEditor: r.roster }).then(
        () => true,
        () => false,
      );
      assert.equal(may, r.may);
    });
  }
});

describe('ledDuties', () => {
  const day = (duties: unknown, events: unknown) => (duties === null ? null : { type: 'sunday', dateKey: '2030-10-06', duties, events });
  for (const r of rows('ledDuties')) {
    test(r.why, () => assert.equal(ledChangeAllowed(new Set(r.roles), day(r.before, r.beforeEvents), day(r.after, r.afterEvents)), r.may));
  }
});

describe('groupMembership', () => {
  for (const r of rows('groupMembership')) test(r.why, () => assert.equal(mayMoveMember(r.caller, r.target, r.group), r.may));
});

describe('eventWriting', () => {
  for (const r of rows('eventWriting')) test(r.why, () => assert.equal(mayWriteEvent(r.member, r.before, r.after), r.may));
});
