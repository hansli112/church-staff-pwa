// Drops old app releases from the project's web archive
// (.firebase/web-assets/<project>), so each Hosting deploy stops carrying
// every release ever published. Keeps the releases packaged in the last
// --keep-days days, and at least the newest --keep of them, with the main
// entries, deferred chunks and asset bundles their manifests name.
//
//   node scripts/prune-web-archive.mjs .firebase/web-assets --project <id>
//     [--keep-days 14] [--keep 10] [--now <ISO time>]
//
// What an older release loses: an installed app last opened before then
// boots its cached shell once, then the latest; in that one session a
// deferred page (管理後台, 教會資訊, …) it never opened says 載入失敗.
// Loose fonts in assets/ are left as they are. Nothing is deleted when any
// release's manifest cannot be read.
import { existsSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';

const releasePattern = /^[0-9a-f]{20}$/;

function run() {
  const [archive, ...rest] = process.argv.slice(2);
  const options = { '--keep-days': '14', '--keep': '10', '--now': new Date().toISOString() };
  let project;
  for (let i = 0; i < rest.length; i += 2) {
    if (rest[i] === '--project') project = rest[i + 1];
    else if (rest[i] in options && rest[i + 1] !== undefined) options[rest[i]] = rest[i + 1];
    else throw new Error(`unknown option: ${rest[i]}`);
  }
  if (!archive || !/^[a-z][a-z0-9-]{0,62}$/.test(project ?? '')) {
    throw new Error('usage: prune-web-archive.mjs <archive> --project <id> [--keep-days N] [--keep N] [--now ISO]');
  }
  const keepDays = Number(options['--keep-days']);
  const keepCount = Number(options['--keep']);
  const now = new Date(options['--now']).getTime();
  if (!(keepDays >= 0) || !Number.isInteger(keepCount) || keepCount < 1 || Number.isNaN(now)) throw new Error('invalid --keep-days, --keep or --now');

  const history = join(archive, project);
  const releasesDir = join(history, 'releases');
  if (!existsSync(releasesDir)) return;

  // Read every manifest before deleting anything.
  const releases = readdirSync(releasesDir, { withFileTypes: true }).map((entry) => {
    if (!entry.isDirectory() || !releasePattern.test(entry.name)) throw new Error(`unsupported archived release: ${entry.name}`);
    const path = join(releasesDir, entry.name, 'release-manifest.json');
    let manifest;
    try {
      manifest = JSON.parse(readFileSync(path, 'utf8'));
      if (!Array.isArray(manifest.files) || manifest.files.some((f) => typeof f?.url !== 'string')) throw new Error();
    } catch {
      throw new Error(`unreadable release manifest: ${entry.name}`);
    }
    return { id: entry.name, packaged: statSync(path).mtimeMs, urls: manifest.files.map((f) => f.url) };
  }).sort((a, b) => b.packaged - a.packaged);

  const cutoff = now - keepDays * 86400000;
  const kept = releases.filter((r, i) => i < keepCount || r.packaged >= cutoff);
  const dropped = releases.filter((r) => !kept.includes(r));
  if (!dropped.length) return;

  const used = new Set(kept.flatMap((r) => r.urls));
  const bundlesUsed = new Set([...used].map((url) => /^\/asset-bundles\/([0-9a-f]{10})\//.exec(url)?.[1]).filter(Boolean));
  let removed = 0;
  for (const r of dropped) {
    rmSync(join(releasesDir, r.id), { recursive: true, force: true });
    removed++;
  }
  for (const name of readdirSync(history)) {
    if (/^main\.dart\./.test(name) && statSync(join(history, name)).isFile() && !used.has(`/${name}`)) {
      rmSync(join(history, name));
      removed++;
    }
  }
  const bundles = join(history, 'asset-bundles');
  if (existsSync(bundles)) {
    for (const name of readdirSync(bundles)) {
      if (/^[0-9a-f]{10}$/.test(name) && !bundlesUsed.has(name)) {
        rmSync(join(bundles, name), { recursive: true, force: true });
        removed++;
      }
    }
  }
  console.log(`prune-web-archive: ${dropped.length} old releases dropped, ${kept.length} kept (${removed} entries removed)`);
}

try {
  run();
} catch (error) {
  console.error(`prune-web-archive: ${error.message}`);
  process.exitCode = 1;
}
