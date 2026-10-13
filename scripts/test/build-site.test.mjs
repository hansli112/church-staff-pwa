import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
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
// As the live site is now: no payments on the website.
const outOff = mkdtempSync(join(tmpdir(), 'martha-site-off-'));
buildSite({ out: outOff, origin: 'https://marthasit.com', project: 'marthasit', payments: 'off' });
process.on('exit', () => {
  rmSync(out, { recursive: true, force: true });
  rmSync(outOff, { recursive: true, force: true });
});
/** The built file a site path is served from (firebase.json's rewrites, else a folder's index.html). */
const fileOf = (path, dir = out) => join(dir, path.endsWith('/') ? `${path}index.html` : `${path === '/' ? '/index' : path}.html`);
const built = (path) => readFileSync(fileOf(path), 'utf8');
const builtOff = (path) => readFileSync(fileOf(path, outOff), 'utf8');

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
        // A link to another language picks it, or the page sends the visitor back.
        for (const [a] of html.matchAll(/<a [^>]*hreflang="[^"]*"[^>]*>/g)) {
          assert.match(a, /data-site-language="([^"]*)"/, `${tag}: ${a}`);
        }
        // A link that says its language (hreflang) is meant to go there.
        for (const [, href] of html.matchAll(/<a (?![^>]*hreflang)[^>]*href="(\/[^"#?]*)/g)) {
          const other = TAGS.find((t) => t !== tag && pages.some((p) => sitePath(t, p) === href) && !pages.some((p) => sitePath(tag, p) === href));
          assert.equal(other, undefined, `${tag}: ${page} links to ${href}, in ${other}`);
        }
      }
    });
  }
});

describe("every page's head", () => {
  test('names its one address, for the copies ?lang= and ?from=app make', () => {
    for (const path of listed) {
      const canonical = [...built(path).matchAll(/<link rel="canonical" href="([^"]*)">/g)].map((m) => m[1]);
      assert.deepEqual(canonical, [`https://marthasit.com${path}`], path);
    }
  });

  test('has the picture a link to it shows, at an absolute address the site serves', () => {
    for (const path of listed) {
      assert.match(built(path), /<meta property="og:image" content="https:\/\/marthasit\.com\/og-image\.png">/, path);
    }
    assert.ok(existsSync(join(out, 'og-image.png')));
  });

  test("has the browser's colors, light and dark, once", () => {
    for (const path of listed) {
      const colors = [...built(path).matchAll(/<meta name="theme-color" content="([^"]*)" media="\(prefers-color-scheme: (\w+)\)">/g)].map((m) => `${m[2]} ${m[1]}`);
      assert.deepEqual(colors, ['light #FFFFFF', 'dark #000000'], path);
    }
  });
});

test('no comment in landing/ reaches the built site, payments on or off', () => {
  for (const path of listed) {
    assert.doesNotMatch(built(path), /<!--/, `on: ${path}`);
    assert.doesNotMatch(builtOff(path), /<!--/, `off: ${path}`);
  }
});

test('while the website takes no payments, the support page has no button but shows what paying will be, for the payment provider to review', () => {
  // What the page says (its script mentions NewebPay either way).
  const main = (html) => /<main[\s\S]*<\/main>/.exec(html)[0];
  for (const tag of TAGS) {
    const on = main(built(sitePath(tag, '/support')));
    const off = main(builtOff(sitePath(tag, '/support')));
    assert.match(on, /<form id="pay-form"/, `${tag}: on`);
    assert.match(on, /Apple Pay/, `${tag}: on`);
    assert.doesNotMatch(off, /<form|<button|id="pay"|data-soon/, `${tag}: no button`);
    // Priced in NT$, by card, with no provider named until one is chosen.
    assert.match(off, /Apple Pay/, `${tag}: ways to pay`);
    assert.match(off, /1,000/, `${tag}: amounts`);
    assert.doesNotMatch(off, /Google Pay|NewebPay|藍新|蓝新/, `${tag}: no provider`);
    assert.equal(on.match(/id="refund-title"/g).length, 1, `${tag}: on`);
    assert.equal(off.match(/id="refund-title"/g).length, 1, `${tag}: off`);
    assert.ok(off.includes('mailto:support@marthasit.com'), `${tag}: refunds and where to write`);
  }
});

describe('a translated page is its Traditional Chinese page, translated', () => {
  /** What a page's script and styles hang on, in order, and where the shared parts go. */
  const skeleton = (html) => [
    ...html.matchAll(/ (?:id|class|for|name|type|value|data-(?!site-language)[a-z-]+)="[^"]*"|<!-- \/?(?:site-[a-z]+|payments:o[nf]+) -->/g),
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

test('the privacy policy and the terms name NewebPay only while the site takes payments', () => {
  const off = mkdtempSync(join(tmpdir(), 'martha-site-off-'));
  try {
    buildSite({ out: off, origin: 'https://marthasit.com', project: 'marthasit', payments: 'off' });
    for (const tag of TAGS) {
      for (const page of ['/privacy', '/terms']) {
        assert.match(built(sitePath(tag, page)), /NewebPay/, `${tag}${page}: on`);
        const html = readFileSync(join(off, `${sitePath(tag, page)}.html`), 'utf8');
        assert.doesNotMatch(html, /NewebPay|藍新|蓝新/, `${tag}${page}: off`);
      }
    }
  } finally {
    rmSync(off, { recursive: true, force: true });
  }
});

describe('opened from the iOS and Android apps (from=app), a page hides its ways to the payments', () => {
  /** Runs [path]'s from=app script; whether the page is the app's, and what the tab keeps. */
  function open(path, { search = '', kept = null } = {}) {
    const script = /<script id="from-app">([\s\S]*?)<\/script>/.exec(built(path))[1];
    const store = { fromApp: kept };
    const classes = new Set();
    new Function('location', 'sessionStorage', 'document', script)(
      { search },
      { getItem: (k) => store[k], setItem: (k, v) => (store[k] = v) },
      { documentElement: { classList: { add: (c) => classes.add(c) } } },
    );
    return { app: classes.has('from-app'), kept: store.fromApp };
  }

  test('the app asks with from=app, and the tab keeps it from page to page', () => {
    assert.deepEqual(open('/privacy', { search: '?lang=zh-Hant&from=app' }), { app: true, kept: '1' });
    assert.deepEqual(open('/en/terms', { kept: '1' }), { app: true, kept: '1' });
    assert.deepEqual(open('/privacy', { search: '?lang=zh-Hant' }), { app: false, kept: null });
  });

  test('what it hides: every way to the web app (which has the support page), and the terms on paying on the website', () => {
    const rule = /([^{}]*)\{\s*display:\s*none;?\s*\}/g;
    const hidden = [...read('landing/site.css').matchAll(rule)].flatMap((m) => m[1].split(',').map((s) => s.trim()));
    assert.ok(hidden.includes('.from-app a[href="/home"]') && hidden.includes('.from-app [data-from-app="hide"]'), 'site.css hides them');
    for (const tag of TAGS) {
      // What the app opens, and all they link to (no header nav, no site footer).
      for (const page of ['/privacy', '/terms', '/delete-account']) {
        // A link in a sentence goes with the words around it.
        for (const [line] of built(sitePath(tag, page)).matchAll(/^.*<(?:li|p)\b.*href="\/home".*$/gm)) {
          assert.match(line, /<span data-from-app="hide">[^<]*<a href="\/home">/, `${tag}${page}: ${line.trim()}`);
        }
      }
      const newebpay = [...built(sitePath(tag, '/terms')).matchAll(/<li[^>]*>[^\n]*NewebPay[^\n]*/g)].map((m) => m[0]);
      assert.equal(newebpay.length, 1, tag);
      assert.match(newebpay[0], /^<li data-from-app="hide">/, tag);
    }
  });

  test("the terms' line on store refunds says it is for in-app payments only once the website takes payments", () => {
    const off = mkdtempSync(join(tmpdir(), 'martha-site-off-'));
    try {
      buildSite({ out: off, origin: 'https://marthasit.com', project: 'marthasit', payments: 'off' });
      const store = (html) => /<li>([^<]*)Apple App Store/.exec(html)[1];
      assert.equal(store(built('/terms')), 'App 內的付款、續訂與取消訂閱由 ');
      assert.equal(store(readFileSync(join(off, 'terms.html'), 'utf8')), '付款、續訂與取消訂閱由 ');
    } finally {
      rmSync(off, { recursive: true, force: true });
    }
  });
});

test("firebase.json serves every page at its path", () => {
  const hosting = JSON.parse(read('firebase.json')).hosting;
  const rewrites = new Map(hosting.rewrites.filter((r) => r.destination).map((r) => [r.source, r.destination]));
  // An exact path: Hosting's "source": "/en" also takes /en/, and would send it to itself.
  const redirects = new Map(hosting.redirects.filter((r) => r.regex).map((r) => [r.regex, r.destination]));
  assert.ok(!hosting.redirects.some((r) => translations.some((tag) => r.source?.startsWith(`/${tag}`))), 'no glob redirects for a language');
  for (const path of listed.filter((p) => !p.endsWith('/'))) {
    assert.equal(rewrites.get(path), `${path}.html`, `${path}: a rewrite to its file`);
    assert.ok(hosting.rewrites.findIndex((r) => r.source === path) < hosting.rewrites.findIndex((r) => r.source === '**'), `${path}: before the app's`);
  }
  for (const tag of translations) assert.equal(redirects.get(`^/${tag}$`), `/${tag}/`, `/${tag} to its front page`);
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
