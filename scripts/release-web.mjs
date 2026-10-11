// Packages a strict app release after fingerprint-web. The archive is
// additive and project-scoped: never rotate away a published boot/chunk URL.
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { Script } from 'node:vm';
import { fileURLToPath } from 'node:url';

const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
const releasePattern = /^[0-9a-f]{20}$/;
function tree(dir, prefix = '') {
  const out = [];
  for (const item of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name < b.name ? -1 : 1)) {
    if (!/^[A-Za-z0-9_.-]+$/.test(item.name) || item.name.startsWith('.')) throw new Error('unsupported release asset path');
    const path = `${prefix}${item.name}`;
    if (item.isDirectory()) out.push(...tree(join(dir, item.name), `${path}/`));
    else if (item.isFile()) out.push({ path, bytes: readFileSync(join(dir, item.name)) });
    else throw new Error(`unsupported release asset: ${path}`);
  }
  return out;
}
function immutableWrite(path, bytes) {
  if (existsSync(path)) {
    if (!lstatSync(path).isFile() || !readFileSync(path).equals(Buffer.from(bytes))) throw new Error(`immutable release collision: ${path}`);
    return;
  }
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytes, { flag: 'wx' });
}
function run() {
  const [web, archiveFlag, archive, projectFlag, project] = process.argv.slice(2);
  if (!web || archiveFlag !== '--archive' || !archive || projectFlag !== '--project' || !/^[a-z][a-z0-9-]{0,62}$/.test(project ?? '')) {
    throw new Error('usage: release-web.mjs <web> --archive <dir> --project <id>');
  }
  if (readFileSync(join(web, '.web-assets-project'), 'utf8') !== project) throw new Error('release build belongs to another project');
  const inputPath = join(web, '.martha-release-input');
  const currentHtml = readFileSync(join(web, 'app.html'), 'utf8');
  const html = currentHtml.includes('/*martha-boot*/') ? readFileSync(inputPath, 'utf8') : currentHtml;
  if (!html.includes('src="flutter_bootstrap.js"') || !html.includes('src="martha_app.js"')) throw new Error('expected app shell and update runtime scripts');
  const bootstrap = readFileSync(join(web, 'flutter_bootstrap.js'), 'utf8');
  const config = JSON.parse(/_flutter\.buildConfig\s*=\s*(\{[\s\S]*?\})\s*;/.exec(bootstrap)?.[1]);
  const builds = config.builds.filter((build) => build?.compileTarget === 'dart2js');
  if (builds.length !== 1 || config.builds.some((build) => build?.compileTarget === 'dart2wasm')) throw new Error('expected one dart2js release build');
  const main = builds[0].mainJsPath;
  if (!/^main\.dart\.[0-9a-f]{10}\.js$/.test(main)) throw new Error('main entry point must be content-named');
  const mainBytes = readFileSync(join(web, main));
  if (!main.includes(sha(mainBytes).slice(0, 10))) throw new Error('main entry point hash mismatch');
  const base = /\/\*martha-assets\*\/\s*"(asset-bundles\/[0-9a-f]{10}\/)"/.exec(bootstrap)?.[1];
  if (!base) throw new Error('asset bundle must be bound to the bootstrap');
  const chunks = [...new Set(mainBytes.toString().match(/main\.dart\.js_\d+\.part\.[0-9a-f]{10}\.js/g) ?? [])].sort();
  const shared = [{ path: main, bytes: mainBytes, optional: false }, ...chunks.map((path) => {
    const bytes = readFileSync(join(web, path));
    if (!path.includes(sha(bytes).slice(0, 10))) throw new Error(`deferred chunk hash mismatch: ${path}`);
    return { path, bytes, optional: true };
  }), ...tree(join(web, base, 'assets'), `${base}assets/`).map((file) => ({ ...file, optional: !/(?:AssetManifest\.(?:bin|json)|FontManifest\.json|app_zh\.arb|MaterialIcons(?:-Regular)?\.[a-f0-9]+\.(?:otf|ttf)|CupertinoIcons\.[a-f0-9]+\.ttf)$/.test(file.path) }))];
  const local = [
    ...tree(join(web, 'icons'), 'icons/').map((file) => ({ ...file, optional: file.path !== 'icons/Icon-192.png' })),
    ...tree(join(web, 'canvaskit'), 'canvaskit/').map((file) => ({ ...file, optional: true, engine: true })),
    { path: 'favicon.png', bytes: readFileSync(join(web, 'favicon.png')), optional: false },
    { path: 'manifest.json', bytes: readFileSync(join(web, 'manifest.json')), optional: false },
    { path: 'martha_app.js', bytes: readFileSync(join(web, 'martha_app.js')), optional: false },
  ];
  // Identity includes the unbound inputs; binding a release URL into its own
  // HTML/bootstrap would otherwise make the content hash self-referential.
  const identity = sha(JSON.stringify({ project, html, bootstrap, files: [...shared, ...local].map((file) => [file.path, sha(file.bytes), file.optional, file.engine ?? false]), packager: sha(readFileSync(fileURLToPath(import.meta.url))), worker: sha(readFileSync(join(web, 'martha_app_sw.js'))) }));
  const id = identity.slice(0, 20);
  const prefix = `releases/${id}/`;
  const metadata = { schema: 1, project, id, metadata: `/${prefix}release.json` };
  const boundHtml = html
    .replace('<head>', `<head><script>/*martha-boot*/window.marthaBootRelease=Object.freeze(${JSON.stringify(metadata)});</script>`)
    .replaceAll('src="flutter_bootstrap.js"', `src="/${prefix}flutter_bootstrap.js"`)
    .replaceAll('src="martha_app.js"', `src="/${prefix}martha_app.js"`)
    .replace(/(?:src|href)="((?:icons\/[^"\s]+|favicon\.png|manifest\.json))"/g, (match, path) => match.replace(path, `/${prefix}${path}`));
  if (boundHtml === html || !boundHtml.includes('/*martha-boot*/')) throw new Error('expected a complete app HTML head');
  // The platform loader must never register Flutter's obsolete worker or
  // fetch an unversioned/CDN engine beneath a versioned main entry point.
  const boundBootstrap = bootstrap.replace('_flutter.loader.load(', `_flutter.loader.load(((options={})=>({...options,serviceWorkerSettings:undefined,config:{...options.config,canvasKitBaseUrl:"/${prefix}canvaskit/"}}))(`);
  // Close the one outer wrapper at the last loader call's trailing semicolon.
  const finalBootstrap = boundBootstrap.replace(/\);\s*$/, '));');
  new Script(finalBootstrap);
  const files = [
    ...shared.map((file) => ({ ...file, url: `/${file.path}` })),
    ...local.map((file) => ({ ...file, url: `/${prefix}${file.path}` })),
    { url: `/${prefix}app.html`, bytes: Buffer.from(boundHtml), optional: false },
    { url: `/${prefix}flutter_bootstrap.js`, bytes: Buffer.from(finalBootstrap), optional: false },
  ];
  const manifest = {
    schema: 1, project, id, identity, shell: `/${prefix}app.html`, bootstrap: `/${prefix}flutter_bootstrap.js`,
    files: files.map(({ url, bytes, optional, engine }) => ({ url, sha256: sha(bytes), size: bytes.length, optional, ...(engine ? { engine: true } : {}) })),
  };
  const manifestBytes = Buffer.from(JSON.stringify(manifest));
  const pointer = { ...metadata, manifest: `/${prefix}release-manifest.json`, manifestSha256: sha(manifestBytes) };
  const releaseFiles = [...files.filter((file) => file.url.startsWith(`/${prefix}`)),
    { url: pointer.manifest, bytes: manifestBytes }, { url: metadata.metadata, bytes: Buffer.from(JSON.stringify(pointer)) }];
  const history = join(archive, project);
  // Validate all existing immutable destinations before publishing any part.
  for (const file of releaseFiles) {
    for (const dir of [web, history]) {
      const target = join(dir, file.url.slice(1));
      if (existsSync(target) && (!lstatSync(target).isFile() || !readFileSync(target).equals(file.bytes))) throw new Error('immutable release collision');
    }
  }
  for (const file of releaseFiles) {
    immutableWrite(join(web, file.url.slice(1)), file.bytes);
    immutableWrite(join(history, file.url.slice(1)), file.bytes);
  }
  const historical = join(history, 'releases');
  for (const entry of readdirSync(historical, { withFileTypes: true })) {
    if (!releasePattern.test(entry.name) || !entry.isDirectory()) throw new Error('unsupported archived release');
    for (const file of tree(join(historical, entry.name), `releases/${entry.name}/`)) immutableWrite(join(web, file.path), file.bytes);
  }
  writeFileSync(inputPath, html);
  writeFileSync(join(web, 'app.html'), boundHtml);
  writeFileSync(join(web, 'release.json'), JSON.stringify(pointer));
}
try { run(); } catch (error) { console.error(`release-web: ${error.message}`); process.exitCode = 1; }
