import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');

function cacheControl(path, rules) {
  let value;
  for (const rule of rules) {
    const pattern = rule.regex ?? rule.source
      .replace(/[.+?^${}()|[\]\\]/g, '\\$&')
      .replaceAll('**', '\u0000').replaceAll('*', '[^/]*').replaceAll('\u0000', '.*');
    const input = rule.regex || rule.source.startsWith('/') ? path : path.slice(1);
    if (!new RegExp(rule.regex ? pattern : `^${pattern}$`).test(input)) continue;
    for (const header of rule.headers) {
      if (header.key.toLowerCase() === 'cache-control') value = header.value;
    }
  }
  return value;
}

test('only content-named compiled JS overrides no-cache with immutable long caching', () => {
  const { hosting } = JSON.parse(readFileSync(join(root, 'firebase.json'), 'utf8'));
  const rules = hosting.headers;
  for (const path of ['/main.dart.d3e18322f0.js', '/main.dart.js_1.part.5567a01230.js']) {
    assert.equal(cacheControl(path, rules), 'public, max-age=31536000, immutable', path);
    const matched = rules.map((rule, i) => rule.regex && new RegExp(rule.regex).test(path) ? i : -1).filter((i) => i >= 0);
    assert.ok(matched.length >= 2, 'specific immutable header overrides the earlier no-cache default');
    assert.equal(rules[matched.at(-1)].headers[0].value, 'public, max-age=31536000, immutable');
  }
  for (const path of ['/index.html', '/app.html', '/flutter_bootstrap.js', '/main.dart.js', '/main.dart.js_1.part.js', '/main.dart.wasm', '/main.dart.mjs', '/main.dart.d3e18322f0.js.map', '/unrelated.d3e18322f0.js']) {
    assert.equal(cacheControl(path, rules), 'no-cache', path);
  }
  assert.equal(cacheControl('/assets/fonts/Icons.a2f6674ce7.otf', rules), 'public, max-age=31536000, immutable');
  assert.equal(cacheControl('/c/test-church', rules), undefined, 'churchPage keeps its own CDN header');
});

test('release-bound asset bundles are immutable but stable manifests and unrelated paths are not', () => {
  const { hosting } = JSON.parse(readFileSync(join(root, 'firebase.json'), 'utf8'));
  for (const path of [
    '/asset-bundles/0123456789/assets/FontManifest.json',
    '/asset-bundles/0123456789/assets/AssetManifest.bin',
    '/asset-bundles/0123456789/assets/fonts/Icons.a2f6674ce7.otf',
    '/asset-bundles/0123456789/assets/logo.png',
    '/asset-bundles/0123456789/assets/shaders/ink_sparkle.frag',
  ]) assert.equal(cacheControl(path, hosting.headers), 'public, max-age=31536000, immutable', path);
  for (const path of [
    '/assets/FontManifest.json',
    '/asset-bundles/not-a-hash/assets/FontManifest.json',
    '/asset-bundles/0123456789/other/FontManifest.json',
  ]) assert.equal(cacheControl(path, hosting.headers), 'no-cache', path);
});
