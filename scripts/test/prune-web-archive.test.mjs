import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const now = new Date('2026-11-26T12:00:00Z');
const daysAgo = (days) => new Date(now.getTime() - days * 86400000);

function archive(t) {
  const dir = mkdtempSync(join(tmpdir(), 'martha-prune-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const history = join(dir, 'demo-martha');
  mkdirSync(join(history, 'releases'), { recursive: true });
  return { dir, history };
}

let n = 0;
/** A release packaged [age] days ago, using [files] outside its own folder. */
function release(history, age, files) {
  const id = (++n).toString(16).padStart(20, '0');
  const folder = join(history, 'releases', id);
  mkdirSync(join(folder, 'canvaskit'), { recursive: true });
  writeFileSync(join(folder, 'canvaskit/canvaskit.wasm'), 'engine');
  for (const url of files) {
    mkdirSync(dirname(join(history, url)), { recursive: true });
    writeFileSync(join(history, url), url);
  }
  const urls = [...files, `/releases/${id}/app.html`];
  writeFileSync(join(folder, 'release-manifest.json'), JSON.stringify({ schema: 1, id, files: urls.map((url) => ({ url })) }));
  const when = daysAgo(age);
  utimesSync(join(folder, 'release-manifest.json'), when, when);
  return id;
}

function prune(dir, ...args) {
  return spawnSync(process.execPath, [join(root, 'scripts/prune-web-archive.mjs'), dir, '--project', 'demo-martha', '--now', now.toISOString(), ...args], { encoding: 'utf8' });
}

test('keeps the releases of the last 14 days, and what they use', (t) => {
  const { dir, history } = archive(t);
  const old = release(history, 30, ['/main.dart.aaaaaaaaaa.js', '/main.dart.js_1.part.bbbbbbbbbb.js', '/asset-bundles/cccccccccc/assets/a.png', '/main.dart.shared0000.js']);
  const recent = release(history, 3, ['/main.dart.dddddddddd.js', '/main.dart.eeeeeeeeee.wasm', '/asset-bundles/ffffffffff/assets/a.png', '/main.dart.shared0000.js']);
  const result = prune(dir, '--keep-days', '14', '--keep', '1');
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(readdirSync(join(history, 'releases')), [recent]);
  assert.equal(existsSync(join(history, 'releases', old)), false);
  assert.equal(existsSync(join(history, 'main.dart.aaaaaaaaaa.js')), false);
  assert.equal(existsSync(join(history, 'main.dart.js_1.part.bbbbbbbbbb.js')), false);
  assert.equal(existsSync(join(history, 'asset-bundles/cccccccccc')), false);
  for (const kept of ['main.dart.dddddddddd.js', 'main.dart.eeeeeeeeee.wasm', 'asset-bundles/ffffffffff/assets/a.png', 'main.dart.shared0000.js']) {
    assert.equal(existsSync(join(history, kept)), true, kept);
  }
});

test('always keeps the newest few, however old', (t) => {
  const { dir, history } = archive(t);
  const oldest = release(history, 90, ['/main.dart.1111111111.js']);
  const older = release(history, 60, ['/main.dart.2222222222.js']);
  const newest = release(history, 40, ['/main.dart.3333333333.js']);
  const result = prune(dir, '--keep-days', '14', '--keep', '2');
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(readdirSync(join(history, 'releases')).sort(), [older, newest].sort());
  assert.equal(existsSync(join(history, 'main.dart.1111111111.js')), false);
  assert.equal(existsSync(join(history, 'main.dart.2222222222.js')), true);
  assert.equal(existsSync(join(history, 'releases', oldest)), false);
});

test('leaves the loose fonts and other files alone', (t) => {
  const { dir, history } = archive(t);
  release(history, 1, ['/main.dart.1111111111.js']);
  mkdirSync(join(history, 'assets/fonts'), { recursive: true });
  writeFileSync(join(history, 'assets/fonts/Icons.0123456789.otf'), 'font');
  const result = prune(dir, '--keep-days', '14', '--keep', '1');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(join(history, 'assets/fonts/Icons.0123456789.otf')), true);
});

test('deletes nothing when a release cannot be read', (t) => {
  const { dir, history } = archive(t);
  const old = release(history, 30, ['/main.dart.1111111111.js']);
  const broken = release(history, 1, []);
  writeFileSync(join(history, 'releases', broken, 'release-manifest.json'), 'not json');
  const result = prune(dir, '--keep-days', '14', '--keep', '1');
  assert.notEqual(result.status, 0);
  assert.equal(existsSync(join(history, 'releases', old)), true);
  assert.equal(existsSync(join(history, 'main.dart.1111111111.js')), true);
});

test('a project with no archive yet is fine', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'martha-prune-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const result = prune(dir);
  assert.equal(result.status, 0, result.stderr);
});
