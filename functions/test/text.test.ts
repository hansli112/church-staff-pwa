import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { withinTextLimit } from '../src/limits.js';
import { characterCount, foldWidthAndCase, matchesSearch, nameKey } from '../src/text.js';

/** The rows app/test/domain/text_test.dart runs too: both sides must agree. */
const rules = JSON.parse(readFileSync(new URL('../../testdata/text_rules.json', import.meta.url), 'utf8'));

type Row = Record<string, string | number | boolean>;
const rows = (name: string) => rules[name] as Row[];

describe('foldWidthAndCase', () => {
  for (const r of rows('foldWidthAndCase')) test(r.why as string, () => assert.equal(foldWidthAndCase(r.in as string), r.out));
});

describe('nameKey', () => {
  for (const r of rows('nameKey')) test(r.why as string, () => assert.equal(nameKey(r.in as string), r.out));
});

describe('matchesSearch', () => {
  for (const r of rows('matchesSearch')) {
    test(r.why as string, () => assert.equal(matchesSearch(r.name as string, r.query as string), r.matches));
  }
});

describe('characterCount', () => {
  for (const r of rows('characterCount')) test(r.why as string, () => assert.equal(characterCount(r.in as string), r.count));
});

describe('withinTextLimit', () => {
  for (const r of rows('withinTextLimit')) {
    test(r.why as string, () => assert.equal(withinTextLimit(r.in as string, r.max as number), r.within));
  }
});
