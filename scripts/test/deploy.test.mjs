import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');

function deployment(t) {
  const dir = mkdtempSync(join(tmpdir(), 'martha-deploy-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  for (const path of ['scripts', 'app/config', 'bin']) mkdirSync(join(dir, path), { recursive: true });
  for (const script of ['deploy.sh', 'hosting-predeploy.sh', 'fingerprint-fonts.mjs', 'fingerprint-web.mjs', 'build-site.mjs']) {
    copyFileSync(join(root, 'scripts', script), join(dir, 'scripts', script));
  }
  assert.ok(existsSync(join(root, 'landing/node_modules/marked')), 'use existing website dependencies; do not install in tests');
  cpSync(join(root, 'landing'), join(dir, 'landing'), { recursive: true });
  writeFileSync(join(dir, 'app/config/dev.json'), '{"FIREBASE_PROJECT_ID":"test-dev"}');
  writeFileSync(join(dir, 'app/config/prod.json'), '{"FIREBASE_PROJECT_ID":"test-prod"}');
  // Only external commands are substituted. The real deploy and predeploy
  // CLIs run on scratch artifacts, with no Flutter build or Firebase access.
  writeFileSync(join(dir, 'bin/flutter'), `#!/usr/bin/env bash
set -euo pipefail
[ "\${FAKE_FLUTTER_FAIL:-}" != 1 ] || exit 1
mkdir -p build/web/assets/fonts
printf '%s' '<base href="/"><script src="flutter_bootstrap.js" async></script>' > build/web/index.html
printf '%s' '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","mainJsPath":"main.dart.js"},{}]}; _flutter.loader.load({});' > build/web/flutter_bootstrap.js
printf '%s\\n' "$FAKE_MAIN" > build/web/main.dart.js
printf '%s' 'icons A' > build/web/assets/fonts/Icons.otf
printf '%s' '[{"family":"Icons","fonts":[{"asset":"fonts/Icons.otf"}]}]' > build/web/assets/FontManifest.json
`, { mode: 0o755 });
  writeFileSync(join(dir, 'scripts/firebase.sh'), `#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
GCLOUD_PROJECT="$1" bash "$root/scripts/hosting-predeploy.sh"
`, { mode: 0o755 });
  // deploy.sh retries failed Firebase attempts; skip its wait in this isolated
  // harness, never invoke the real sleep or any deployment CLI.
  writeFileSync(join(dir, 'bin/sleep'), '#!/usr/bin/env bash\nexit 0\n', { mode: 0o755 });
  return dir;
}

function deploy(dir, environment, main, extra = {}) {
  return spawnSync('bash', [join(dir, 'scripts/deploy.sh'), environment, '--only', 'hosting'], {
    encoding: 'utf8',
    env: { ...process.env, PATH: `${join(dir, 'bin')}:${process.env.PATH}`, FAKE_MAIN: main, SUPPORT_PAYMENTS: 'off', ...extra },
  });
}

test('deploy CLI builds a clean output on dev-to-prod switches without deleting project archives', (t) => {
  const dir = deployment(t);
  const dev = deploy(dir, 'dev', 'console.log("martha");');
  assert.equal(dev.status, 0, dev.stderr);
  const prod = deploy(dir, 'prod', 'console.log("changed");');
  assert.equal(prod.status, 0, prod.stderr);
  const archive = join(dir, '.firebase/web-assets');
  assert.equal(readFileSync(join(archive, 'test-dev/main.dart.d3e18322f0.js'), 'utf8'), 'console.log("martha");\n');
  assert.equal(readFileSync(join(archive, 'test-prod/main.dart.c8606d046a.js'), 'utf8'), 'console.log("changed");\n');
  assert.equal(existsSync(join(archive, 'test-prod/main.dart.d3e18322f0.js')), false);
  assert.equal(existsSync(join(dir, 'app/build/web/main.dart.d3e18322f0.js')), false);
  assert.equal(readFileSync(join(dir, 'app/build/web/.web-assets-project'), 'utf8'), 'test-prod');
  assert.deepEqual(readdirSync(archive).sort(), ['test-dev', 'test-prod']);
});

test('failed build keeps the last prepared project assets available for the next attempt', (t) => {
  const dir = deployment(t);
  const initial = deploy(dir, 'dev', 'console.log("martha");');
  assert.equal(initial.status, 0, initial.stderr);
  const failed = deploy(dir, 'dev', 'console.log("changed");', { FAKE_FLUTTER_FAIL: '1' });
  assert.equal(failed.status, 1);
  const history = join(dir, '.firebase/web-assets/test-dev');
  assert.equal(readFileSync(join(history, 'main.dart.d3e18322f0.js'), 'utf8'), 'console.log("martha");\n');
  assert.equal(readFileSync(join(history, 'assets/fonts/Icons.a2f6674ce7.otf'), 'utf8'), 'icons A');
  assert.equal(existsSync(join(history, 'main.dart.c8606d046a.js')), false);
  const retry = deploy(dir, 'dev', 'console.log("changed");');
  assert.equal(retry.status, 0, retry.stderr);
  assert.equal(readFileSync(join(dir, 'app/build/web/main.dart.d3e18322f0.js'), 'utf8'), 'console.log("martha");\n');
  assert.equal(readFileSync(join(dir, 'app/build/web/main.dart.c8606d046a.js'), 'utf8'), 'console.log("changed");\n');
});
