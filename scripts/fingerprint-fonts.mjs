// Names the web build's fonts after their contents, and points
// assets/FontManifest.json at the new names. Flutter keeps only the icons
// the app uses, so MaterialIcons-Regular.otf changes with every build under
// the same name: a phone holding yesterday's copy shows blanks for new
// icons. Named after their contents, fonts can be cached for good (the
// hashed-font header in firebase.json, which knows these names: 10 hex
// digits before the extension). Run on every Hosting deploy
// (hosting-predeploy.sh). Copies first, then the manifest, then removes the
// old names, so a run cut short can simply run again.
//
//   node scripts/fingerprint-fonts.mjs app/build/web
import { createHash } from 'node:crypto';
import { copyFileSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const web = process.argv[2];
const manifestPath = join(web, 'assets', 'FontManifest.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const named = /\.[0-9a-f]{10}\.(otf|ttf)$/;

const old = [];
for (const family of manifest) {
  for (const font of family.fonts) {
    if (named.test(font.asset)) continue;
    const from = join(web, 'assets', font.asset);
    const hash = createHash('sha256').update(readFileSync(from)).digest('hex').slice(0, 10);
    const asset = font.asset.replace(/\.(otf|ttf)$/, `.${hash}.$1`);
    copyFileSync(from, join(web, 'assets', asset));
    font.asset = asset;
    old.push(from);
  }
}
writeFileSync(manifestPath, JSON.stringify(manifest));
for (const file of old) rmSync(file);
