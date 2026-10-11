import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const digest = (value) => createHash('sha256').update(value).digest('hex');
function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'martha-release-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const web = join(dir, 'web');
  mkdirSync(join(web, 'assets'), { recursive: true });
  mkdirSync(join(web, 'icons'));
  mkdirSync(join(web, 'canvaskit'));
  writeFileSync(join(web, 'assets/FontManifest.json'), '[]');
  writeFileSync(join(web, 'assets/AssetManifest.bin'), 'manifest');
  writeFileSync(join(web, 'icons/Icon-192.png'), 'icon');
  writeFileSync(join(web, 'favicon.png'), 'favicon');
  writeFileSync(join(web, 'manifest.json'), '{}');
  writeFileSync(join(web, 'canvaskit/canvaskit.js'), 'engine');
  writeFileSync(join(web, 'canvaskit/canvaskit.wasm'), 'wasm');
  writeFileSync(join(web, 'martha_app.js'), 'window.marthaUpdate = {};');
  writeFileSync(join(web, 'martha_app_sw.js'), 'self.addEventListener("fetch", () => {});');
  writeFileSync(join(web, 'app.html'), '<html><head><base href="/"></head><body><div id="splash"></div><script src="martha_app.js"></script><script src="flutter_bootstrap.js" async></script></body></html>');
  writeFileSync(join(web, 'main.dart.js'), 'const chunks = ["main.dart.js_1.part.js"];');
  writeFileSync(join(web, 'main.dart.js_1.part.js'), 'deferred();');
  writeFileSync(join(web, 'flutter_bootstrap.js'), '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]}; _flutter.loader.load({});');
  execFileSync(process.execPath, [join(root, 'scripts/fingerprint-web.mjs'), web, '--archive', join(dir, 'archive'), '--project', 'demo-martha']);
  return { dir, web };
}
function packageRelease(web, archive) {
  execFileSync(process.execPath, [join(root, 'scripts/release-web.mjs'), web, '--archive', archive, '--project', 'demo-martha']);
  return JSON.parse(readFileSync(join(web, 'release.json'), 'utf8'));
}

test('release manifest binds the real boot shell and keeps deferred code optional', (t) => {
  const { dir, web } = fixture(t);
  const release = packageRelease(web, join(dir, 'archive'));
  const manifestBytes = readFileSync(join(web, release.manifest.slice(1)));
  assert.equal(digest(manifestBytes), release.manifestSha256);
  const manifest = JSON.parse(manifestBytes);
  const shell = readFileSync(join(web, manifest.shell.slice(1)), 'utf8');
  assert.match(shell, new RegExp(`"id":"${release.id}"`));
  assert.match(shell, new RegExp(`/releases/${release.id}/flutter_bootstrap\\.js`));
  assert.ok(manifest.files.some((f) => /\.part\./.test(f.url) && f.optional));
  assert.ok(manifest.files.some((f) => /main\.dart\.[a-f0-9]+\.js$/.test(f.url) && !f.optional));
  assert.ok(manifest.files.every((f) => digest(readFileSync(join(web, f.url.slice(1)))) === f.sha256));
  assert.equal(existsSync(join(dir, 'archive/demo-martha', manifest.shell.slice(1))), true);
  const again = packageRelease(web, join(dir, 'archive'));
  assert.deepEqual(again, release);
});
