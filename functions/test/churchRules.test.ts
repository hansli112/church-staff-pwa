import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { churchAccess } from '../src/access.js';
import { attendanceDue } from '../src/attendance.js';

import { identitiesOf, withIdentities, type Identity } from '../src/identities.js';
import { mapMember } from '../src/importer.js';
import { unreadCount } from '../src/notificationList.js';
import { standing } from '../src/joinRequests.js';
import { ledChangeAllowed } from '../src/ledDuties.js';
import { LANGUAGES, words } from '../src/languages.js';
import { groupOf, powersOf, type ChurchGroup } from '../src/powers.js';
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

describe('memberIdentities', () => {
  for (const r of rows('memberIdentities')) test(r.why, () => assert.deepEqual(identitiesOf(r.doc), r.identities));
});

describe('identityProjection', () => {
  for (const r of rows('identityProjection')) {
    test(r.why, () => {
      const out: Record<string, unknown> = withIdentities({ role: r.role }, r.identities as Identity[]);
      assert.deepEqual(Object.fromEntries(Object.keys(r.out).map((k) => [k, out[k]])), r.out);
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
  const group = (g: Row): ChurchGroup =>
    g.smallGroup ? { kind: 'small', id: g.smallGroup, service: g.service } : g.service ? { kind: 'service', id: g.service } : { kind: 'ministry', id: g.ministry };
  for (const r of rows('groupMembership')) test(r.why, () => assert.equal(powersOf(r.caller).mayMove(r.target, group(r.group)), r.may));
});

describe('eventWriting', () => {
  for (const r of rows('eventWriting')) test(r.why, () => assert.equal(powersOf(r.member).mayWriteEvent(r.before, r.after), r.may));
});

describe('smallGroupEditing', () => {
  for (const r of rows('smallGroupEditing')) test(r.why, () => assert.equal(powersOf(r.member).mayEditSmallGroup(r.before, r.after), r.may));
});

describe('attendanceAccess', () => {
  for (const r of rows('attendanceAccess')) {
    test(r.why, () => {
      const group = groupOf(r.group, r.smallGroupService ?? null)!;
      assert.equal(powersOf(r.member).writesAttendance(group), r.writes, 'writes');
      assert.equal(powersOf(r.member).readsAttendance(group), r.reads, 'reads');
    });
  }
});

describe('attendanceReminded', () => {
  for (const r of rows('attendanceReminded')) {
    test(r.why, () => assert.equal(powersOf(r.member).remindedOfAttendance(groupOf(r.group)!), r.reminded));
  }
});

describe('attendanceDue', () => {
  for (const r of rows('attendanceDue')) {
    test(r.why, () => assert.equal(attendanceDue(r.meets, { since: r.since, pauses: r.pauses ?? [] }, r.day), r.due));
  }
});

describe('joinRequestState', () => {
  for (const r of rows('joinRequestState')) test(r.why, () => assert.equal(standing(r.daysAgo, r.rejected), r.state));
});

describe('unreadNotifications', () => {
  for (const r of rows('unreadNotifications')) test(r.why, () => assert.equal(unreadCount(r.items, r.seen), r.unread));
});
