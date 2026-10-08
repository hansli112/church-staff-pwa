import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { LIMITS, personName, RULES_SIZE_FACTOR, SUPPORT_AMOUNT, TEXT_LIMITS } from '../src/limits.js';

// The same limits live in three places: src/limits.ts (here),
// app/lib/domain/limits.dart and firestore.rules. This reads the other two
// as text and fails on any number that disagrees. The website's support
// page (landing/support.html) has the 線上支持 amounts.

const read = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8');
const dart = read('../../app/lib/domain/limits.dart');
const rules = read('../../firestore.rules');
const supportPage = read('../../landing/support.html');

/** `static const name = 123;` in `abstract final class [name]`; nothing else allowed there. */
function dartClass(name: string): Record<string, number> {
  const body = dart.match(new RegExp(`abstract final class ${name} \\{([\\s\\S]*?)\\n\\}`))?.[1];
  assert.ok(body, `class ${name} in limits.dart`);
  const consts = [...body.matchAll(/static const (\w+) = ([^;]+);/g)];
  const out: Record<string, number> = {};
  for (const [, key, value] of consts) {
    assert.match(value, /^\d+$/, `${name}.${key} must be a plain number`);
    out[key] = Number(value);
  }
  return out;
}

/** Which limit each `<field>.size() <= n` in firestore.rules guards. */
const RULES_FIELDS: Record<string, { text?: keyof typeof TEXT_LIMITS; other?: keyof typeof LIMITS; rulesOnly?: number }> = {
  'request.resource.data.homeName': { text: 'homeName' },
  'request.resource.data.name': { text: 'profileName' },
  'data.title': { text: 'linkTitle' },
  "data.get('body', '')": { text: 'linkBody' },
  'data.url': { other: 'url' },
  'data.services': { other: 'services' },
  'roster.title': { text: 'eventTitle' },
  // invites: the 牧區 an invite joins, at most every service.
  "request.resource.data.get('zoneTypes', [])": { other: 'services' },
  // settings/services ids: a list only the rules bound.
  'data.ids': { rulesOnly: 100 },
};

const rulesSizes = [...rules.matchAll(/((?:\.get\([^)]*\)|[\w.])+)\.size\(\) <= (\d+)/g)].map(([, field, n]) => ({
  field,
  n: Number(n),
}));

describe('limits', () => {
  test('limits.dart has the text limits of limits.ts', () => {
    assert.deepEqual(dartClass('TextLimits'), { ...TEXT_LIMITS });
  });

  test('limits.dart has the other limits of limits.ts', () => {
    assert.deepEqual(dartClass('Limits'), { ...LIMITS });
  });

  test('limits.dart has the same rules factor', () => {
    assert.equal(Number(dart.match(/^const rulesSizeFactor = (\d+);$/m)?.[1]), RULES_SIZE_FACTOR);
  });

  test('every size() bound in firestore.rules is a known limit', () => {
    assert.ok(rulesSizes.length > 0, 'found the size() bounds');
    for (const { field } of rulesSizes) assert.ok(RULES_FIELDS[field], `unknown size() bound on ${field}`);
    assert.doesNotMatch(rules, /\.size\(\) <(?!=)/, 'bounds are written as size() <= n');
  });

  test('firestore.rules allows text limit × 4 UTF-16 units and other limits as they are', () => {
    for (const [field, of] of Object.entries(RULES_FIELDS)) {
      const found = rulesSizes.filter((s) => s.field === field);
      assert.ok(found.length > 0, `firestore.rules bounds ${field}`);
      const want = of.text ? TEXT_LIMITS[of.text] * RULES_SIZE_FACTOR : of.other ? LIMITS[of.other] : of.rulesOnly;
      for (const { n } of found) assert.equal(n, want, `${field}.size() <= ${n} in firestore.rules`);
    }
  });

  test('the support page takes the amounts the Functions take', () => {
    const field = supportPage.match(/<input[^>]*id="pay-custom"[^>]*>/)?.[0];
    assert.ok(field, 'the custom amount field in support.html');
    assert.equal(Number(field.match(/\bmin="(\d+)"/)?.[1]), SUPPORT_AMOUNT.min);
    assert.equal(Number(field.match(/\bmax="(\d+)"/)?.[1]), SUPPORT_AMOUNT.max);
    const presets = [...supportPage.matchAll(/name="amount" value="(\d+)"/g)].map(([, v]) => Number(v));
    assert.ok(presets.length > 0, 'preset amounts in support.html');
    for (const p of presets) assert.ok(p >= SUPPORT_AMOUNT.min && p <= SUPPORT_AMOUNT.max, `preset ${p}`);
  });

  test('a name from elsewhere is trimmed and cut to whole characters', () => {
    assert.equal(personName(`  ${'👨‍👩‍👧'.repeat(41)} `), '👨‍👩‍👧'.repeat(40));
    assert.equal(personName(' 王小明 '), '王小明');
    assert.equal(personName(undefined), '');
  });
});
