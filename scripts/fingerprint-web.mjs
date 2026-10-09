// Names Flutter's compiled JavaScript and asset trees after their contents.
// The bootstrap stays at its stable, no-cache URL; its dart2js path and
// loader assetBase bind code to the same release's manifests/fonts/assets.
// Keep main.dart.js and stable assets too for the loader's legacy fallback.
//
//   node scripts/fingerprint-web.mjs app/build/web
//     --archive .firebase/web-assets --project <Firebase project id>
//   node scripts/fingerprint-web.mjs app/build/web --check-build
//
// --check-build only validates build metadata; real wasm builds are rejected
// before any output changes. This is not a wasm rollout compatibility layer.
//
// The project archive is additive: failed deploys must never rotate away
// published assets. Preserve/transfer it when changing deployment machines.
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { Script } from 'node:vm';

function assetTree(dir, strict = false) {
  if (!lstatSync(dir).isDirectory()) throw new Error(`unsupported asset directory: ${dir}`);
  const files = [];
  function collect(here, prefix = '') {
    for (const entry of readdirSync(here, { withFileTypes: true })) {
      const path = `${prefix}${entry.name}`;
      if (entry.name.startsWith('.') || entry.name.includes('\\') || /\.(?:[cm]?js|map)$/i.test(path)) {
        throw new Error(`unsupported asset path: ${path}`);
      }
      if (entry.isDirectory()) collect(join(here, entry.name), `${path}/`);
      else if (entry.isFile()) files.push({ path, bytes: readFileSync(join(here, entry.name)) });
      else throw new Error(`unsupported asset path: ${path}`);
    }
  }
  collect(dir);
  let manifest;
  try {
    manifest = JSON.parse(files.find((file) => file.path === 'FontManifest.json')?.bytes.toString());
    if (!Array.isArray(manifest) || manifest.some((family) => !Array.isArray(family?.fonts))) throw new Error();
  } catch {
    throw new Error('invalid assets/FontManifest.json');
  }
  const fonts = new Set(manifest.flatMap((family) => family.fonts.map((font) => font.asset)));
  for (const path of fonts) {
    if (typeof path !== 'string' || !files.some((file) => file.path === path)) throw new Error(`missing font asset: ${path}`);
  }
  // Historical loose fonts stay at their old URLs for a tab that already
  // fetched the stable manifest. They are not part of this release's tree.
  const current = files.filter((file) => !/\.(?:otf|ttf)$/i.test(file.path) || fonts.has(file.path));
  if (strict && current.length !== files.length) throw new Error('unexpected font in immutable asset bundle');
  current.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  const hash = createHash('sha256');
  for (const file of current) hash.update(`${file.path}\0${file.bytes.length}\0`).update(file.bytes);
  return { hash: hash.digest('hex').slice(0, 10), files: current };
}

function sameTree(a, b) {
  return a.hash === b.hash && a.files.length === b.files.length && a.files.every((file, i) => file.path === b.files[i].path && file.bytes.equals(b.files[i].bytes));
}

function publishBundle(tree, target) {
  if (existsSync(target)) {
    if (!lstatSync(target).isDirectory()) throw new Error(`unsupported asset bundle path: ${target}`);
    const previous = assetTree(join(target, 'assets'), true);
    if (previous.hash !== tree.hash) throw new Error(`asset bundle hash mismatch: ${target}`);
    if (!sameTree(previous, tree)) throw new Error(`immutable asset bundle collision: ${target}`);
    return;
  }
  mkdirSync(dirname(target), { recursive: true });
  const pending = mkdtempSync(join(dirname(target), '.pending-'));
  try {
    for (const file of tree.files) {
      const path = join(pending, 'assets', file.path);
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, file.bytes);
    }
    if (!sameTree(assetTree(join(pending, 'assets'), true), tree)) throw new Error('incomplete asset bundle copy');
    renameSync(pending, target);
  } finally {
    rmSync(pending, { recursive: true, force: true });
  }
}

function bindAssets(bootstrap, base) {
  const managed = /\/\*martha-assets\*\/\s*"asset-bundles\/[0-9a-f]{10}\/"/g;
  const previous = [...bootstrap.matchAll(managed)];
  if (previous.length > 1) throw new Error('invalid managed assetBase in flutter_bootstrap.js');
  if (previous.length) return bootstrap.replace(managed, () => `/*martha-assets*/ ${JSON.stringify(base)}`);
  const calls = [...bootstrap.matchAll(/_flutter\.loader\.load\s*\(/g)];
  if (calls.length !== 1) throw new Error('expected one Flutter loader.load call in flutter_bootstrap.js');
  const start = calls[0].index + calls[0][0].length;
  let depth = 1;
  let quote;
  let end;
  for (let i = start; i < bootstrap.length; i++) {
    const char = bootstrap[i];
    if (quote) {
      if (char === '\\') i++;
      else if (char === quote) quote = undefined;
    } else if (char === '"' || char === "'" || char === '`') quote = char;
    else if (bootstrap.startsWith('//', i)) {
      i = bootstrap.indexOf('\n', i + 2);
      if (i < 0) break;
    } else if (bootstrap.startsWith('/*', i)) {
      i = bootstrap.indexOf('*/', i + 2);
      if (i < 0) break;
      i++;
    } else if (char === '(') depth++;
    else if (char === ')' && --depth === 0) { end = i; break; }
  }
  if (end === undefined) throw new Error('malformed Flutter loader.load call');
  const options = bootstrap.slice(start, end);
  const bound = `((options = {}) => ({ ...options, config: { ...options.config, assetBase: /*martha-assets*/ ${JSON.stringify(base)} } }))(${options})`;
  return bootstrap.slice(0, start) + bound + bootstrap.slice(end);
}

const immutable = /^(?:main\.dart(?:\.js_\d+\.part)?\.[0-9a-f]{10}\.js|assets\/(?:[A-Za-z0-9_-][A-Za-z0-9_.-]*\/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*\.[0-9a-f]{10}\.(?:otf|ttf))$/;
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex').slice(0, 10);

function immutableFiles(dir, prefix = '') {
  if (!existsSync(dir)) return [];
  const files = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = `${prefix}${entry.name}`;
    if (entry.isDirectory()) files.push(...immutableFiles(join(dir, entry.name), `${path}/`));
    else if (entry.isFile() && immutable.test(path)) {
      const bytes = readFileSync(join(dir, entry.name));
      const hash = /\.([0-9a-f]{10})\.(?:js|otf|ttf)$/.exec(path)[1];
      if (hash !== digest(bytes)) throw new Error(`content hash mismatch: ${path}`);
      files.push(path);
    }
  }
  return files;
}

function publish(source, target) {
  const bytes = readFileSync(source);
  const hash = /\.([0-9a-f]{10})\.(?:js|otf|ttf)$/.exec(target)[1];
  if (digest(bytes) !== hash) throw new Error(`content hash mismatch: ${source}`);
  if (existsSync(target)) {
    const previous = readFileSync(target);
    if (previous.equals(bytes)) return;
    // A valid immutable file must never be overwritten. A truncated copy
    // from the former direct-copy implementation can be repaired safely.
    if (digest(previous) === hash) throw new Error(`immutable asset collision: ${target}`);
  }
  mkdirSync(dirname(target), { recursive: true });
  const pending = mkdtempSync(join(dirname(target), '.pending-'));
  const temporary = join(pending, 'asset');
  try {
    copyFileSync(source, temporary);
    if (!readFileSync(temporary).equals(bytes)) throw new Error(`incomplete archive copy: ${source}`);
    renameSync(temporary, target);
  } finally {
    rmSync(pending, { recursive: true, force: true });
  }
}

function retain(web, archive, project, tree) {
  const history = join(archive, project);
  publishBundle(tree, join(history, 'asset-bundles', tree.hash));
  for (const path of immutableFiles(web)) publish(join(web, path), join(history, path));
  const bundles = join(history, 'asset-bundles');
  for (const entry of readdirSync(bundles, { withFileTypes: true })) {
    if (!/^[0-9a-f]{10}$/.test(entry.name)) continue;
    if (!entry.isDirectory()) throw new Error(`unsupported asset bundle path: ${entry.name}`);
    const previous = assetTree(join(bundles, entry.name, 'assets'), true);
    if (previous.hash !== entry.name) throw new Error(`asset bundle hash mismatch: ${entry.name}`);
    publishBundle(previous, join(web, 'asset-bundles', entry.name));
  }
  for (const path of immutableFiles(history)) publish(join(history, path), join(web, path));
  writeFileSync(join(web, '.web-assets-project'), project);
}

function run() {
  const [web, ...args] = process.argv.slice(2);
  let archive;
  let project;
  const checkBuild = args.length === 1 && args[0] === '--check-build';
  if (args.length === 4 && args[0] === '--archive' && args[2] === '--project') {
    archive = args[1];
    project = args[3];
  } else if (args.length && !checkBuild) throw new Error('usage: fingerprint-web.mjs <web> [--check-build | --archive <dir> --project <id>]');
  if (!web || web.startsWith('--') || (args.length && !checkBuild && (!archive || !project || !/^[a-z][a-z0-9-]{0,62}$/.test(project)))) {
    throw new Error('usage: fingerprint-web.mjs <web> [--check-build | --archive <dir> --project <id>]');
  }
  const marker = join(web, '.web-assets-project');
  if (archive && existsSync(marker) && readFileSync(marker, 'utf8') !== project) {
    throw new Error('web build belongs to another Firebase project; create a fresh build');
  }
  const bootstrapPath = join(web, 'flutter_bootstrap.js');
  const bootstrap = readFileSync(bootstrapPath, 'utf8');
  const assignment = /_flutter\.buildConfig\s*=\s*(\{[\s\S]*?\})\s*;/;
  const match = assignment.exec(bootstrap);
  let config;
  try {
    config = JSON.parse(match?.[1]);
  } catch {
    throw new Error('invalid Flutter build configuration in flutter_bootstrap.js');
  }
  if (!Array.isArray(config.builds)) throw new Error('invalid Flutter build configuration: expected builds');
  // This rollout versions dart2js only. Pinning assets while leaving a real
  // wasm/mjs entry point unversioned would mix releases on an older bootstrap.
  // Reject it before changing any generated output; empty fallbacks stay.
  if (config.builds.some((build) => build?.compileTarget === 'dart2wasm')) {
    throw new Error('dart2wasm builds are not supported by this dart2js-only fingerprinting rollout');
  }
  if (!config.builds.some((build) => build?.compileTarget === 'dart2js')) {
    throw new Error('invalid Flutter build configuration: expected a dart2js build');
  }
  const jsBuilds = config.builds.filter((build) => build?.compileTarget === 'dart2js');
  if (jsBuilds.some((build) => typeof build.mainJsPath !== 'string' || !/^main\.dart(?:\.[0-9a-f]{10})?\.js$/.test(build.mainJsPath))) {
    throw new Error('invalid Flutter build configuration: unsupported mainJsPath');
  }
  if (checkBuild) return;
  const mainPath = join(web, 'main.dart.js');
  let main = readFileSync(mainPath, 'utf8');
  const parts = new Set([
    ...readdirSync(web).filter((file) => /^main\.dart\.js_\d+\.part\.js$/.test(file)),
    ...Array.from(main.matchAll(/main\.dart\.js_\d+\.part\.js/g), (match) => match[0]),
  ]);
  // Read every required chunk before writing anything, so missing chunks
  // cannot leave a half-rewritten deployment behind.
  const chunks = [...parts].map((part) => {
    const bytes = readFileSync(join(web, part));
    return { part, bytes, named: part.replace(/\.js$/, `.${digest(bytes)}.js`) };
  });
  const tree = assetTree(join(web, 'assets'));
  const base = `asset-bundles/${tree.hash}/`;
  const boundBootstrap = bindAssets(bootstrap, base);
  try { new Script(boundBootstrap); } catch { throw new Error('malformed flutter_bootstrap.js'); }
  publishBundle(tree, join(web, 'asset-bundles', tree.hash));
  for (const { part, bytes, named } of chunks) {
    writeFileSync(join(web, named), bytes);
    main = main.replaceAll(part, named);
  }
  const hash = digest(main);
  const named = `main.dart.${hash}.js`;
  writeFileSync(join(web, named), main);
  writeFileSync(mainPath, main);
  for (const build of config.builds) {
    if (build?.compileTarget === 'dart2js') build.mainJsPath = named;
  }
  writeFileSync(bootstrapPath, boundBootstrap.replace(assignment, () => `_flutter.buildConfig = ${JSON.stringify(config)};`));
  if (archive) retain(web, archive, project, tree);
}

try {
  run();
} catch (error) {
  console.error(`fingerprint-web: ${error.message}`);
  process.exitCode = 1;
}
