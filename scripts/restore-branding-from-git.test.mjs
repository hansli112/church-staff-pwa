import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { deflateSync } from 'node:zlib';
import defaults from '../worker/generated_config.js';
import { restoreBranding, validateGitRef, validatePng } from './restore-branding-from-git.mjs';

const REF = 'a1'.repeat(20);
const sourceSizes = new Map([
  ['web/favicon.png', 32], ['web/icons/Icon-192.png', 192], ['web/icons/Icon-512.png', 512],
  ['web/icons/Icon-maskable-192.png', 192], ['web/icons/Icon-maskable-512.png', 512],
]);

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1) ? (0xedb88320 ^ (crc >>> 1)) : (crc >>> 1);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, body) {
  const bytes = Buffer.alloc(body.length + 12);
  bytes.writeUInt32BE(body.length);
  bytes.write(type, 4);
  body.copy(bytes, 8);
  bytes.writeUInt32BE(crc32(bytes.subarray(4, 8 + body.length)), 8 + body.length);
  return bytes;
}
function png(size, { badFilter = false, shortRows = false } = {}) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8;
  header[9] = 2;
  const rows = Buffer.alloc((size * 3 + 1) * size - (shortRows ? 1 : 0));
  if (badFilter) rows[0] = 5;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', header), chunk('IDAT', deflateSync(rows)), chunk('IEND', Buffer.alloc(0)),
  ]);
}
const blobs = new Map([...sourceSizes].map(([source, size]) => [source, png(size)]));

async function fixture(t) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'church-git-branding-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const config = structuredClone(defaults);
  for (const key of Object.keys(config.icons)) config.icons[key] = 'original/' + config.icons[key];
  const configPath = path.join(root, 'church.json');
  await writeFile(configPath, JSON.stringify(config));
  const calls = [];
  const git = {
    isIgnored: async (_root, relative) => { calls.push(['ignored', relative]); return true; },
    assertCommit: async (_root, ref) => { calls.push(['commit', ref]); },
    readBlob: async (_root, ref, source) => { calls.push(['blob', ref, source]); return blobs.get(source); },
  };
  const options = { root, configPath, ref: REF, outDir: '.local/branding', git };
  return { root, config, configPath, git, calls, options };
}

async function noOutput(root) {
  await assert.rejects(() => readdir(path.join(root, '.local')), { code: 'ENOENT' });
}

test('only complete hexadecimal commit IDs are accepted', () => {
  assert.equal(validateGitRef(REF.toUpperCase()), REF);
  for (const ref of ['HEAD', 'main', '123abcd', 'a'.repeat(39), 'b'.repeat(41), 'g'.repeat(40), '-'.repeat(40), REF + ':web/favicon.png', '$(touch x)', REF + '\n']) {
    assert.throws(() => validateGitRef(ref), /40-hex/);
  }
});

test('valid PNG structure, dimensions and bounded image data are required', () => {
  for (const [source, bytes] of blobs) validatePng(bytes, sourceSizes.get(source), source);
  validatePng(png(32), null);
  assert.throws(() => validatePng(png(512), null), /favicon/);
  assert.throws(() => validatePng(png(192), 512), /512x512/);
  assert.throws(() => validatePng(Buffer.alloc(4 * 1024 * 1024 + 1), 512), /4 MiB/);
  assert.throws(() => validatePng(Buffer.alloc(50), 192), /signature/);
  assert.throws(() => validatePng(png(192).subarray(0, 70), 192), /truncated|missing/);
  const brokenCrc = Buffer.from(png(192));
  brokenCrc[29] ^= 1;
  assert.throws(() => validatePng(brokenCrc, 192), /CRC/);
  assert.throws(() => validatePng(png(192, { badFilter: true }), 192), /filter/);
  assert.throws(() => validatePng(png(192, { shortRows: true }), 192), /scanline/);
});

test('five fixed Git paths map to config icons, and identical reruns are idempotent', async (t) => {
  const { root, calls, options, config } = await fixture(t);
  assert.equal((await restoreBranding(options)).written, 5);
  const result = await restoreBranding(options);
  assert.equal(result.written, 0);
  assert.equal(result.unchanged, 5);
  assert.deepEqual(calls.filter(([kind]) => kind === 'blob').slice(0, 5).map(([, , source]) => source), [...sourceSizes.keys()]);
  for (const [index, key] of Object.keys(config.icons).entries()) {
    assert.deepEqual(await readFile(path.join(root, '.local/branding', config.icons[key])), blobs.get([...sourceSizes.keys()][index]));
  }
  assert.deepEqual((await readdir(root)).sort(), ['.local', 'church.json']);
});

test('bad full config or unpinned revision fails before reading Git or writing outputs', async (t) => {
  const { root, configPath, config, calls, options } = await fixture(t);
  await assert.rejects(() => restoreBranding({ ...options, ref: 'HEAD' }), /40-hex/);
  config.timeZone = 'not/a-timezone';
  await writeFile(configPath, JSON.stringify(config));
  await assert.rejects(() => restoreBranding(options), /IANA/);
  assert.equal(calls.length, 0);
  await noOutput(root);
});

test('missing or corrupt final Git blob leaves no partial output', async (t) => {
  const { root, git, options } = await fixture(t);
  for (const mode of ['missing', 'corrupt']) {
    await assert.rejects(() => restoreBranding({ ...options, git: {
      ...git,
      readBlob: async (_root, _ref, source) => {
        if (source.endsWith('Icon-maskable-512.png')) {
          if (mode === 'missing') throw new Error('missing Git blob');
          return png(192);
        }
        return blobs.get(source);
      },
    } }), /missing Git blob|512x512/);
    await noOutput(root);
  }
});

test('different existing content is never overwritten and no other asset is written', async (t) => {
  const { root, config, options } = await fixture(t);
  const last = path.join(root, '.local/branding', config.icons.maskable512);
  await mkdir(path.dirname(last), { recursive: true });
  await writeFile(last, 'keep this existing content');
  await assert.rejects(() => restoreBranding(options), /refusing to overwrite/);
  assert.equal(await readFile(last, 'utf8'), 'keep this existing content');
  await assert.rejects(() => readFile(path.join(root, '.local/branding', config.icons.favicon)), { code: 'ENOENT' });
});

test('output must be a gitignored .local subdirectory', async (t) => {
  const { root, git, options } = await fixture(t);
  for (const outDir of ['web', '.local', '.local/../web', root, path.dirname(root)]) {
    await assert.rejects(() => restoreBranding({ ...options, outDir }), /gitignored subdirectory/);
  }
  await assert.rejects(() => restoreBranding({ ...options, git: { ...git, isIgnored: async () => false } }), /must be gitignored/);
  await noOutput(root);
});

test('symlinked output roots, nested parents and targets cannot escape', async (t) => {
  const { root, config, options } = await fixture(t);
  const outside = path.join(root, 'outside');
  await mkdir(outside);
  await symlink(outside, path.join(root, '.local'));
  await assert.rejects(() => restoreBranding(options), /symlinks/);
  await rm(path.join(root, '.local'));
  await mkdir(path.join(root, '.local/branding'), { recursive: true });
  await symlink(outside, path.join(root, '.local/branding/original'));
  await assert.rejects(() => restoreBranding(options), /symlinks/);
  await rm(path.join(root, '.local/branding/original'));
  await mkdir(path.join(root, '.local/branding/original'));
  await writeFile(path.join(outside, 'asset.png'), blobs.get('web/favicon.png'));
  await symlink(path.join(outside, 'asset.png'), path.join(root, '.local/branding', config.icons.favicon));
  await assert.rejects(() => restoreBranding(options), /regular file without links/);
  assert.deepEqual(await readdir(outside), ['asset.png']);
});

test('colliding config destinations fail before writing', async (t) => {
  const { root, config, configPath, options } = await fixture(t);
  config.icons.icon192 = config.icons.favicon;
  await writeFile(configPath, JSON.stringify(config));
  await assert.rejects(() => restoreBranding(options), /same output path/);
  await noOutput(root);
});

test('a non-commit object or unavailable local commit cannot be restored', async (t) => {
  const { root, git, calls, options } = await fixture(t);
  await assert.rejects(() => restoreBranding({ ...options, git: { ...git, assertCommit: async () => { throw new Error('not a local commit'); } } }), /not a local commit/);
  assert.equal(calls.filter(([kind]) => kind === 'blob').length, 0);
  await noOutput(root);
});
