import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const script = join(dirname(fileURLToPath(import.meta.url)), '../wasm-names.mjs');
const header = Buffer.from('\0asm\x01\0\0\0', 'latin1');
// A type section, then the names --no-strip-wasm keeps: 0 main, 1 RenderBox.hitTest.
const code = Buffer.from([0x01, 0x04, 0x01, 0x60, 0x00, 0x00]);
const names = Buffer.concat([
  Buffer.from([0x00, 0x21, 0x04]),
  Buffer.from('name'),
  Buffer.from([0x01, 0x1a, 0x02, 0x00, 0x04]),
  Buffer.from('main'),
  Buffer.from([0x01, 0x11]),
  Buffer.from('RenderBox.hitTest'),
]);

test('a deploy ships the wasm without its names; an error from it is named from what was kept', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'martha-wasm-names-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const web = join(dir, 'web');
  const archive = join(dir, 'names');
  mkdirSync(web);
  writeFileSync(join(web, 'main.dart.wasm'), Buffer.concat([header, code, names]));

  const strip = spawnSync('node', [script, 'strip', web, archive], { encoding: 'utf8' });
  assert.equal(strip.status, 0, strip.stderr);
  const shipped = readFileSync(join(web, 'main.dart.wasm'));
  assert.deepEqual(shipped, Buffer.concat([header, code]));
  assert.ok(WebAssembly.validate(shipped));

  const hash = createHash('sha256').update(shipped).digest('hex').slice(0, 10);
  const error = [
    'Null check operator used on a null value',
    `    at https://marthasit.com/main.dart.${hash}.wasm:wasm-function[1]:0x2099e5`,
    `    at https://marthasit.com/main.dart.${hash}.wasm:wasm-function[0]:0x10`,
    '    at https://marthasit.com/main.dart.0123456789.wasm:wasm-function[1]:0x1',
  ].join('\n');
  const named = spawnSync('node', [script, 'name', archive], { input: error, encoding: 'utf8' });
  assert.equal(named.status, 0, named.stderr);
  assert.equal(
    named.stdout,
    [
      'Null check operator used on a null value',
      '    at RenderBox.hitTest',
      '    at main',
      // Another deploy's, whose names are not here: as it was.
      '    at https://marthasit.com/main.dart.0123456789.wasm:wasm-function[1]:0x1',
    ].join('\n'),
  );
});
