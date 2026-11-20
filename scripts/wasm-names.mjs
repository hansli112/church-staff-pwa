// The wasm web app's function names: kept here, not shipped. The web app
// reports its errors with wasm-function[4284] in place of names; the build
// keeps them (--no-strip-wasm), this takes them out of what is deployed and
// files them under the name the deployed file gets (main.dart.<hash>.wasm,
// as scripts/fingerprint-web.mjs names it). So users download no more than a
// stripped build, and an error from a deploy can still be read.
//
//   node scripts/wasm-names.mjs strip app/build/web .firebase/wasm-names/marthasit
//   node scripts/wasm-names.mjs name .firebase/wasm-names/marthasit < error.txt
//
// `name` replaces every main.dart.<hash>.wasm:wasm-function[N] in its input
// with the function's name, from the file filed for that hash.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [command, ...args] = process.argv.slice(2);

function leb(bytes, at) {
  let value = 0;
  let shift = 0;
  for (;;) {
    const byte = bytes[at++];
    value += (byte & 0x7f) * 2 ** shift;
    shift += 7;
    if (byte < 0x80) return [value, at];
  }
}

/** The wasm's sections: id, where it starts, where its contents start and end. */
function sections(bytes) {
  const out = [];
  let at = 8;
  while (at < bytes.length) {
    const id = bytes[at];
    const [size, body] = leb(bytes, at + 1);
    let name = null;
    if (id === 0) {
      const [length, start] = leb(bytes, body);
      name = bytes.subarray(start, start + length).toString('utf8');
    }
    out.push({ id, name, start: at, body, end: body + size });
    at = body + size;
  }
  return out;
}

/** Function index → name, from a wasm `name` section's contents. */
function functionNames(section) {
  const names = new Map();
  let [length, at] = leb(section, 0);
  at += length; // the section's own name, "name"
  while (at < section.length) {
    const kind = section[at];
    const [size, body] = leb(section, at + 1);
    if (kind === 1) {
      let [count, p] = leb(section, body);
      for (let i = 0; i < count; i++) {
        let index;
        let nameLength;
        [index, p] = leb(section, p);
        [nameLength, p] = leb(section, p);
        names.set(index, section.subarray(p, p + nameLength).toString('utf8'));
        p += nameLength;
      }
    }
    at = body + size;
  }
  return names;
}

if (command === 'strip') {
  const [web, archive] = args;
  const path = join(web, 'main.dart.wasm');
  if (!existsSync(path)) process.exit(0); // a JS-only build
  const bytes = readFileSync(path);
  const names = sections(bytes).find((s) => s.id === 0 && s.name === 'name');
  if (!names) throw new Error(`${path} has no names: build it with --no-strip-wasm`);
  const stripped = Buffer.concat([bytes.subarray(0, names.start), bytes.subarray(names.end)]);
  const hash = createHash('sha256').update(stripped).digest('hex').slice(0, 10);
  mkdirSync(archive, { recursive: true });
  writeFileSync(join(archive, `main.dart.${hash}.names`), bytes.subarray(names.body, names.end));
  writeFileSync(path, stripped);
  console.log(`wasm names kept as ${join(archive, `main.dart.${hash}.names`)}`);
} else if (command === 'name') {
  const [archive] = args;
  const text = readFileSync(0, 'utf8');
  const loaded = new Map();
  const lookup = (hash) => {
    if (!loaded.has(hash)) {
      const file = join(archive, `main.dart.${hash}.names`);
      loaded.set(hash, existsSync(file) ? functionNames(readFileSync(file)) : null);
    }
    return loaded.get(hash);
  };
  process.stdout.write(
    text.replace(/(?:[^\s()]*\/)?main\.dart\.([0-9a-f]{10})\.wasm:wasm-function\[(\d+)\](:0x[0-9a-f]+)?/g, (all, hash, index) => {
      return lookup(hash)?.get(Number(index)) ?? all;
    }),
  );
} else {
  console.error('usage: wasm-names.mjs strip <web> <archive> | name <archive> < errors');
  process.exit(2);
}
