import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import { REMINDER_TIMINGS } from '../src/notifications.js';
import { GROUP_KEY } from '../src/powers.js';
import { NOTIFICATION_KINDS } from '../src/push.js';

// Lists kept by name in three places: src (here), app/lib/domain/models.dart
// and firestore.rules. This reads the other two as text and fails on any
// that disagrees, as limits.test.ts does for the limits.

const read = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8');
const models = read('../../app/lib/domain/models.dart');
const rules = read('../../firestore.rules');

/** The values of `enum [name] { a, b }` in models.dart. */
function dartEnum(name: string) {
  const body = models.match(new RegExp(`enum ${name} \\{([^}]*)\\}`))?.[1];
  assert.ok(body, `enum ${name} in models.dart`);
  return body.split(',').map((v) => v.trim()).filter(Boolean);
}

/** The list firestore.rules checks [field] against: `[field].hasOnly([...])` or `[field] in [...]`. */
function rulesList(field: string) {
  const at = rules.match(new RegExp(`${field.replace('.', '\\.')}(?:\\.hasOnly\\(| in )\\[([^\\]]*)\\]`))?.[1];
  assert.ok(at, `${field} in firestore.rules`);
  return [...at.matchAll(/'([^']*)'/g)].map((m) => m[1]);
}

test('the kinds of notification a member can turn off', () => {
  assert.deepEqual(dartEnum('NotificationKind'), [...NOTIFICATION_KINDS]);
  assert.deepEqual(rulesList('p.muted'), [...NOTIFICATION_KINDS]);
});

test('when a member is reminded', () => {
  assert.deepEqual(dartEnum('ReminderTiming'), [...REMINDER_TIMINGS]);
  assert.deepEqual(rulesList('p.reminderTiming'), [...REMINDER_TIMINGS]);
});

test("an event roster's group, as the rules check it", () => {
  assert.ok(rules.includes(`roster.group.matches('${GROUP_KEY}')`), GROUP_KEY);
});
