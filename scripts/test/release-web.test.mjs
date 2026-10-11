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
function fixture(t, { wasm = false } = {}) {
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
  const js = '{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}';
  const builds = wasm ? `{"compileTarget":"dart2wasm","renderer":"skwasm","mainWasmPath":"main.dart.wasm","jsSupportRuntimePath":"main.dart.mjs"},${js}` : `${js},{}`;
  writeFileSync(join(web, 'flutter_bootstrap.js'), `_flutter.buildConfig = {"builds":[${builds}]}; _flutter.loader.load({});`);
  if (wasm) {
    writeFileSync(join(web, 'main.dart.wasm'), 'wasm entry');
    writeFileSync(join(web, 'main.dart.mjs'), 'module entry');
  }
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
  assert.ok(manifest.files.some((f) => /main\.dart\.[a-f0-9]+\.js$/.test(f.url)));
  assert.ok(manifest.files.every((f) => digest(readFileSync(join(web, f.url.slice(1)))) === f.sha256));
  assert.equal(existsSync(join(dir, 'archive/demo-martha', manifest.shell.slice(1))), true);
  const again = packageRelease(web, join(dir, 'archive'));
  assert.deepEqual(again, release);
});

test('each browser caches only the main entry it ran, and the wasm renderer stays single-threaded', (t) => {
  const { dir, web } = fixture(t, { wasm: true });
  const release = packageRelease(web, join(dir, 'archive'));
  const manifest = JSON.parse(readFileSync(join(web, release.manifest.slice(1)), 'utf8'));
  const entries = manifest.files.filter((f) => /^\/main\.dart\.[0-9a-f]{10}\.(?:js|wasm|mjs)$/.test(f.url));
  assert.deepEqual(entries.map((f) => f.url.replace(/\.[0-9a-f]{10}\.js$/, '.<hash>.js')).sort(), ['/main.dart.<hash>.js', '/main.dart.ad50759298.wasm', '/main.dart.b108204f3a.mjs']);
  // Like the engine files: on first install, cached only if this page used it.
  assert.ok(entries.every((f) => f.optional && f.engine));
  const bootstrap = readFileSync(join(web, manifest.bootstrap.slice(1)), 'utf8');
  let options;
  new Function('_flutter', bootstrap)({ buildConfig: {}, loader: { load(value) { options = value; } } });
  // Multi-threaded skwasm can corrupt text on some Flutter versions, and
  // its cross-origin isolation would break the Google sign-in popup.
  assert.equal(options.config.forceSingleThreadedSkwasm, true);
  assert.equal(options.config.canvasKitBaseUrl, `/releases/${release.id}/canvaskit/`);
});
