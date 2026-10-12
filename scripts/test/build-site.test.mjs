import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, test } from 'node:test';

import { LANGUAGES, buildSite, sitePath, speaks } from '../build-site.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const read = (path) => readFileSync(join(root, path), 'utf8');
const TAGS = Object.keys(LANGUAGES);
const translations = TAGS.filter((tag) => tag !== 'zh-Hant');

const out = mkdtempSync(join(tmpdir(), 'martha-site-'));
const listed = buildSite({ out, origin: 'https://marthasit.com', project: 'marthasit', payments: 'on' });
process.on('exit', () => rmSync(out, { recursive: true, force: true }));
/** The built file a site path is served from (firebase.json's rewrites, else a folder's index.html). */
const fileOf = (path) => join(out, path.endsWith('/') ? `${path}index.html` : `${path === '/' ? '/index' : path}.html`);
const built = (path) => readFileSync(fileOf(path), 'utf8');

/** Every page, by its path in Traditional Chinese. */
const pages = listed.filter((path) => !TAGS.some((tag) => path.startsWith(`/${tag}/`)));

describe('the languages', () => {
  test("are the app's", () => {
    const languages = /export const LANGUAGES: readonly Language\[\] = \[([^\]]*)\]/.exec(read('functions/src/languages.ts'))[1];
    assert.deepEqual(TAGS, [...languages.matchAll(/'([^']+)'/g)].map((m) => m[1]));
  });

  describe("a visitor's: the first on the browser's list the app speaks, else English, as the app picks", () => {
    for (const r of JSON.parse(read('testdata/languages.json')).preferred) {
      test(r.why, () => assert.equal(r.preferred.map(speaks).find((l) => l && LANGUAGES[l]) ?? 'en', r.language));
    }
  });
});

describe('every page in every language', () => {
  test('the same pages, Traditional Chinese at the root and the others under /<language>/', () => {
    for (const tag of translations) {
      assert.deepEqual(listed.filter((path) => path.startsWith(`/${tag}/`)), pages.map((page) => sitePath(tag, page)), tag);
    }
  });

  for (const page of pages) {
    test(page, () => {
      for (const tag of TAGS) {
        const html = built(sitePath(tag, page));
        assert.match(html, new RegExp(`<html lang="${tag}">`), `${tag}: says its language`);
        for (const other of TAGS) {
          assert.ok(html.includes(`<link rel="alternate" hreflang="${other}" href="https://marthasit.com${sitePath(other, page)}">`), `${tag}: lists ${other}`);
          assert.ok(html.includes(`href="${sitePath(other, page)}" hreflang="${other}"`), `${tag}: links to ${other} at its foot`);
        }
        assert.ok(html.includes(`<link rel="alternate" hreflang="x-default" href="https://marthasit.com${sitePath('en', page)}">`));
        assert.ok(!/__ORIGIN__|__FIREBASE_PROJECT__|<!-- site-|<!-- \/?payments:/.test(html), `${tag}: every marker filled`);
        // Its links to the site's pages stay in its language.
        // A link that says its language (hreflang) is meant to go there.
        for (const [, href] of html.matchAll(/<a (?![^>]*hreflang)[^>]*href="(\/[^"#?]*)/g)) {
          const other = TAGS.find((t) => t !== tag && pages.some((p) => sitePath(t, p) === href) && !pages.some((p) => sitePath(tag, p) === href));
          assert.equal(other, undefined, `${tag}: ${page} links to ${href}, in ${other}`);
        }
      }
    });
  }
});

describe('a translated page is its Traditional Chinese page, translated', () => {
  /** What a page's script and styles hang on, in order, and where the shared parts go. */
  const skeleton = (html) => [
    ...html.matchAll(/ (?:id|class|for|name|type|value|data-[a-z-]+)="[^"]*"|<!-- \/?(?:site-[a-z]+|payments:o[nf]+) -->/g),
  ].map((m) => m[0]);
  // The pages and the blog's posts: not the translations' folders, nor node_modules.
  const sources = (dir) => readdirSync(join(root, dir), { recursive: true }).filter((f) => /^(?:blog\/)?[^/]+\.(?:html|md)$/.test(f));

  for (const file of sources('landing')) {
    test(file, () => {
      const zh = read(`landing/${file}`);
      for (const tag of translations) {
        const translated = read(`landing/${tag}/${file}`);
        if (file.endsWith('.md')) {
          assert.equal(/^date: (.*)$/m.exec(translated)?.[1], /^date: (.*)$/m.exec(zh)[1], `${tag}: the same date`);
          continue;
        }
        assert.deepEqual(skeleton(translated), skeleton(zh), `${tag}/${file}`);
      }
    });
  }

  test('nothing else in a language folder', () => {
    for (const tag of translations) {
      const files = readdirSync(join(root, 'landing', tag), { recursive: true }).filter((f) => /\.(html|md)$/.test(f)).sort();
      assert.deepEqual(files, sources('landing').sort(), tag);
    }
  });
});

test("firebase.json serves every page at its path", () => {
  const hosting = JSON.parse(read('firebase.json')).hosting;
  const rewrites = new Map(hosting.rewrites.filter((r) => r.destination).map((r) => [r.source, r.destination]));
  const redirects = new Map(hosting.redirects.map((r) => [r.source, r.destination]));
  for (const path of listed.filter((p) => !p.endsWith('/'))) {
    assert.equal(rewrites.get(path), `${path}.html`, `${path}: a rewrite to its file`);
    assert.ok(hosting.rewrites.findIndex((r) => r.source === path) < hosting.rewrites.findIndex((r) => r.source === '**'), `${path}: before the app's`);
  }
  for (const tag of translations) assert.equal(redirects.get(`/${tag}`), `/${tag}/`, `/${tag} to its front page`);
  assert.deepEqual(relative(out, fileOf('/en/')), 'en/index.html');
});

describe('a visitor goes to their language', () => {
  /** Runs [path]'s language script in a browser asking for [languages]; where it sends them, and what it keeps. */
  function visit(path, { languages = ['zh-TW'], picked = null, search = '', userAgent = 'Mozilla/5.0' } = {}) {
    const html = built(path);
    const script = /<script>\n\(function \(\) \{\n  function speaks[\s\S]*?<\/script>/.exec(html)[0].slice('<script>'.length, -'</script>'.length);
    const kept = { siteLanguage: picked };
    let sent = null;
    new Function('location', 'navigator', 'localStorage', 'document', script)(
      { search, hash: '', replace: (to) => (sent = to) },
      { languages, userAgent },
      { getItem: (k) => kept[k], setItem: (k, v) => (kept[k] = v) },
      { addEventListener() {} },
    );
    return { sent, kept: kept.siteLanguage };
  }

  test("by the browser's languages, as the app picks", () => {
    assert.equal(visit('/support', { languages: ['zh-CN'] }).sent, '/zh-Hans/support');
    assert.equal(visit('/zh-Hans/support', { languages: ['de', 'fr'] }).sent, '/en/support', 'none it speaks: English');
    assert.equal(visit('/support', { languages: ['zh-TW'] }).sent, null);
  });

  test('a language picked at the foot of a page wins', () => {
    assert.equal(visit('/en/', { languages: ['zh-TW'], picked: 'en' }).sent, null);
    assert.equal(visit('/en/', { languages: ['en'], picked: 'zh-Hant' }).sent, '/');
  });

  test('the app asks for its language with ?lang=, and the site keeps it', () => {
    assert.deepEqual(visit('/privacy', { languages: ['en-US'], search: '?lang=zh-Hant' }), { sent: null, kept: 'zh-Hant' });
    assert.deepEqual(visit('/privacy', { languages: ['zh-TW'], search: '?lang=en' }), { sent: '/en/privacy?lang=en', kept: 'en' });
  });

  test('search engines stay where they are', () => {
    assert.equal(visit('/support', { languages: ['en-US'], userAgent: 'Mozilla/5.0 (compatible; Googlebot/2.1)' }).sent, null);
  });
});
