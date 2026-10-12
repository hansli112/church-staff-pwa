import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { browserLanguage, LANGUAGES, languageOf, words } from '../src/languages.js';

const json = (path: string) => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));
/** The rows app/test/app/languages_test.dart runs too: both sides must agree. */
const shared = json('../../testdata/languages.json');

describe('which language', () => {
  test("a person's: the language their app shows; none, Traditional Chinese; one not known yet, English", () => {
    assert.equal(languageOf('en'), 'en');
    assert.equal(languageOf('zh-Hant'), 'zh-Hant');
    assert.equal(languageOf(undefined), 'zh-Hant', 'an app from before languages');
    assert.equal(languageOf(42), 'zh-Hant');
    assert.equal(languageOf('zh-Hans'), 'zh-Hans');
    assert.equal(languageOf('ja'), 'en', 'an app newer than these functions');
  });

  describe("a browser's: the first on its list the app speaks, else English, as the app picks", () => {
    for (const r of shared.preferred as { why: string; preferred: string[]; language: string }[]) {
      test(r.why, () => assert.equal(browserLanguage(r.preferred.join(',')), r.language));
    }
  });

  describe("app/web/index.html's, before the app starts, as the app picks", () => {
    const html = readFileSync(new URL('../../app/web/index.html', import.meta.url), 'utf8');
    const speaks = new Function(
      `${html.slice(html.indexOf('function speaks'), html.indexOf('var langs'))}; return speaks;`,
    )() as (tag: string) => string | null;
    for (const r of shared.preferred as { why: string; preferred: string[]; language: string }[]) {
      test(r.why, () => assert.equal(r.preferred.map(speaks).find((l) => l) ?? 'en', r.language));
    }
  });

  test('a browser lists them by weight, not by place', () => {
    assert.equal(browserLanguage('zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7'), 'zh-Hant');
    assert.equal(browserLanguage('ja,en;q=0.5,zh-CN;q=0.8'), 'zh-Hans');
    assert.equal(browserLanguage('zh;q=0,en'), 'en', 'q=0 is "not this"');
    assert.equal(browserLanguage('zh;Q=0,en'), 'en', 'Q as q');
    assert.equal(browserLanguage('zh;q=high,en'), 'en', 'a weight that is no number');
    assert.equal(browserLanguage('*'), 'en');
    assert.equal(browserLanguage(undefined), 'en');
  });
});

describe("words the app shows too", () => {
  test("are the app's, word for word", () => {
    const arbs = { 'zh-Hant': 'app_zh.arb', 'zh-Hans': 'app_zh_Hans.arb', en: 'app_en.arb' } as const;
    assert.deepEqual(Object.keys(arbs), LANGUAGES);
    for (const language of LANGUAGES) {
      const arb = json(`../../app/lib/l10n/${arbs[language]}`);
      const w = words(language);
      assert.deepEqual(
        [w.appName, w.placeholder, w.inviteInvalid, w.inviteExpired],
        [arb.appName, arb.nobodyYet, arb.errInviteInvalid, arb.errInviteExpired],
        language,
      );
    }
  });
});

describe('dates in pushes', () => {
  test('Chinese: 10/18（週日）, 10/18（周日）; English names the month: Oct 18 (Sun)', () => {
    const zh = words('zh-Hant');
    const hans = words('zh-Hans');
    const en = words('en');
    assert.deepEqual([zh.shortDate('2026-10-18'), zh.dateWithWeekday('2026-10-18')], ['10/18', '10/18（週日）']);
    assert.deepEqual([hans.shortDate('2026-10-18'), hans.dateWithWeekday('2026-10-18')], ['10/18', '10/18（周日）']);
    assert.deepEqual([en.shortDate('2026-10-18'), en.dateWithWeekday('2026-10-18')], ['Oct 18', 'Oct 18 (Sun)']);
    assert.equal(en.dateWithWeekday('2027-01-04'), 'Jan 4 (Mon)');
  });
});
