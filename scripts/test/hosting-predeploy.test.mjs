import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');

function deployment(t) {
  // The public predeploy CLI finds its build relative to its own script.
  // Copy only deployment packaging inputs: never write to the real build,
  // read app/config, invoke Flutter/Firebase, or install dependencies.
  const dir = mkdtempSync(join(tmpdir(), 'martha-hosting-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'scripts'));
  for (const script of ['hosting-predeploy.sh', 'fingerprint-fonts.mjs', 'fingerprint-web.mjs', 'build-site.mjs']) {
    copyFileSync(join(root, 'scripts', script), join(dir, 'scripts', script));
  }
  assert.ok(existsSync(join(root, 'landing/node_modules/marked')), 'use existing website dependencies; do not install in tests');
  cpSync(join(root, 'landing'), join(dir, 'landing'), { recursive: true });
  const web = join(dir, 'app/build/web');
  mkdirSync(join(web, 'assets/fonts'), { recursive: true });
  writeFileSync(join(web, 'index.html'), '<base href="/nested/"><script src="flutter_bootstrap.js" async></script>');
  writeFileSync(join(web, 'main.dart.js'), 'console.log("martha");\n');
  writeFileSync(join(web, 'flutter_bootstrap.js'), '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]};\n_flutter.loader.load({});');
  writeFileSync(join(web, 'assets/fonts/Icons.otf'), 'icons A');
  writeFileSync(join(web, 'assets/FontManifest.json'), '[{"family":"Icons","fonts":[{"asset":"fonts/Icons.otf"}]}]');
  writeFileSync(join(web, 'flutter_service_worker.js'), 'self.addEventListener("activate", () => self.registration.unregister());');
  return { dir, web };
}

function predeploy(dir) {
  return execFileSync('bash', [join(dir, 'scripts/hosting-predeploy.sh')], {
    encoding: 'utf8',
    env: { ...process.env, GCLOUD_PROJECT: 'test-martha-dev', SUPPORT_PAYMENTS: 'off' },
  });
}

test('Hosting CLI packages stable HTML/bootstrap with versioned JS and fonts, including on rerun', (t) => {
  const { dir, web } = deployment(t);
  const html = readFileSync(join(web, 'index.html'), 'utf8');
  const worker = readFileSync(join(web, 'flutter_service_worker.js'), 'utf8');
  predeploy(dir);
  assert.match(readFileSync(join(web, 'flutter_bootstrap.js'), 'utf8'), /"mainJsPath":"main\.dart\.d3e18322f0\.js"/);
  assert.equal(readFileSync(join(web, 'main.dart.d3e18322f0.js'), 'utf8'), 'console.log("martha");\n');
  assert.equal(readFileSync(join(web, 'app.html'), 'utf8'), html);
  assert.doesNotMatch(readFileSync(join(web, 'index.html'), 'utf8'), /flutter_bootstrap/);
  assert.equal(readFileSync(join(web, 'flutter_service_worker.js'), 'utf8'), worker);
  assert.match(readFileSync(join(web, 'assets/FontManifest.json'), 'utf8'), /Icons\.a2f6674ce7\.otf/);
  assert.equal(readFileSync(join(dir, '.firebase/web-assets/test-martha-dev/assets/fonts/Icons.a2f6674ce7.otf'), 'utf8'), 'icons A');
  const bootstrap = readFileSync(join(web, 'flutter_bootstrap.js'), 'utf8');
  predeploy(dir);
  assert.equal(readFileSync(join(web, 'app.html'), 'utf8'), html);
  assert.equal(readFileSync(join(web, 'flutter_bootstrap.js'), 'utf8'), bootstrap);
});

test('Hosting CLI without a Firebase project fails before altering the build', (t) => {
  const { dir, web } = deployment(t);
  const env = { ...process.env };
  delete env.GCLOUD_PROJECT;
  const result = spawnSync('bash', [join(dir, 'scripts/hosting-predeploy.sh')], { encoding: 'utf8', env });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Firebase project id is required/);
  assert.equal(existsSync(join(web, 'index.html')), true);
  assert.equal(existsSync(join(web, 'app.html')), false);
  assert.equal(existsSync(join(web, 'assets/fonts/Icons.otf')), true);
  assert.equal(existsSync(join(web, 'main.dart.d3e18322f0.js')), false);
  assert.equal(existsSync(join(dir, '.firebase/web-assets')), false);
});

test('font processing must succeed before any JS hash is published or archived', (t) => {
  const { dir, web } = deployment(t);
  writeFileSync(join(web, 'assets/FontManifest.json'), '{malformed');
  const result = spawnSync('bash', [join(dir, 'scripts/hosting-predeploy.sh')], {
    encoding: 'utf8',
    env: { ...process.env, GCLOUD_PROJECT: 'test-martha-dev' },
  });
  assert.notEqual(result.status, 0);
  assert.equal(existsSync(join(web, 'main.dart.d3e18322f0.js')), false);
  assert.equal(existsSync(join(dir, '.firebase/web-assets')), false);
  assert.match(readFileSync(join(web, 'flutter_bootstrap.js'), 'utf8'), /"mainJsPath":"main\.dart\.js"/);
});

test('Hosting CLI rejects wasm before moving HTML or rewriting fonts', (t) => {
  const { dir, web } = deployment(t);
  const bootstrap = '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2wasm","renderer":"skwasm","mainWasmPath":"main.dart.wasm","jsSupportRuntimePath":"main.dart.mjs"},{"compileTarget":"dart2js","mainJsPath":"main.dart.js"},{}]}; _flutter.loader.load({});';
  writeFileSync(join(web, 'flutter_bootstrap.js'), bootstrap);
  const manifest = readFileSync(join(web, 'assets/FontManifest.json'), 'utf8');
  const result = spawnSync('bash', [join(dir, 'scripts/hosting-predeploy.sh')], {
    encoding: 'utf8',
    env: { ...process.env, GCLOUD_PROJECT: 'test-martha-dev' },
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /dart2wasm builds are not supported/);
  assert.equal(existsSync(join(web, 'index.html')), true);
  assert.equal(existsSync(join(web, 'app.html')), false);
  assert.equal(readFileSync(join(web, 'assets/FontManifest.json'), 'utf8'), manifest);
  assert.equal(readFileSync(join(web, 'assets/fonts/Icons.otf'), 'utf8'), 'icons A');
  assert.equal(readFileSync(join(web, 'flutter_bootstrap.js'), 'utf8'), bootstrap);
  assert.equal(existsSync(join(dir, '.firebase/web-assets')), false);
});
