#!/usr/bin/env node
// Shared by CI and the installer after Flutter builds, before Pages deployment.
// Only staged web assets are public; rules, defines and server credentials stay out.
import { lstat, mkdir, readFile, readdir, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const FIREBASE_KEYS = [
  'FIREBASE_API_KEY', 'FIREBASE_AUTH_DOMAIN', 'FIREBASE_PROJECT_ID',
  'FIREBASE_STORAGE_BUCKET', 'FIREBASE_MESSAGING_SENDER_ID',
  'FIREBASE_APP_ID', 'FIREBASE_MEASUREMENT_ID',
];
export const OPTIONAL_FIREBASE_KEYS = new Set(['FIREBASE_STORAGE_BUCKET', 'FIREBASE_MEASUREMENT_ID']);

function validateVersion(value, name) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/.test(value)) {
    throw new Error(`${name} must be a 1-200 character cache version using letters, digits, dots, underscores or hyphens`);
  }
}

function firebaseValues(config) {
  if (!config || typeof config !== 'object' || Array.isArray(config)) throw new Error('firebaseConfig must be a dart-define JSON object');
  return Object.fromEntries(FIREBASE_KEYS.map((key) => {
    const value = config[key] ?? (OPTIONAL_FIREBASE_KEYS.has(key) ? '' : undefined);
    if (typeof value !== 'string' || (!OPTIONAL_FIREBASE_KEYS.has(key) && !value.trim())) throw new Error(`${key} is required and must be a non-empty string`);
    return [key, value];
  }));
}

function renderCache(source, buildVersion, vendorVersion) {
  for (const [constant, placeholder, value] of [
    ['CACHE_VERSION', '__BUILD_VERSION__', buildVersion],
    ['VENDOR_VERSION', '__VENDOR_VERSION__', vendorVersion],
  ]) {
    const declaration = new RegExp(`^const ${constant} = (['"])${placeholder}\\1;$`, 'gm');
    if ([...source.matchAll(declaration)].length !== 1) throw new Error(`${placeholder} declaration missing or duplicated in cache_sw.js; use a fresh Flutter build`);
    source = source.replaceAll(placeholder, value);
  }
  if (/__(?:BUILD|VENDOR)_[A-Z_]+__/.test(source)) throw new Error('Cache placeholders remain in cache_sw.js');
  return source;
}

function renderFirebase(source, config) {
  for (const [key, value] of Object.entries(config)) {
    const placeholder = `__${key}__`;
    const literal = new RegExp(`(['"])${placeholder}\\1`, 'g');
    if ([...source.matchAll(literal)].length !== 1) throw new Error(`${placeholder} literal missing or duplicated in firebase-messaging-sw.js`);
    // Replace the whole literal: sed-style replacement corrupts quotes, slashes,
    // dollar signs and newlines. A Firebase value must never become JavaScript.
    source = source.replace(literal, () => JSON.stringify(value));
  }
  if (/__FIREBASE_[A-Z_]+__/.test(source)) throw new Error('Firebase placeholders remain in firebase-messaging-sw.js');
  return source;
}

const contains = (parent, child) => child === parent || child.startsWith(`${parent}${path.sep}`);

async function directory(dir, name) {
  if (!dir || typeof dir !== 'string') throw new Error(`${name} is required`);
  if (!(await lstat(dir)).isDirectory()) throw new Error(`${name} must be a directory without symbolic links`);
  return realpath(dir);
}

async function stagedFiles(dir, prefix = '') {
  const files = new Map();
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const relative = path.join(prefix, entry.name);
    const source = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      for (const [name, bytes] of await stagedFiles(source, relative)) files.set(name, bytes);
    } else if (entry.isFile()) {
      files.set(relative, await readFile(source));
    } else {
      throw new Error('staging/web must contain only regular files and directories, without symbolic links');
    }
  }
  return files;
}

async function checkTarget(build, relative) {
  const parts = relative.split(path.sep);
  for (let i = 1; i <= parts.length; i += 1) {
    const target = path.join(build, ...parts.slice(0, i));
    const stat = await lstat(target).catch((error) => {
      if (error.code === 'ENOENT') return null;
      throw error;
    });
    if (!stat) continue;
    if (i < parts.length ? !stat.isDirectory() : !stat.isFile() || stat.nlink !== 1) {
      throw new Error('build targets must be regular files/directories without symbolic or hard links');
    }
  }
}

export async function finalizeWebDeployment({ buildDir, stagingDir, firebaseConfig, buildVersion, vendorVersion }) {
  validateVersion(buildVersion, 'buildVersion');
  validateVersion(vendorVersion, 'vendorVersion');
  const values = firebaseValues(firebaseConfig);
  const build = await directory(buildDir, 'buildDir');
  const staging = await directory(stagingDir, 'stagingDir');
  const sourceRoot = await realpath(ROOT);
  if (contains(build, sourceRoot) || ['web', 'lib', 'worker', 'functions', 'scripts', 'config', 'test', '.github'].some((dir) => contains(path.join(sourceRoot, dir), build))) {
    throw new Error('buildDir must not overwrite tracked source directories');
  }
  if (contains(build, staging) || contains(staging, build)) throw new Error('buildDir and stagingDir must not overlap');

  const web = await directory(path.join(staging, 'web'), 'staging/web');
  const files = await stagedFiles(web);
  for (const name of ['index.html', 'manifest.json', 'firebase-messaging-sw.js']) {
    if (!files.has(name)) throw new Error(`staging/web/${name} is required; run prepare-deployment.mjs first`);
  }
  await checkTarget(build, 'cache_sw.js');
  const cache = renderCache(await readFile(path.join(build, 'cache_sw.js'), 'utf8'), buildVersion, vendorVersion);
  const messaging = renderFirebase(files.get('firebase-messaging-sw.js').toString('utf8'), values);
  files.set('cache_sw.js', Buffer.from(cache));
  files.set('firebase-messaging-sw.js', Buffer.from(messaging));

  // Preflight every input and destination before altering the build. Keep the
  // Flutter bundle, local CanvasKit, version.json and _worker.js/ untouched.
  for (const name of files.keys()) await checkTarget(build, name);
  for (const [name, bytes] of files) {
    const target = path.join(build, name);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, bytes);
  }
  return { buildDir: build, buildVersion, vendorVersion };
}

async function main() {
  const args = process.argv.slice(2);
  const flags = new Map([
    ['--build', 'buildDir'], ['--staging', 'stagingDir'], ['--firebase-config', 'firebaseConfigPath'],
    ['--build-version', 'buildVersion'], ['--vendor-version', 'vendorVersion'],
  ]);
  const options = {};
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === '--help') {
      console.log('Usage: node scripts/finalize-web-deployment.mjs --build DIR --staging DIR --firebase-config FILE --build-version VERSION --vendor-version VERSION\nRun after flutter build web --no-web-resources-cdn. Staging is the prepare-deployment.mjs output root. Firebase JSON uses FIREBASE_* dart-define keys. No builds, downloads or deployments are performed.');
      return;
    }
    const key = flags.get(args[i]);
    if (!key || key in options || !args[i + 1] || args[i + 1].startsWith('--')) throw new Error('Invalid or duplicate argument; use --help');
    options[key] = args[++i];
  }
  for (const [flag, key] of flags) if (!options[key]) throw new Error(`${flag} is required`);
  try {
    options.firebaseConfig = JSON.parse(await readFile(options.firebaseConfigPath, 'utf8'));
  } catch {
    throw new Error('Unable to read Firebase config JSON; use a readable file containing a JSON object');
  }
  const result = await finalizeWebDeployment(options);
  console.log(`Finalized web deployment in ${result.buildDir}. No remote changes made.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
