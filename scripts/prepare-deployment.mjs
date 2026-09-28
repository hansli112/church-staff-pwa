#!/usr/bin/env node
// Generates deployment artifacts without editing tracked sources or contacting
// Firebase/Cloudflare. Church configuration is public; credentials stay separate.
import { cp, lstat, mkdir, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateChurchConfig } from '../worker/church_config.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MARKER = '.church-deployment';
export { validateChurchConfig };

export function renderRules(source, config) {
  validateChurchConfig(config);
  const marker = /\/\/ BEGIN GENERATED SERVICE IDS[\s\S]*?\/\/ END GENERATED SERVICE IDS/g;
  if ([...source.matchAll(marker)].length !== 1) throw new Error('firestore.rules must contain exactly one service-ID marker');
  return source.replace(marker,
    `// BEGIN GENERATED SERVICE IDS\n      return ${JSON.stringify(config.services.map((service) => service.id))};\n      // END GENERATED SERVICE IDS`);
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

export function renderWeb(indexSource, manifestSource, config) {
  validateChurchConfig(config);
  const replaceOne = (pattern, replacement) => {
    if ([...indexSource.matchAll(pattern)].length !== 1) throw new Error(`web/index.html metadata marker missing or duplicated: ${pattern}`);
    indexSource = indexSource.replace(pattern, () => replacement);
  };
  const name = escapeHtml(config.appName);
  // Staged HTML is copied after `flutter build --base-href /`, so it must carry
  // the final base URL, not Flutter's pre-build placeholder.
  replaceOne(/<base href="\$FLUTTER_BASE_HREF">/g, '<base href="/">');
  replaceOne(/<title>[^<]*<\/title>/g, `<title>${name}</title>`);
  replaceOne(/<meta name="description" content="[^"]*">/g, `<meta name="description" content="${name}">`);
  replaceOne(/<meta name="apple-mobile-web-app-title" content="[^"]*">/g, `<meta name="apple-mobile-web-app-title" content="${escapeHtml(config.shortName)}">`);
  replaceOne(/<link rel="apple-touch-icon" href="[^"]*">/g, `<link rel="apple-touch-icon" href="${config.icons.icon192}">`);
  replaceOne(/<link rel="icon"[^>]*>/g, `<link rel="icon" type="image/png" href="${config.icons.favicon}">`);
  replaceOne(/<div class="title">[^<]*<\/div>/g, `<div class="title">${name}</div>`);
  const manifest = JSON.parse(manifestSource);
  manifest.name = config.appName;
  manifest.short_name = config.shortName;
  manifest.description = config.appName;
  manifest.icons = [
    ['icon192', '192x192'], ['icon512', '512x512'],
    ['maskable192', '192x192', 'maskable'], ['maskable512', '512x512', 'maskable'],
  ].map(([key, sizes, purpose]) => ({
    src: config.icons[key], sizes,
    type: 'image/png', ...(purpose ? { purpose } : {}),
  }));
  return { index: indexSource, manifest: JSON.stringify(manifest, null, 2) + '\n' };
}

export function renderMessagingWorker(source, config) {
  validateChurchConfig(config);
  const title = /^  const title = data\.title \|\| notification\.title \|\| .*;$/gm;
  const icon = /^    icon: .*,$/gm;
  if ([...source.matchAll(title)].length !== 1 || [...source.matchAll(icon)].length !== 1) {
    throw new Error('firebase-messaging-sw.js branding markers missing or duplicated');
  }
  return source
    .replace(title, () => `  const title = data.title || notification.title || ${JSON.stringify(config.appName)};`)
    .replace(icon, () => `    icon: ${JSON.stringify('/' + config.icons.icon192)},`);
}

export async function prepareDeployment({ configPath = path.join(ROOT, 'config/church.example.json'), outDir, assetsDir, root = ROOT }) {
  if (!outDir) throw new Error('--out DIR is required');
  const requestedOutput = path.resolve(outDir);
  let ancestor = requestedOutput;
  const suffix = [];
  while (!(await lstat(ancestor).catch((error) => {
    if (error.code === 'ENOENT') return null;
    throw error;
  }))) {
    suffix.unshift(path.basename(ancestor));
    ancestor = path.dirname(ancestor);
  }
  const output = path.join(await realpath(ancestor), ...suffix);
  const sourceRoot = await realpath(root);
  if (output === sourceRoot || sourceRoot.startsWith(`${output}${path.sep}`) ||
      ['worker', 'functions', 'config', 'scripts', 'web', 'lib', 'test', '.github'].some((dir) => {
        const source = path.join(sourceRoot, dir);
        return output === source || output.startsWith(`${source}${path.sep}`);
      })) {
    throw new Error('--out must not overwrite tracked source directories');
  }
  const config = validateChurchConfig(JSON.parse(await readFile(configPath, 'utf8')));
  const rules = renderRules(await readFile(path.join(sourceRoot, 'firestore.rules'), 'utf8'), config);
  const webRoot = await realpath(path.join(sourceRoot, 'web'));
  const assetsRoot = await realpath(assetsDir ?? webRoot);
  const icons = new Map();
  for (const icon of new Set(Object.values(config.icons))) {
    const resolved = await realpath(path.join(assetsRoot, icon));
    if (!resolved.startsWith(`${assetsRoot}${path.sep}`) || !(await lstat(resolved)).isFile()) {
      throw new Error(`icon must be a file within the assets directory: ${icon}`);
    }
    if (resolved.startsWith(`${output}${path.sep}`)) throw new Error('assets must not be inside the output directory');
    icons.set(icon, resolved);
  }
  const web = renderWeb(
    await readFile(path.join(webRoot, 'index.html'), 'utf8'),
    await readFile(path.join(webRoot, 'manifest.json'), 'utf8'), config,
  );
  const messagingWorker = renderMessagingWorker(
    await readFile(path.join(webRoot, 'firebase-messaging-sw.js'), 'utf8'), config,
  );
  const contents = await readdir(output).catch((error) => {
    if (error.code === 'ENOENT') return [];
    throw error;
  });
  if (contents.length && !contents.includes(MARKER)) throw new Error('--out must be empty or a previously generated deployment directory');
  for (const entry of contents) {
    if ((await lstat(path.join(output, entry))).isSymbolicLink()) throw new Error('--out must not contain symbolic links');
  }
  await mkdir(output, { recursive: true });
  await writeFile(path.join(output, MARKER), 'Generated by prepare-deployment.mjs\n');
  // A removed source route must not survive in a reused staging directory.
  for (const directory of ['functions', 'worker', 'web']) {
    await rm(path.join(output, directory), { recursive: true, force: true });
  }
  await mkdir(path.join(output, 'web'), { recursive: true });
  await Promise.all([
    writeFile(path.join(output, 'web/index.html'), web.index),
    writeFile(path.join(output, 'web/manifest.json'), web.manifest),
    writeFile(path.join(output, 'web/firebase-messaging-sw.js'), messagingWorker),
    writeFile(path.join(output, 'dart-defines.json'), JSON.stringify({ CHURCH_CONFIG_JSON: JSON.stringify(config) }, null, 2) + '\n'),
    writeFile(path.join(output, 'church.json'), JSON.stringify(config, null, 2) + '\n'),
    writeFile(path.join(output, 'firestore.rules'), rules),
    writeFile(path.join(output, 'firebase.json'), JSON.stringify({ firestore: { rules: 'firestore.rules' } }, null, 2) + '\n'),
    cp(path.join(sourceRoot, 'functions'), path.join(output, 'functions'), { recursive: true }),
    cp(path.join(sourceRoot, 'worker'), path.join(output, 'worker'), { recursive: true }),
  ]);
  for (const [icon, source] of icons) {
    const target = path.join(output, 'web', icon);
    await mkdir(path.dirname(target), { recursive: true });
    await cp(source, target);
  }
  await writeFile(path.join(output, 'worker/generated_config.js'),
    '// Generated from the same configuration as Flutter and Firestore rules.\nexport default ' + JSON.stringify(config, null, 2) + ';\n');
  return { output, config };
}

async function main() {
  const args = process.argv.slice(2);
  let configPath;
  let outDir;
  let assetsDir;
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === '--help') {
      console.log('Usage: node scripts/prepare-deployment.mjs [--config FILE] [--assets DIR] --out DIR\nDefault config: config/church.example.json (neutral, optional integrations disabled).\nDefault assets: web/. Only configured relative PNG files are copied into output/web.\nNo rules are deployed. Review output/firestore.rules before deploying explicitly.');
      return;
    }
    if (!['--config', '--out', '--assets'].includes(args[i]) || !args[i + 1] || args[i + 1].startsWith('--')) throw new Error(`invalid argument: ${args[i]}`);
    if (args[i] === '--config') configPath = args[++i];
    else if (args[i] === '--assets') assetsDir = args[++i];
    else outDir = args[++i];
  }
  const { output } = await prepareDeployment({ configPath, outDir, assetsDir });
  console.log(`Prepared deployment in ${output}. No remote changes made.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
