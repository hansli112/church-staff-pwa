import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { cp, link, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { promisify } from 'node:util';
import vm from 'node:vm';
import defaults from '../worker/generated_config.js';
import { prepareDeployment } from './prepare-deployment.mjs';
import { finalizeWebDeployment } from './finalize-web-deployment.mjs';

const exec = promisify(execFile);
const ROOT = path.resolve(import.meta.dirname, '..');
const FIREBASE = {
  FIREBASE_API_KEY: 'dummy-public-api-key',
  FIREBASE_AUTH_DOMAIN: 'example.firebaseapp.com',
  FIREBASE_PROJECT_ID: 'example',
  FIREBASE_STORAGE_BUCKET: 'example.firebasestorage.app',
  FIREBASE_MESSAGING_SENDER_ID: '123456789',
  FIREBASE_APP_ID: '1:123456789:web:example',
  FIREBASE_MEASUREMENT_ID: 'G-EXAMPLE',
};

async function fixture(t) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'church-finalizer-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const buildDir = path.join(dir, 'build/web');
  const stagingDir = path.join(dir, 'staged');
  const config = { ...structuredClone(defaults), appName: 'Example <Community>', shortName: 'Friends' };
  const configPath = path.join(dir, 'church.json');
  await writeFile(configPath, JSON.stringify(config));
  await prepareDeployment({ configPath, outDir: stagingDir });
  // A small Flutter-shaped fixture keeps the test offline. Real tracked web
  // templates and real prepareDeployment output exercise the production seam.
  await cp(path.join(ROOT, 'web'), buildDir, { recursive: true });
  const untouched = new Map([
    ['main.dart.js', 'compiled Flutter bundle'],
    ['flutter_bootstrap.js', 'local CanvasKit bootstrap'],
    ['canvaskit/canvaskit.wasm', Buffer.from([0, 97, 115, 109])],
    ['canvaskit/canvaskit.js', 'local third-party engine'],
    ['assets/FontManifest.json', '[]'],
    ['version.json', JSON.stringify({ version: '0123456789abcdef', build_number: '42', branch: 'dev', generated_at: '2026-01-01T00:00:00Z' })],
    ['_worker.js/index.js', 'export default { fetch() {} };'],
    ['_worker.js/chunks/route.js', 'export const route = 1;'],
  ]);
  for (const [name, bytes] of untouched) {
    const target = path.join(buildDir, name);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, bytes);
  }
  return {
    dir, config, untouched,
    options: { buildDir, stagingDir, firebaseConfig: { ...FIREBASE }, buildVersion: '01234567-42', vendorVersion: 'flutter-3.41.0' },
  };
}

async function snapshot(dir) {
  const files = new Map();
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const target = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      for (const [name, bytes] of await snapshot(target)) files.set(path.join(entry.name, name), bytes);
    } else if (entry.isFile()) files.set(entry.name, await readFile(target));
  }
  return files;
}

function firebaseRuntime(source) {
  let config;
  let notification;
  const imports = [];
  vm.runInNewContext(source, {
    importScripts: (url) => imports.push(url),
    firebase: {
      initializeApp: (value) => { config = value; },
      messaging: () => ({ onBackgroundMessage: (listener) => listener({}) }),
    },
    self: { registration: { showNotification: (title, options) => { notification = { title, options }; } } },
  });
  return JSON.parse(JSON.stringify({ config, notification, imports }));
}

test('finalizer stages configured branding and cache/FCM values without changing other build assets', async (t) => {
  const { options, config, untouched } = await fixture(t);
  const stagingBefore = await snapshot(options.stagingDir);
  const sourceBefore = await snapshot(path.join(ROOT, 'web'));
  const result = await finalizeWebDeployment(options);
  assert.equal(result.buildDir, options.buildDir);
  const output = await snapshot(options.buildDir);
  for (const [name, bytes] of untouched) assert.deepEqual(output.get(name), Buffer.from(bytes), name);
  assert.deepEqual(await snapshot(options.stagingDir), stagingBefore);
  assert.deepEqual(await snapshot(path.join(ROOT, 'web')), sourceBefore);
  assert.match(output.get('index.html').toString(), /<base href="\/">/);
  assert.match(output.get('index.html').toString(), /<title>Example &lt;Community&gt;<\/title>/);
  assert.equal(JSON.parse(output.get('manifest.json')).name, config.appName);
  for (const icon of Object.values(config.icons)) assert.deepEqual(output.get(icon), stagingBefore.get(path.join('web', icon)));
  const cacheSource = output.get('cache_sw.js').toString();
  assert.doesNotMatch(cacheSource, /__BUILD_VERSION__|__VENDOR_VERSION__/);
  const names = vm.runInNewContext(`${cacheSource}\n[CACHE_NAME, VENDOR_CACHE_NAME]`, { self: { addEventListener() {} } });
  assert.deepEqual(Array.from(names), ['church-staff-pwa-01234567-42', 'church-staff-pwa-vendor-flutter-3.41.0']);
  const runtime = firebaseRuntime(output.get('firebase-messaging-sw.js').toString());
  assert.deepEqual(Object.values(runtime.config), Object.values(FIREBASE));
  assert.equal(runtime.notification.title, config.appName);
  assert.equal(runtime.notification.options.icon, '/' + config.icons.icon192);
  assert.equal(runtime.imports.length, 2);
  for (const name of ['church.json', 'dart-defines.json', 'firestore.rules', 'firebase.json', 'worker/generated_config.js', 'functions/api/calendar/events.js']) {
    assert.equal(output.has(name), false, `${name} must not be served`);
  }
});

test('only seven public Firebase keys are serialized and optional values default to empty', async (t) => {
  const { options } = await fixture(t);
  delete options.firebaseConfig.FIREBASE_STORAGE_BUCKET;
  delete options.firebaseConfig.FIREBASE_MEASUREMENT_ID;
  options.firebaseConfig.CHURCH_CONFIG_JSON = 'not a Firebase field';
  options.firebaseConfig.GOOGLE_SERVICE_ACCOUNT_JSON = 'private server credential must not leak';
  await writeFile(path.join(options.stagingDir, 'server-key.json'), 'another private value');
  await finalizeWebDeployment(options);
  const output = await snapshot(options.buildDir);
  const source = output.get('firebase-messaging-sw.js').toString();
  const { config } = firebaseRuntime(source);
  assert.equal(config.storageBucket, '');
  assert.equal(config.measurementId, '');
  assert.equal(Object.keys(config).length, 7);
  assert.doesNotMatch(Buffer.concat([...output.values()]).toString(), /private server credential|another private value|not a Firebase field/);
});

test('Firebase replacement keeps quotes, newlines, slashes and replacement syntax as data', async (t) => {
  const { options } = await fixture(t);
  const unusual = "quote'\"; throw Error('executed'); //\\\n$& $` ${value} | &";
  for (const key of Object.keys(options.firebaseConfig)) options.firebaseConfig[key] = unusual;
  await finalizeWebDeployment(options);
  const { config } = firebaseRuntime(await readFile(path.join(options.buildDir, 'firebase-messaging-sw.js'), 'utf8'));
  assert.deepEqual(Object.values(config), Array(7).fill(unusual));
});

test('missing or invalid Firebase fields fail before modifying the build', async (t) => {
  const { options } = await fixture(t);
  const before = await snapshot(options.buildDir);
  for (const key of ['FIREBASE_API_KEY', 'FIREBASE_AUTH_DOMAIN', 'FIREBASE_PROJECT_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_APP_ID']) {
    for (const value of [undefined, '', '  ', 123, {}]) {
      await assert.rejects(() => finalizeWebDeployment({ ...options, firebaseConfig: { ...FIREBASE, [key]: value } }), new RegExp(key));
    }
  }
  for (const firebaseConfig of [null, [], 'not-object']) await assert.rejects(() => finalizeWebDeployment({ ...options, firebaseConfig }), /JSON object/);
  await assert.rejects(() => finalizeWebDeployment({ ...options, firebaseConfig: { ...FIREBASE, FIREBASE_STORAGE_BUCKET: 5 } }), /FIREBASE_STORAGE_BUCKET/);
  assert.deepEqual(await snapshot(options.buildDir), before);
});

test('unsafe, empty or unbounded versions fail before writing', async (t) => {
  const { options } = await fixture(t);
  const before = await snapshot(options.buildDir);
  for (const name of ['buildVersion', 'vendorVersion']) {
    for (const value of [undefined, '', 42, '../path', "x';alert(1)//", 'x\ny', 'x y', 'x'.repeat(201)]) {
      await assert.rejects(() => finalizeWebDeployment({ ...options, [name]: value }), /cache version/);
    }
  }
  assert.deepEqual(await snapshot(options.buildDir), before);
});

test('cache guards require actual declarations, reject residual markers and reject refinalization', async (t) => {
  const { options } = await fixture(t);
  const target = path.join(options.buildDir, 'cache_sw.js');
  const source = await readFile(target, 'utf8');
  for (const changed of [
    source.replace("const CACHE_VERSION = '__BUILD_VERSION__';", "const CACHE_VERSION = 'already-built';"),
    source.replace("const VENDOR_VERSION = '__VENDOR_VERSION__';", ''),
    source + "\nconst CACHE_VERSION = '__BUILD_VERSION__';\n",
    source + "\nconst extra = '__BUILD_NEW_FIELD__';\n",
  ]) {
    await writeFile(target, changed);
    const before = await snapshot(options.buildDir);
    await assert.rejects(() => finalizeWebDeployment(options), /placeholder|declaration/);
    assert.deepEqual(await snapshot(options.buildDir), before);
  }
  await writeFile(target, source);
  await finalizeWebDeployment(options);
  const finalized = await snapshot(options.buildDir);
  await assert.rejects(() => finalizeWebDeployment(options), /fresh Flutter build/);
  assert.deepEqual(await snapshot(options.buildDir), finalized);
});

test('missing, duplicated or unhandled Firebase placeholders fail before copying staging', async (t) => {
  const { options } = await fixture(t);
  const target = path.join(options.stagingDir, 'web/firebase-messaging-sw.js');
  const source = await readFile(target, 'utf8');
  const before = await snapshot(options.buildDir);
  for (const changed of [
    source.replace("'__FIREBASE_API_KEY__'", "'already-replaced'"),
    source + "\nconst duplicate = '__FIREBASE_API_KEY__';\n",
    source + "\nconst unknown = '__FIREBASE_NEW_FIELD__';\n",
  ]) {
    await writeFile(target, changed);
    await assert.rejects(() => finalizeWebDeployment(options), /literal|placeholders/);
    assert.deepEqual(await snapshot(options.buildDir), before);
  }
});

test('incomplete staging cannot silently publish default branding', async (t) => {
  const { options } = await fixture(t);
  const before = await snapshot(options.buildDir);
  await rm(path.join(options.stagingDir, 'web/manifest.json'));
  await assert.rejects(() => finalizeWebDeployment(options), /prepare-deployment/);
  assert.deepEqual(await snapshot(options.buildDir), before);
});

test('source staging links and destination directory/file links are rejected without writes', async (t) => {
  const { options, dir } = await fixture(t);
  const outside = path.join(dir, 'outside');
  await mkdir(outside);
  await writeFile(path.join(outside, 'keep.txt'), 'keep');
  const stagedLink = path.join(options.stagingDir, 'web/linked.txt');
  await symlink(path.join(outside, 'keep.txt'), stagedLink);
  const before = await snapshot(options.buildDir);
  await assert.rejects(() => finalizeWebDeployment(options), /symbolic links/);
  assert.deepEqual(await snapshot(options.buildDir), before);
  await rm(stagedLink);

  const icons = path.join(options.buildDir, 'icons');
  await rm(icons, { recursive: true });
  await symlink(outside, icons);
  const withoutIcons = await snapshot(options.buildDir);
  await assert.rejects(() => finalizeWebDeployment(options), /links/);
  assert.deepEqual(await snapshot(options.buildDir), withoutIcons);
  await rm(icons);

  const index = path.join(options.buildDir, 'index.html');
  await rm(index);
  for (const makeLink of [symlink, link]) {
    await makeLink(path.join(outside, 'keep.txt'), index);
    await assert.rejects(() => finalizeWebDeployment(options), /links/);
    assert.equal(await readFile(path.join(outside, 'keep.txt'), 'utf8'), 'keep');
    await rm(index);
  }
  assert.deepEqual(await readdir(outside), ['keep.txt']);
});

test('tracked source targets and overlapping directories are rejected', async (t) => {
  const { options } = await fixture(t);
  for (const buildDir of [ROOT, path.join(ROOT, 'web'), path.join(ROOT, 'scripts'), path.dirname(ROOT)]) {
    await assert.rejects(() => finalizeWebDeployment({ ...options, buildDir }), /tracked source/);
  }
  for (const stagingDir of [options.buildDir, path.dirname(options.buildDir)]) {
    await assert.rejects(() => finalizeWebDeployment({ ...options, stagingDir }), /overlap/);
  }
});

test('CLI and exported API produce identical output from the same build/staging fixture', async (t) => {
  const { options, dir } = await fixture(t);
  const otherBuild = path.join(dir, 'cli-build');
  await cp(options.buildDir, otherBuild, { recursive: true });
  const firebasePath = path.join(dir, 'firebase.json');
  await writeFile(firebasePath, JSON.stringify(options.firebaseConfig));
  await finalizeWebDeployment(options);
  const { stdout, stderr } = await exec(process.execPath, [
    path.join(ROOT, 'scripts/finalize-web-deployment.mjs'),
    '--build', otherBuild, '--staging', options.stagingDir, '--firebase-config', firebasePath,
    '--build-version', options.buildVersion, '--vendor-version', options.vendorVersion,
  ]);
  assert.match(stdout, /No remote changes/);
  assert.equal(stderr, '');
  assert.deepEqual(await snapshot(otherBuild), await snapshot(options.buildDir));
});

test('CLI rejects malformed args and redacts invalid JSON contents', async (t) => {
  const { options, dir } = await fixture(t);
  const script = path.join(ROOT, 'scripts/finalize-web-deployment.mjs');
  for (const args of [[], ['--build'], ['--unexpected', 'value'], ['--build', 'a', '--build', 'b']]) {
    await assert.rejects(() => exec(process.execPath, [script, ...args]), (error) => /required|argument/.test(error.stderr));
  }
  const firebasePath = path.join(dir, 'invalid.json');
  await writeFile(firebasePath, 'secret-value-not-to-print');
  await assert.rejects(() => exec(process.execPath, [script,
    '--build', options.buildDir, '--staging', options.stagingDir, '--firebase-config', firebasePath,
    '--build-version', options.buildVersion, '--vendor-version', options.vendorVersion,
  ]), (error) => /Unable to read Firebase config JSON/.test(error.stderr) && !error.stderr.includes('secret-value-not-to-print'));
});

test('CI uses the shared finalizer while preserving safety gates, local CanvasKit and Pages module output', async () => {
  const source = await readFile(path.join(ROOT, '.github/workflows/deploy-flutter-pwa.yml'), 'utf8');
  assert.match(source, /branches: \[ main, dev \]/);
  assert.match(source, /needs: \[firestore-rules, functions-tests, web-tests\]/);
  assert.match(source, /run: flutter analyze/);
  assert.match(source, /run: flutter test/);
  assert.match(source, /node --test scripts\/\*\.test\.mjs/);
  assert.match(source, /flutter build web --release --base-href "\/" --no-web-resources-cdn/);
  assert.match(source, /node scripts\/finalize-web-deployment\.mjs/);
  assert.match(source, /--build-version "\$\{GITHUB_SHA::8\}-\$\{GITHUB_RUN_NUMBER\}"/);
  assert.match(source, /--vendor-version "flutter-\$\{FLUTTER_VERSION\}"/);
  assert.match(source, /--firebase-config \.local\/firebase-config\.json/);
  assert.match(source, /pages functions build \.local\/deployment\/functions --outdir=build\/web\/_worker\.js/);
  assert.match(source, /--branch=\$\{\{ github.ref_name \}\}/);
  assert.doesNotMatch(source, /sed -i|cp -R \.local\/deployment\/web/);
  assert.ok(source.indexOf('web/version.json') < source.indexOf('flutter build web --release'));
  assert.ok(source.indexOf('node scripts/finalize-web-deployment.mjs') < source.indexOf('pages functions build'));
  assert.ok(source.indexOf('pages functions build') < source.indexOf('pages deploy build/web'));
});
