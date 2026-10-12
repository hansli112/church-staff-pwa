import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { browserLanguage, LANGUAGES, languageOf, words, type Language } from '../src/languages.js';

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
    assert.equal(languageOf('ja'), 'ja');
    assert.equal(languageOf('fr'), 'en', 'an app newer than these functions');
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
    assert.equal(browserLanguage('fr,en;q=0.5,zh-CN;q=0.8'), 'zh-Hans');
    assert.equal(browserLanguage('zh;q=0,en'), 'en', 'q=0 is "not this"');
    assert.equal(browserLanguage('zh;Q=0,en'), 'en', 'Q as q');
    assert.equal(browserLanguage('zh;q=high,en'), 'en', 'a weight that is no number');
    assert.equal(browserLanguage('*'), 'en');
    assert.equal(browserLanguage(undefined), 'en');
  });
});

describe("words the app shows too", () => {
  test("are the app's, word for word", () => {
    const arbs = { 'zh-Hant': 'app_zh.arb', 'zh-Hans': 'app_zh_Hans.arb', en: 'app_en.arb', ja: 'app_ja.arb', ko: 'app_ko.arb' } as const;
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

describe('a member who left, in Korean', () => {
  test('님 after a name; the someone without one takes 이', () => {
    const ko = words('ko');
    assert.equal(ko.memberLeft('김민수'), '김민수 님이 교회를 나갔어요');
    assert.equal(ko.memberLeft(ko.someone), '멤버 한 명이 교회를 나갔어요');
  });
});

describe('dates in pushes', () => {
  test('10/18（週日）, 10/18（周日）; English names the month: Oct 18 (Sun); Japanese and Korean as CLDR has them', () => {
    const zh = words('zh-Hant');
    const hans = words('zh-Hans');
    const en = words('en');
    assert.deepEqual([zh.shortDate('2026-10-18'), zh.dateWithWeekday('2026-10-18')], ['10/18', '10/18（週日）']);
    assert.deepEqual([hans.shortDate('2026-10-18'), hans.dateWithWeekday('2026-10-18')], ['10/18', '10/18（周日）']);
    assert.deepEqual([en.shortDate('2026-10-18'), en.dateWithWeekday('2026-10-18')], ['Oct 18', 'Oct 18 (Sun)']);
    assert.equal(en.dateWithWeekday('2027-01-04'), 'Jan 4 (Mon)');
    const ja = words('ja');
    const ko = words('ko');
    assert.deepEqual([ja.shortDate('2026-10-18'), ja.dateWithWeekday('2026-10-18')], ['10月18日', '10月18日(日)']);
    assert.deepEqual([ko.shortDate('2026-10-18'), ko.dateWithWeekday('2026-10-18')], ['10월 18일', '10월 18일 (일)']);
  });
});

test("what a 線上支持 payment is for fits NewebPay's 50, counted in bytes", () => {
  for (const language of LANGUAGES) assert.ok(Buffer.byteLength(words(language).supportItem) <= 50, language);
});

describe("the app's name under its home-screen icon, in each language", () => {
  const read = (path: string) => readFileSync(new URL(`../../app/${path}`, import.meta.url), 'utf8');
  // Android's resource folders: Traditional for zh-TW, zh-HK and plain zh;
  // Simplified for what Android counts as written in it (zh-CN, zh-SG, zh-MY);
  // English for every language the app does not speak.
  const android: Record<Language, string> = { 'zh-Hant': 'values-zh', 'zh-Hans': 'values-b+zh+Hans', en: 'values', ja: 'values-ja', ko: 'values-ko' };
  const ios: Record<Language, string> = { 'zh-Hant': 'zh-Hant', 'zh-Hans': 'zh-Hans', en: 'en', ja: 'ja', ko: 'ko' };
  const project = read('ios/Runner.xcodeproj/project.pbxproj');
  const plist = read('ios/Runner/Info.plist');

  for (const language of LANGUAGES) {
    test(language, () => {
      const name = words(language).appName;
      const strings = read(`android/app/src/main/res/${android[language]}/strings.xml`);
      assert.match(strings, new RegExp(`<string name="app_name">${escapeXml(name)}</string>`), `Android, ${android[language]}`);

      const lproj = read(`ios/Runner/${ios[language]}.lproj/InfoPlist.strings`);
      assert.match(lproj, new RegExp(`^"CFBundleDisplayName" = "${name}";$`, 'm'), `iOS, ${ios[language]}.lproj`);
      assert.match(project, new RegExp(`/\\* ${ios[language]} \\*/ = \\{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = ${ios[language]}; path = ${ios[language]}.lproj/InfoPlist.strings;`), `${ios[language]}.lproj in the Xcode project`);
      assert.match(plist, new RegExp(`<key>CFBundleLocalizations</key>\\s*<array>[\\s\\S]*?<string>${ios[language]}</string>[\\s\\S]*?</array>`), `Info.plist lists ${ios[language]}`);

      const manifest = JSON.parse(read(`web/${language === 'zh-Hant' ? 'manifest.json' : `manifest-${language}.json`}`));
      assert.deepEqual([manifest.name, manifest.short_name, manifest.description, manifest.lang], [name, name, words(language).description, language], 'the web app');
    });
  }

  test("Android's label and iOS's name come from them", () => {
    assert.match(read('android/app/src/main/AndroidManifest.xml'), /android:label="@string\/app_name"/);
    assert.match(plist, /<key>CFBundleDisplayName<\/key>\s*<string>Martha, sit<\/string>/, 'as English, the development language');
  });

  test("app/web/index.html's script points the web app at its language's manifest", () => {
    const html = read('web/index.html');
    assert.match(html, /<link rel="manifest" href="manifest.json">/);
    assert.ok(html.includes("'manifest-' + lang + '.json'"));
  });
});

function escapeXml(s: string) {
  return s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]!);
}
