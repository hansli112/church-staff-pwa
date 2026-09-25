import assert from 'node:assert/strict';
import { cp, lstat, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { buildCoreDeployment } from './installer/build.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CONFIG = JSON.parse(await readFile(path.join(ROOT, 'config/church.example.json'), 'utf8'));
const FIREBASE = { FIREBASE_API_KEY: 'dummy-public-web-key', FIREBASE_AUTH_DOMAIN: 'new-church-example.firebaseapp.com', FIREBASE_PROJECT_ID: 'new-church-example', FIREBASE_MESSAGING_SENDER_ID: '123456789', FIREBASE_APP_ID: '1:123456789:web:offline' };

async function fixture(t, { incomplete = false, workerMissing = false } = {}) {
  const runDir = await mkdtemp(path.join(os.tmpdir(), 'installer-build-test-'));
  t.after(() => rm(runDir, { recursive: true, force: true }));
  const checkpoint = { resources: {}, intents: {} };
  const context = { runDir, plan: { runId: 'run-example-1234', projectId: 'new-church-example', createdAt: '2026-09-24T00:00:00Z', churchConfig: structuredClone(CONFIG) }, checkpoint, transient: { firebaseConfig: FIREBASE }, events: [], emit(event) { context.events.push(event); }, save: async (patch) => {
    Object.assign(checkpoint.resources, patch.resources); Object.assign(checkpoint.intents, patch.intents);
  } };
  const calls = [];
  async function command(executable, args, options) {
    calls.push({ executable, args, options });
    if (args[0] === '--version') return { exitCode: 0, stdout: executable === 'test-flutter' ? '{"frameworkVersion":"3.41.0"}' : '4.138.0' };
    if (args[0] === 'build') {
      const output = args[args.indexOf('--output') + 1];
      assert.equal(output, path.join(runDir, 'web-build'));
      if (incomplete) return { exitCode: 0, stdout: 'Looks successful but missing files' };
      await cp(path.join(options.cwd, 'web'), output, { recursive: true });
      for (const name of ['main.dart.js', 'flutter_bootstrap.js', 'canvaskit/canvaskit.wasm']) {
        await mkdir(path.dirname(path.join(output, name)), { recursive: true });
        await writeFile(path.join(output, name), 'mock build content');
      }
    }
    if (args[0] === 'pages' && !workerMissing) {
      const output = args.find((arg) => arg.startsWith('--outdir=')).slice('--outdir='.length);
      await mkdir(output, { recursive: true });
      await writeFile(path.join(output, 'index.js'), 'export default {fetch(){return new Response("offline")}}');
    }
    return { exitCode: 0, stdout: '' };
  }
  return { runDir, context, calls, command, options: { command, flutter: 'test-flutter', wrangler: 'test-wrangler', environment: { PATH: '/safe/bin', CLOUDFLARE_API_TOKEN: 'production-token', FIREBASE_API_KEY: 'wrong-project', GOOGLE_APPLICATION_CREDENTIALS: '/secret.json', NODE_OPTIONS: '--require=/bad.js', WRANGLER_AUTH_URL: 'https://bad.example' } } };
}

test('core build isolates source, uses per-run output and shares staging/finalizer with complete production config', async (t) => {
  const { runDir, context, calls, options } = await fixture(t);
  const originalIndex = await readFile(path.join(ROOT, 'web/index.html'), 'utf8');
  const result = await buildCoreDeployment(context, options);
  assert.equal(result.buildDir, path.join(runDir, 'web-build'));
  assert.equal(result.deploymentDir, path.join(runDir, 'deployment'));
  assert.equal(context.transient.buildVersion, result.buildVersion);
  assert.equal((await lstat(path.join(runDir, 'firebase-config.json'))).mode & 0o777, 0o600);
  assert.equal(await readFile(path.join(ROOT, 'web/index.html'), 'utf8'), originalIndex);
  assert.deepEqual(JSON.parse(await readFile(path.join(runDir, 'deployment/church.json'), 'utf8')), CONFIG);
  const build = calls.find(({ args }) => args[0] === 'build');
  assert.ok(build.args.includes('--release'));
  assert.ok(build.args.includes('--no-web-resources-cdn'));
  assert.ok(build.args.includes(`--dart-define-from-file=${path.join(runDir, 'deployment/dart-defines.json')}`));
  assert.ok(build.args.includes(`--dart-define-from-file=${path.join(runDir, 'firebase-config.json')}`));
  assert.ok(!build.args.some((arg) => arg.includes('production-token') || arg.includes('dummy-public-web-key')));
  assert.equal(build.options.cwd, path.join(runDir, 'build-workspace'));
  const worker = calls.find(({ args }) => args[0] === 'pages');
  assert.deepEqual(worker.args, ['pages', 'functions', 'build', path.join(runDir, 'deployment/functions'), `--outdir=${path.join(runDir, 'web-build/_worker.js')}`]);
  for (const { options: child } of calls) {
    for (const key of ['CLOUDFLARE_API_TOKEN', 'FIREBASE_API_KEY', 'GOOGLE_APPLICATION_CREDENTIALS', 'NODE_OPTIONS', 'WRANGLER_AUTH_URL']) assert.equal(child.env[key], undefined);
    assert.ok(child.env.HOME.startsWith(runDir + path.sep));
  }
  const cache = await readFile(path.join(result.buildDir, 'cache_sw.js'), 'utf8');
  assert.ok(cache.includes(result.buildVersion));
  assert.ok(cache.includes('flutter-3.41.0'));
  assert.ok(!cache.includes('__BUILD_VERSION__'));
  const sw = await readFile(path.join(result.buildDir, 'firebase-messaging-sw.js'), 'utf8');
  assert.ok(sw.includes('dummy-public-web-key'));
  const publicFiles = await readdir(result.buildDir);
  for (const name of ['firebase-config.json', 'church.json', '.installer-build', 'firestore.rules']) assert.ok(!publicFiles.includes(name));
  assert.equal(JSON.parse(await readFile(path.join(result.buildDir, 'version.json'))).branch, 'main');
  assert.ok(!JSON.stringify(context.checkpoint).includes('dummy-public-web-key'));
});

test('repeat of this run has stable build version and other runs cannot overwrite its workspace', async (t) => {
  const { context, options } = await fixture(t);
  const first = await buildCoreDeployment(context, options);
  const second = await buildCoreDeployment(context, options);
  assert.equal(first.buildVersion, second.buildVersion);
  context.plan.runId = 'different-run-1234';
  await assert.rejects(buildCoreDeployment(context, options), /禁止覆寫/);
});

test('incomplete Flutter output and missing Worker are rejected despite successful exit status', async (t) => {
  for (const variant of [{ incomplete: true }, { workerMissing: true }]) {
    const { context, options } = await fixture(t, variant);
    await assert.rejects(buildCoreDeployment(context, options), /不完整/);
    assert.equal(context.transient.buildDir, undefined);
  }
});

test('failed build is safely retryable with the same private workspace', async (t) => {
  const { context, options, command } = await fixture(t);
  options.command = async (executable, args, opts) => args[0] === 'build' ? { exitCode: 1, stdout: 'private-token' } : command(executable, args, opts);
  await assert.rejects(buildCoreDeployment(context, options), (error) => !error.message.includes('private-token'));
  options.command = command;
  assert.ok((await buildCoreDeployment(context, options)).buildVersion);
});

test('core-only, Firebase project match and pinned tool versions fail before building', async (t) => {
  const { context, calls, options, command } = await fixture(t);
  context.plan.churchConfig.features.calendar = true;
  await assert.rejects(buildCoreDeployment(context, options), /核心功能/);
  context.plan.churchConfig.features.calendar = false;
  context.transient.firebaseConfig = { ...FIREBASE, FIREBASE_PROJECT_ID: 'not-this-run' };
  await assert.rejects(buildCoreDeployment(context, options), /不屬於本次/);
  assert.equal(calls.length, 0);
  context.transient.firebaseConfig = FIREBASE;
  // Google returns the Firebase JS SDK shape; build must accept it unchanged.
  context.transient.firebaseConfig = { apiKey: FIREBASE.FIREBASE_API_KEY, authDomain: FIREBASE.FIREBASE_AUTH_DOMAIN, projectId: FIREBASE.FIREBASE_PROJECT_ID, messagingSenderId: FIREBASE.FIREBASE_MESSAGING_SENDER_ID, appId: FIREBASE.FIREBASE_APP_ID };
  options.command = async (exe, args, opts) => args.includes('--machine') ? { exitCode: 0, stdout: '{"frameworkVersion":"3.99.0"}' } : command(exe, args, opts);
  await assert.rejects(buildCoreDeployment(context, options), /Flutter 3.41.0/);
});

test('Cloud Shell launcher pins official tools, checks hashes and does not log in or deploy on startup', async () => {
  const script = await readFile(path.join(ROOT, 'scripts/start-installation.sh'), 'utf8');
  assert.match(script, /NODE_VERSION=22\.22\.0/);
  assert.match(script, /FLUTTER_VERSION=3\.41\.0/);
  assert.match(script, /WRANGLER_VERSION=4\.138\.0/);
  assert.match(script, /sha256sum --check --status/);
  assert.match(script, /sha512sum --check --status/);
  assert.match(script, /npm install[^\n]*--ignore-scripts/);
  assert.match(script, /INSTALLER_BUILD_ROOT="\$TOOLS\/builds"/);
  assert.match(script, /install-core\.mjs" --cloud-shell/);
  assert.doesNotMatch(script, /gcloud\s+(auth|projects)|wrangler\s+(login|pages)|\.local\/.*(?:env|credential)|curl[^\n]*\|\s*(bash|sh)/);
});
