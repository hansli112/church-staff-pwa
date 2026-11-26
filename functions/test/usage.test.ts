import assert from 'node:assert/strict';
import { test } from 'node:test';

import { powersOf } from '../src/powers.js';
import { eventActingAs } from '../src/usage.js';

test('an event write is logged as the broadest 身分 that lets it', () => {
  assert.equal(eventActingAs(powersOf({ role: 'admin' }), ''), 'admin');
  assert.equal(eventActingAs(powersOf({ groups: ['roster-editors', 'calendar-editors'] }), 'ministry:media'), 'office');
  assert.equal(eventActingAs(powersOf({ leadMinistries: ['media'] }), 'ministry:media'), 'ministryLead');
  assert.equal(eventActingAs(powersOf({ leadSmallGroups: ['joy'] }), 'small:joy'), 'smallGroupLead');
  assert.equal(eventActingAs(powersOf({ leadTypes: ['sunday'] }), 'service:sunday'), 'serviceLead');
});
