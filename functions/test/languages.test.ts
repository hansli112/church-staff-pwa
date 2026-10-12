import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { browserLanguage, languageOf, words } from '../src/languages.js';

describe('which language', () => {
  test("a person's: the language their app shows; none, Traditional Chinese; one not known yet, English", () => {
    assert.equal(languageOf('en'), 'en');
    assert.equal(languageOf('zh-Hant'), 'zh-Hant');
    assert.equal(languageOf(undefined), 'zh-Hant', 'an app from before languages');
    assert.equal(languageOf(42), 'zh-Hant');
    assert.equal(languageOf('zh-Hans'), 'zh-Hant', 'every Chinese is Traditional for now');
    assert.equal(languageOf('ja'), 'en', 'an app newer than these functions');
  });

  test("a browser's: the first on its list the app speaks, else English, as the app picks", () => {
    assert.equal(browserLanguage('zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7'), 'zh-Hant');
    assert.equal(browserLanguage('en-US,en;q=0.9,zh-TW;q=0.8'), 'en');
    assert.equal(browserLanguage('ja-JP,ja;q=0.9,zh-CN;q=0.8'), 'zh-Hant', 'every Chinese is Traditional for now');
    assert.equal(browserLanguage('ja,en;q=0.5,zh;q=0.8'), 'zh-Hant', 'by weight, not by place');
    assert.equal(browserLanguage('fr-FR,de'), 'en');
    assert.equal(browserLanguage('zh;q=0,en'), 'en', 'q=0 is "not this"');
    assert.equal(browserLanguage('zh;Q=0,en'), 'en', 'Q as q');
    assert.equal(browserLanguage('zh;q=high,en'), 'en', 'a weight that is no number');
    assert.equal(browserLanguage('*'), 'en');
    assert.equal(browserLanguage(''), 'en');
    assert.equal(browserLanguage(undefined), 'en');
  });
});

describe('dates in pushes', () => {
  test('Chinese: 10/18（週日）; English names the month: Oct 18 (Sun)', () => {
    const zh = words('zh-Hant');
    const en = words('en');
    assert.deepEqual([zh.shortDate('2026-10-18'), zh.dateWithWeekday('2026-10-18')], ['10/18', '10/18（週日）']);
    assert.deepEqual([en.shortDate('2026-10-18'), en.dateWithWeekday('2026-10-18')], ['Oct 18', 'Oct 18 (Sun)']);
    assert.equal(en.dateWithWeekday('2027-01-04'), 'Jan 4 (Mon)');
  });
});
