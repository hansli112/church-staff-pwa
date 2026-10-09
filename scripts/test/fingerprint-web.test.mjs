import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const script = join(root, 'scripts/fingerprint-web.mjs');
const main = 'console.log("martha");\n';

function fixture(t, builds = [{ compileTarget: 'dart2js', renderer: 'canvaskit', mainJsPath: 'main.dart.js' }, {}]) {
  const web = mkdtempSync(join(tmpdir(), 'martha-web-'));
  t.after(() => rmSync(web, { recursive: true, force: true }));
  mkdirSync(join(web, 'assets'), { recursive: true });
  writeFileSync(join(web, 'assets/FontManifest.json'), '[]');
  writeFileSync(join(web, 'assets/AssetManifest.bin'), 'fixture asset manifest');
  writeFileSync(join(web, 'main.dart.js'), main);
  writeFileSync(join(web, 'flutter_bootstrap.js'), `_flutter.buildConfig = ${JSON.stringify({ engineRevision: 'test-engine', builds })};\n_flutter.loader.load({});\n`);
  writeFileSync(join(web, 'index.html'), '<base href="/nested/"><script src="flutter_bootstrap.js" async></script>');
  return web;
}

function fingerprint(web, ...args) {
  return execFileSync(process.execPath, [script, web, ...args], { encoding: 'utf8' });
}

function artifacts(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name)).flatMap((entry) => {
    const path = `${prefix}${entry.name}`;
    return entry.isDirectory() ? artifacts(join(dir, entry.name), `${path}/`) : [[path, readFileSync(join(dir, entry.name), 'utf8')]];
  });
}

function loaderOptions(bootstrap) {
  let options;
  runInNewContext(bootstrap, { _flutter: { loader: { load(value) { options = value; } } } });
  return JSON.parse(JSON.stringify(options));
}

function buildConfig(web) {
  const context = { _flutter: { loader: { load() {} } } };
  runInNewContext(readFileSync(join(web, 'flutter_bootstrap.js'), 'utf8'), context);
  return JSON.parse(JSON.stringify(context._flutter.buildConfig));
}

test('bootstrap loads a content-named main with identical bytes and keeps the legacy entry point', (t) => {
  const web = fixture(t);
  const html = readFileSync(join(web, 'index.html'), 'utf8');
  fingerprint(web);
  assert.equal(buildConfig(web).builds[0].mainJsPath, 'main.dart.d3e18322f0.js');
  assert.equal(readFileSync(join(web, 'main.dart.d3e18322f0.js'), 'utf8'), main);
  assert.equal(readFileSync(join(web, 'main.dart.js'), 'utf8'), main);
  assert.equal(readFileSync(join(web, 'index.html'), 'utf8'), html);
});

test('malformed bootstrap fails clearly without changing deployment files', (t) => {
  const web = fixture(t);
  const malformed = '_flutter.buildConfig = {"builds":"not-builds"};';
  writeFileSync(join(web, 'flutter_bootstrap.js'), malformed);
  const result = spawnSync(process.execPath, [script, web], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /fingerprint-web:.*invalid Flutter build configuration/);
  assert.equal(readFileSync(join(web, 'flutter_bootstrap.js'), 'utf8'), malformed);
  assert.deepEqual(readdirSync(web).sort(), ['assets', 'flutter_bootstrap.js', 'index.html', 'main.dart.js']);
});

test('deferred code is content-named before main and repeated processing keeps fallback metadata stable', (t) => {
  const web = fixture(t);
  writeFileSync(join(web, 'main.dart.js'), 'const deferred = ["main.dart.js_1.part.js"];\n');
  writeFileSync(join(web, 'main.dart.js_1.part.js'), 'deferred();\n');
  fingerprint(web);
  const config = buildConfig(web);
  assert.deepEqual(config.builds[1], {});
  assert.equal(config.builds[0].mainJsPath, 'main.dart.16300f0dad.js');
  const rewritten = 'const deferred = ["main.dart.js_1.part.5567a01230.js"];\n';
  assert.equal(readFileSync(join(web, config.builds[0].mainJsPath), 'utf8'), rewritten);
  assert.equal(readFileSync(join(web, 'main.dart.js_1.part.5567a01230.js'), 'utf8'), 'deferred();\n');
  const before = artifacts(web);
  fingerprint(web);
  assert.deepEqual(artifacts(web), before);
});

test('project archive keeps earlier JS and fonts through new builds and failed deployment attempts', (t) => {
  const archive = mkdtempSync(join(tmpdir(), 'martha-archive-'));
  t.after(() => rmSync(archive, { recursive: true, force: true }));
  const options = ['--archive', archive, '--project', 'test-martha-dev'];
  const a = fixture(t);
  mkdirSync(join(a, 'assets/fonts'), { recursive: true });
  writeFileSync(join(a, 'assets/fonts/Icons.otf'), 'icons A');
  writeFileSync(join(a, 'assets/FontManifest.json'), '[{"family":"Icons","fonts":[{"asset":"fonts/Icons.otf"}]}]');
  execFileSync(process.execPath, [join(root, 'scripts/fingerprint-fonts.mjs'), a]);
  fingerprint(a, ...options);

  const b = fixture(t);
  writeFileSync(join(b, 'main.dart.js'), 'console.log("changed");\n');
  mkdirSync(join(b, 'assets/fonts'), { recursive: true });
  writeFileSync(join(b, 'assets/fonts/Icons.otf'), 'icons B');
  writeFileSync(join(b, 'assets/FontManifest.json'), '[{"family":"Icons","fonts":[{"asset":"fonts/Icons.otf"}]}]');
  execFileSync(process.execPath, [join(root, 'scripts/fingerprint-fonts.mjs'), b]);
  // Predeploy can prepare B even when Firebase fails afterward; repeat it,
  // then try another fresh build. Neither attempt may rotate away A.
  fingerprint(b, ...options);
  fingerprint(b, ...options);
  const c = fixture(t);
  fingerprint(c, ...options);
  assert.equal(readFileSync(join(c, 'main.dart.d3e18322f0.js'), 'utf8'), main);
  assert.equal(readFileSync(join(c, 'main.dart.c8606d046a.js'), 'utf8'), 'console.log("changed");\n');
  assert.equal(readFileSync(join(c, 'assets/fonts/Icons.a2f6674ce7.otf'), 'utf8'), 'icons A');
  assert.equal(readFileSync(join(c, 'assets/fonts/Icons.29726c3939.otf'), 'utf8'), 'icons B');
});

test('missing or unsupported Flutter inputs fail before writing content-named assets', (t) => {
  const cases = [
    ['missing bootstrap', (web) => rmSync(join(web, 'flutter_bootstrap.js'))],
    ['missing main', (web) => rmSync(join(web, 'main.dart.js'))],
    ['missing build configuration', (web) => writeFileSync(join(web, 'flutter_bootstrap.js'), '_flutter.loader.load({});')],
    ['invalid JSON', (web) => writeFileSync(join(web, 'flutter_bootstrap.js'), '_flutter.buildConfig = {broken};')],
    ['missing main path', (web) => writeFileSync(join(web, 'flutter_bootstrap.js'), '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js"}]};')],
    ['unsupported main path', (web) => writeFileSync(join(web, 'flutter_bootstrap.js'), '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","mainJsPath":"elsewhere.js"}]};')],
    ['missing deferred code', (web) => writeFileSync(join(web, 'main.dart.js'), 'const deferred = ["main.dart.js_1.part.js"];')],
  ];
  for (const [label, prepare] of cases) {
    const web = fixture(t);
    prepare(web);
    const before = artifacts(web);
    const result = spawnSync(process.execPath, [script, web], { encoding: 'utf8' });
    assert.equal(result.status, 1, label);
    assert.match(result.stderr, /^fingerprint-web: /, label);
    assert.deepEqual(artifacts(web), before, label);
  }
  const result = spawnSync(process.execPath, [script], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /usage: fingerprint-web\.mjs/);
});

test('archive isolates projects and contains only compiled hashes and hashed fonts', (t) => {
  const archive = mkdtempSync(join(tmpdir(), 'martha-archive-'));
  t.after(() => rmSync(archive, { recursive: true, force: true }));
  const dev = fixture(t);
  for (const file of ['unrelated.d3e18322f0.js', 'main.dart.d3e18322f0.js.map', 'flutter_bootstrap.d3e18322f0.js']) {
    writeFileSync(join(dev, file), main);
  }
  fingerprint(dev, '--archive', archive, '--project', 'test-dev');
  assert.deepEqual(readdirSync(join(archive, 'test-dev')), ['asset-bundles', 'main.dart.d3e18322f0.js']);
  const prod = fixture(t);
  writeFileSync(join(prod, 'main.dart.js'), 'console.log("changed");\n');
  // Unrecognized files in the archive must never be restored either.
  mkdirSync(join(archive, 'test-prod'), { recursive: true });
  writeFileSync(join(archive, 'test-prod/private.js'), 'not a compiled asset');
  fingerprint(prod, '--archive', archive, '--project', 'test-prod');
  assert.equal(existsSync(join(prod, 'main.dart.d3e18322f0.js')), false);
  assert.equal(existsSync(join(prod, 'private.js')), false);
  assert.equal(buildConfig(prod).builds[0].mainJsPath, 'main.dart.c8606d046a.js');
  const switched = spawnSync(process.execPath, [script, dev, '--archive', archive, '--project', 'test-prod'], { encoding: 'utf8' });
  assert.equal(switched.status, 1);
  assert.match(switched.stderr, /another Firebase project/);
  for (const [dir, project] of [[archive, '../prod'], ['', 'test-dev']]) {
    const web = fixture(t);
    const invalid = spawnSync(process.execPath, [script, web, '--archive', dir, '--project', project], { encoding: 'utf8' });
    assert.equal(invalid.status, 1);
    assert.match(invalid.stderr, /usage:/);
    assert.equal(existsSync(join(web, 'main.dart.d3e18322f0.js')), false);
  }
});

test('archive rejects a malformed font hash even if a parent directory contains the correct hash', (t) => {
  const archive = mkdtempSync(join(tmpdir(), 'martha-archive-'));
  t.after(() => rmSync(archive, { recursive: true, force: true }));
  const parent = join(archive, 'test-dev/assets/fonts.a2f6674ce7.cache');
  mkdirSync(parent, { recursive: true });
  writeFileSync(join(parent, 'Icons.0000000000.otf'), 'icons A');
  const web = fixture(t);
  const result = spawnSync(process.execPath, [script, web, '--archive', archive, '--project', 'test-dev'], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /content hash mismatch/);
  assert.equal(existsSync(join(web, 'assets/fonts.a2f6674ce7.cache/Icons.0000000000.otf')), false);
});

test('retry repairs an interrupted archive copy without changing a complete prior asset', (t) => {
  const archive = mkdtempSync(join(tmpdir(), 'martha-archive-'));
  t.after(() => rmSync(archive, { recursive: true, force: true }));
  const history = join(archive, 'test-dev');
  mkdirSync(history, { recursive: true });
  // A partial final name can be left by the old direct-copy implementation.
  // Temporary files from newer interrupted attempts are never public assets.
  writeFileSync(join(history, 'main.dart.d3e18322f0.js'), 'console');
  writeFileSync(join(history, '.pending-main.dart.d3e18322f0.js'), 'partial');
  const published = join(history, 'main.dart.c8606d046a.js');
  writeFileSync(published, 'console.log("changed");\n');
  const before = readFileSync(published);
  const web = fixture(t);
  fingerprint(web, '--archive', archive, '--project', 'test-dev');
  assert.equal(readFileSync(join(history, 'main.dart.d3e18322f0.js'), 'utf8'), main);
  assert.deepEqual(readFileSync(published), before);
  assert.equal(existsSync(join(web, '.pending-main.dart.d3e18322f0.js')), false);
});

test('retry restores only missing historical assets and leaves existing bytes and timestamps intact', (t) => {
  const archive = mkdtempSync(join(tmpdir(), 'martha-archive-'));
  t.after(() => rmSync(archive, { recursive: true, force: true }));
  const history = join(archive, 'test-dev');
  mkdirSync(history, { recursive: true });
  const old = 'main.dart.c8606d046a.js';
  writeFileSync(join(history, old), 'console.log("changed");\n');
  const web = fixture(t);
  const options = ['--archive', archive, '--project', 'test-dev'];
  fingerprint(web, ...options);
  const restored = join(web, old);
  const originalTime = new Date('2000-01-01T00:00:00Z');
  utimesSync(restored, originalTime, originalTime);
  const before = statSync(restored).mtimeMs;
  fingerprint(web, ...options);
  assert.equal(statSync(restored).mtimeMs, before);
  assert.equal(readFileSync(restored, 'utf8'), 'console.log("changed");\n');
  rmSync(restored);
  fingerprint(web, ...options);
  assert.equal(readFileSync(restored, 'utf8'), 'console.log("changed");\n');
});

test('an in-flight A bootstrap still loads its own manifest and font after B lands', (t) => {
  const archive = mkdtempSync(join(tmpdir(), 'martha-archive-'));
  t.after(() => rmSync(archive, { recursive: true, force: true }));
  const options = ['--archive', archive, '--project', 'test-dev'];
  const a = fixture(t);
  mkdirSync(join(a, 'assets/fonts'), { recursive: true });
  writeFileSync(join(a, 'assets/fonts/Icons.otf'), 'icons A');
  writeFileSync(join(a, 'assets/FontManifest.json'), '[{"family":"Icons","fonts":[{"asset":"fonts/Icons.otf"}]}]');
  writeFileSync(join(a, 'assets/logo.png'), 'A image');
  writeFileSync(join(a, 'flutter_bootstrap.js'), readFileSync(join(a, 'flutter_bootstrap.js'), 'utf8')
    .replace('_flutter.loader.load({});', '_flutter.loader.load({config:{renderer:"canvaskit",debugShowSemantics:true},nonce:"nonce",serviceWorkerSettings:{serviceWorkerVersion:"test"}});'));
  execFileSync(process.execPath, [join(root, 'scripts/fingerprint-fonts.mjs'), a]);
  fingerprint(a, ...options);
  const oldBootstrap = readFileSync(join(a, 'flutter_bootstrap.js'), 'utf8');
  const oldOptions = loaderOptions(oldBootstrap);
  assert.match(oldOptions.config.assetBase, /^asset-bundles\/[0-9a-f]{10}\/$/);
  assert.equal(oldOptions.config.renderer, 'canvaskit');
  assert.equal(oldOptions.config.debugShowSemantics, true);
  assert.equal(oldOptions.nonce, 'nonce');
  assert.equal(oldOptions.serviceWorkerSettings.serviceWorkerVersion, 'test');
  const oldManifest = readFileSync(join(a, 'assets/FontManifest.json'), 'utf8');

  const b = fixture(t);
  mkdirSync(join(b, 'assets/fonts'), { recursive: true });
  writeFileSync(join(b, 'assets/fonts/Icons.otf'), 'icons B');
  writeFileSync(join(b, 'assets/FontManifest.json'), '[{"family":"Icons","fonts":[{"asset":"fonts/Icons.otf"}]}]');
  writeFileSync(join(b, 'assets/logo.png'), 'B image');
  execFileSync(process.execPath, [join(root, 'scripts/fingerprint-fonts.mjs'), b]);
  fingerprint(b, ...options);
  const currentOptions = loaderOptions(readFileSync(join(b, 'flutter_bootstrap.js'), 'utf8'));
  assert.notEqual(currentOptions.config.assetBase, oldOptions.config.assetBase);
  const manifestPath = join(b, oldOptions.config.assetBase, 'assets/FontManifest.json');
  assert.equal(readFileSync(manifestPath, 'utf8'), oldManifest);
  const oldFont = JSON.parse(readFileSync(manifestPath, 'utf8'))[0].fonts[0].asset;
  assert.equal(readFileSync(join(b, oldOptions.config.assetBase, 'assets', oldFont), 'utf8'), 'icons A');
  assert.equal(readFileSync(join(b, oldOptions.config.assetBase, 'assets/logo.png'), 'utf8'), 'A image');
  // A tab that fetched the legacy stable manifest before deployment but
  // has not downloaded its font yet must still resolve that font's old URL.
  assert.equal(readFileSync(join(b, 'assets', oldFont), 'utf8'), 'icons A');
  const before = readFileSync(join(b, 'flutter_bootstrap.js'), 'utf8');
  fingerprint(b, ...options);
  assert.equal(readFileSync(join(b, 'flutter_bootstrap.js'), 'utf8'), before, 'historical loose fonts do not alter the current asset tree');
  assert.equal(readFileSync(join(b, 'index.html'), 'utf8'), '<base href="/nested/"><script src="flutter_bootstrap.js" async></script>');
});

test('an existing immutable bundle is validated and never silently overwritten', (t) => {
  const archive = mkdtempSync(join(tmpdir(), 'martha-archive-'));
  t.after(() => rmSync(archive, { recursive: true, force: true }));
  const web = fixture(t);
  const options = ['--archive', archive, '--project', 'test-dev'];
  fingerprint(web, ...options);
  const base = loaderOptions(readFileSync(join(web, 'flutter_bootstrap.js'), 'utf8')).config.assetBase;
  const archived = join(archive, 'test-dev', base, 'assets/AssetManifest.bin');
  writeFileSync(archived, 'unexpected contents');
  const result = spawnSync(process.execPath, [script, web, ...options], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /asset bundle (?:hash mismatch|collision)/);
  assert.equal(readFileSync(archived, 'utf8'), 'unexpected contents');
});

test('unchanged asset trees reuse one bundle and ignore interrupted temporary directories', (t) => {
  const archive = mkdtempSync(join(tmpdir(), 'martha-archive-'));
  t.after(() => rmSync(archive, { recursive: true, force: true }));
  const options = ['--archive', archive, '--project', 'test-dev'];
  const a = fixture(t);
  fingerprint(a, ...options);
  const base = loaderOptions(readFileSync(join(a, 'flutter_bootstrap.js'), 'utf8')).config.assetBase;
  const b = fixture(t);
  writeFileSync(join(b, 'main.dart.js'), 'console.log("changed");\n');
  fingerprint(b, ...options);
  assert.equal(loaderOptions(readFileSync(join(b, 'flutter_bootstrap.js'), 'utf8')).config.assetBase, base);
  const bundles = join(archive, 'test-dev/asset-bundles');
  assert.equal(readdirSync(bundles).length, 1, 'main-only changes do not copy another asset tree');
  const pending = join(bundles, '.pending-interrupted/assets');
  mkdirSync(pending, { recursive: true });
  writeFileSync(join(pending, 'FontManifest.json'), 'partial manifest');
  const local = join(b, base, 'assets/AssetManifest.bin');
  const saved = join(archive, 'test-dev', base, 'assets/AssetManifest.bin');
  const oldTime = new Date('2000-01-01T00:00:00Z');
  utimesSync(local, oldTime, oldTime);
  utimesSync(saved, oldTime, oldTime);
  const localBefore = statSync(local).mtimeMs;
  const savedBefore = statSync(saved).mtimeMs;
  fingerprint(b, ...options);
  assert.equal(statSync(local).mtimeMs, localBefore);
  assert.equal(statSync(saved).mtimeMs, savedBefore);
  assert.equal(existsSync(join(b, 'asset-bundles/.pending-interrupted')), false);
  rmSync(join(b, base), { recursive: true });
  fingerprint(b, ...options);
  assert.equal(readFileSync(local, 'utf8'), 'fixture asset manifest');
});

test('asset snapshots reject script/maps, missing font bytes, and linked asset roots before publication', (t) => {
  const linked = fixture(t);
  const cases = [
    (web) => writeFileSync(join(web, 'assets/unrelated.js'), 'not a Flutter asset'),
    (web) => writeFileSync(join(web, 'assets/unrelated.cjs'), 'not a Flutter asset'),
    (web) => writeFileSync(join(web, 'assets/source.map'), 'not a Flutter asset'),
    (web) => writeFileSync(join(web, 'assets/FontManifest.json'), '[{"fonts":[{"asset":"missing.otf"}]}]'),
    (web) => { rmSync(join(web, 'assets'), { recursive: true }); symlinkSync(join(linked, 'assets'), join(web, 'assets'), 'dir'); },
  ];
  for (const prepare of cases) {
    const web = fixture(t);
    prepare(web);
    const result = spawnSync(process.execPath, [script, web], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /(?:unsupported asset|missing font asset)/);
    assert.equal(existsSync(join(web, 'asset-bundles')), false);
    assert.equal(existsSync(join(web, 'main.dart.d3e18322f0.js')), false);
  }
});

test('generated loader calls keep options/comments intact and support the no-argument form', (t) => {
  const current = fixture(t);
  const configured = readFileSync(join(current, 'flutter_bootstrap.js'), 'utf8').replace('_flutter.loader.load({});', `_flutter.loader.load({
  serviceWorkerSettings: { serviceWorkerVersion: "test" /* deprecated worker (unchanged) */ },
  config: {renderer: "canvaskit", canvasKitBaseUrl: "https://cdn.invalid/(engine)/"},
  nonce: "nonce)", // ignored closing parenthesis )
});`);
  writeFileSync(join(current, 'flutter_bootstrap.js'), configured);
  fingerprint(current);
  const options = loaderOptions(readFileSync(join(current, 'flutter_bootstrap.js'), 'utf8'));
  assert.equal(options.config.canvasKitBaseUrl, 'https://cdn.invalid/(engine)/');
  assert.equal(options.nonce, 'nonce)');
  assert.equal(options.serviceWorkerSettings.serviceWorkerVersion, 'test');
  assert.match(options.config.assetBase, /^asset-bundles\/[0-9a-f]{10}\/$/);
  const noArguments = fixture(t);
  writeFileSync(join(noArguments, 'flutter_bootstrap.js'), readFileSync(join(noArguments, 'flutter_bootstrap.js'), 'utf8').replace('_flutter.loader.load({});', '_flutter.loader.load();'));
  fingerprint(noArguments);
  assert.equal(loaderOptions(readFileSync(join(noArguments, 'flutter_bootstrap.js'), 'utf8')).config.assetBase, options.config.assetBase);
});

test('real dart2wasm builds fail before changing any output or project archive', (t) => {
  const archive = mkdtempSync(join(tmpdir(), 'martha-archive-'));
  t.after(() => rmSync(archive, { recursive: true, force: true }));
  const wasm = { compileTarget: 'dart2wasm', renderer: 'skwasm', mainWasmPath: 'main.dart.wasm', jsSupportRuntimePath: 'main.dart.mjs' };
  for (const builds of [[wasm, { compileTarget: 'dart2js', renderer: 'canvaskit', mainJsPath: 'main.dart.js' }, {}], [wasm]]) {
    const web = fixture(t, builds);
    writeFileSync(join(web, 'main.dart.wasm'), 'wasm entry');
    writeFileSync(join(web, 'main.dart.mjs'), 'module entry');
    const before = artifacts(web);
    const result = spawnSync(process.execPath, [script, web, '--archive', archive, '--project', 'test-dev'], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /dart2wasm builds are not supported/);
    assert.deepEqual(artifacts(web), before);
    assert.deepEqual(readdirSync(archive), []);
  }
});

test('build-kind preflight is read-only for supported generated JavaScript output', (t) => {
  const web = fixture(t);
  const before = artifacts(web);
  fingerprint(web, '--check-build');
  assert.deepEqual(artifacts(web), before);
});
