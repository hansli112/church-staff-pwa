#!/usr/bin/env node
// Restore only the five standard PWA PNGs from an explicitly pinned commit.
// This helper reads local Git objects; fetching the commit is the CI caller's job.
import { execFile } from 'node:child_process';
import { constants } from 'node:fs';
import { lstat, mkdir, open, readFile, realpath, unlink } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { inflateSync } from 'node:zlib';
import { validateChurchConfig } from '../worker/church_config.js';

const execFileAsync = promisify(execFile);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MAX_PNG_BYTES = 4 * 1024 * 1024;
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const SOURCES = [
  ['favicon', 'web/favicon.png', null],
  ['icon192', 'web/icons/Icon-192.png', 192],
  ['icon512', 'web/icons/Icon-512.png', 512],
  ['maskable192', 'web/icons/Icon-maskable-192.png', 192],
  ['maskable512', 'web/icons/Icon-maskable-512.png', 512],
];
const CRC_TABLE = Array.from({ length: 256 }, (_, value) => {
  for (let bit = 0; bit < 8; bit += 1) value = (value & 1) ? (0xedb88320 ^ (value >>> 1)) : (value >>> 1);
  return value >>> 0;
});
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = CRC_TABLE[(crc ^ byte) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

export function validateGitRef(ref) {
  if (typeof ref !== 'string' || !/^[0-9a-fA-F]{40}$/.test(ref)) {
    throw new Error('--ref must be a complete 40-hex commit SHA');
  }
  return ref.toLowerCase();
}

// Check the actual PNG structure, CRCs and bounded decompressed scanlines, not
// just the extension/signature. Supports RGB, RGBA, grayscale, indexed and Adam7.
export function validatePng(bytes, size, label = 'PNG') {
  const fail = (detail) => { throw new Error(`${label}: ${detail}`); };
  if (!Buffer.isBuffer(bytes) || bytes.length < 45 || bytes.length > MAX_PNG_BYTES) fail('PNG must be 45 bytes to 4 MiB');
  if (!bytes.subarray(0, 8).equals(PNG_SIGNATURE)) fail('invalid PNG signature');
  let offset = 8;
  let header;
  let palette = false;
  let ended = false;
  let idatEnded = false;
  const compressed = [];
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) fail('truncated PNG chunk');
    const length = bytes.readUInt32BE(offset);
    if (offset + length + 12 > bytes.length) fail('truncated PNG chunk');
    const type = bytes.toString('latin1', offset + 4, offset + 8);
    if (!/^[A-Za-z]{4}$/.test(type)) fail('invalid PNG chunk type');
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    if (crc32(bytes.subarray(offset + 4, offset + 8 + length)) !== bytes.readUInt32BE(offset + 8 + length)) fail('invalid PNG CRC');
    if (!header && type !== 'IHDR') fail('IHDR must be first');
    if (type === 'IHDR') {
      if (header || length !== 13) fail('invalid IHDR');
      const width = data.readUInt32BE(0);
      const height = data.readUInt32BE(4);
      if (width !== height || (size ? width !== size : width < 16 || width > 256)) {
        fail(size ? `expected ${size}x${size} pixels` : 'favicon must be square, 16 to 256 pixels');
      }
      const depth = data[8];
      const color = data[9];
      const validDepths = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] };
      if (!validDepths[color]?.includes(depth) || data[10] !== 0 || data[11] !== 0 || data[12] > 1) fail('unsupported PNG header');
      header = { width, height, depth, color, interlace: data[12] };
    } else if (type === 'PLTE') {
      if (palette || compressed.length || !length || length % 3 || length > 768) fail('invalid PNG palette');
      palette = true;
    } else if (type === 'IDAT') {
      if (idatEnded || (header.color === 3 && !palette)) fail('invalid PNG image data order');
      compressed.push(data);
    } else if (type === 'IEND') {
      if (length || !compressed.length || offset + 12 !== bytes.length) fail('invalid PNG end');
      ended = true;
    } else if (type[0] === type[0].toUpperCase()) {
      fail('unknown critical PNG chunk');
    }
    if (compressed.length && type !== 'IDAT') idatEnded = true;
    offset += length + 12;
  }
  if (!ended) fail('missing PNG end');
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[header.color];
  const passes = header.interlace
    ? [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]]
    : [[0, 0, 1, 1]];
  const rows = [];
  for (const [x, y, dx, dy] of passes) {
    const width = Math.ceil((header.width - x) / dx);
    const height = Math.ceil((header.height - y) / dy);
    if (width <= 0 || height <= 0) continue;
    const rowBytes = Math.ceil(width * channels * header.depth / 8) + 1;
    rows.push(...Array(height).fill(rowBytes));
  }
  const expected = rows.reduce((sum, length) => sum + length, 0);
  let decoded;
  try { decoded = inflateSync(Buffer.concat(compressed), { maxOutputLength: expected }); }
  catch { fail('invalid or oversized compressed PNG data'); }
  if (decoded.length !== expected) fail('incorrect PNG scanline length');
  offset = 0;
  for (const rowBytes of rows) {
    if (decoded[offset] > 4) fail('invalid PNG row filter');
    offset += rowBytes;
  }
}

async function gitCommand(root, args, options = {}) {
  return execFileAsync('git', args, { cwd: root, encoding: 'utf8', ...options });
}

async function assertCommit(root, ref) {
  const { stdout } = await gitCommand(root, ['cat-file', '-t', ref]);
  if (stdout.trim() !== 'commit') throw new Error('--ref must name a commit already present in local Git objects');
}

async function readBlob(root, ref, source) {
  const { stdout } = await gitCommand(root, ['show', `${ref}:${source}`], { encoding: 'buffer', maxBuffer: MAX_PNG_BYTES + 1 });
  return stdout;
}

async function isIgnored(root, relative) {
  try {
    await gitCommand(root, ['check-ignore', '--quiet', '--no-index', '--', relative]);
    const { stdout } = await gitCommand(root, ['--literal-pathspecs', 'ls-files', '--', relative]);
    return stdout.trim() === '';
  } catch (error) {
    if (error.code === 1) return false;
    throw error;
  }
}

async function existingStat(file) {
  return lstat(file).catch((error) => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
}

async function checkParents(root, target, create = false) {
  const relative = path.relative(root, path.dirname(target));
  let parent = root;
  for (const part of relative.split(path.sep)) {
    parent = path.join(parent, part);
    if (create) {
      await mkdir(parent, { mode: 0o700 }).catch((error) => {
        if (error.code !== 'EEXIST') throw error;
      });
    }
    const stat = await existingStat(parent);
    if (stat && (stat.isSymbolicLink() || !stat.isDirectory())) throw new Error('output parents must be real directories, not symlinks');
  }
}

async function hasIdenticalTarget(target, bytes) {
  const stat = await existingStat(target);
  if (!stat) return false;
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) throw new Error('existing output must be a regular file without links');
  if (stat.size !== bytes.length) throw new Error(`refusing to overwrite different asset: ${target}`);
  const handle = await open(target, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    if (!(await handle.readFile()).equals(bytes)) throw new Error(`refusing to overwrite different asset: ${target}`);
  } finally { await handle.close(); }
  return true;
}

export async function restoreBranding({ configPath, ref, outDir, root = ROOT, git = {} }) {
  const commit = validateGitRef(ref);
  if (!configPath || !outDir) throw new Error('--config FILE and --out DIR are required');
  const repoRoot = await realpath(root);
  const output = path.resolve(repoRoot, outDir);
  const localRoot = path.join(repoRoot, '.local');
  if (!output.startsWith(`${localRoot}${path.sep}`)) throw new Error('--out must be a gitignored subdirectory of this repository\'s .local/');
  const config = validateChurchConfig(JSON.parse(await readFile(path.resolve(repoRoot, configPath), 'utf8')));
  await checkParents(repoRoot, path.join(output, 'asset.png'));
  if (!(await (git.isIgnored ?? isIgnored)(repoRoot, path.relative(repoRoot, output) + '/'))) {
    throw new Error('--out must be gitignored');
  }
  await (git.assertCommit ?? assertCommit)(repoRoot, commit);
  const assets = new Map();
  // Validate every source and destination before creating or writing anything.
  for (const [key, source, size] of SOURCES) {
    const bytes = await (git.readBlob ?? readBlob)(repoRoot, commit, source);
    validatePng(bytes, size, source);
    const target = path.join(output, config.icons[key]);
    if (assets.has(target) && !assets.get(target).equals(bytes)) throw new Error('different source icons map to the same output path');
    assets.set(target, bytes);
  }
  for (const [target, bytes] of assets) {
    await checkParents(repoRoot, target);
    await hasIdenticalTarget(target, bytes);
  }
  const created = [];
  try {
    for (const [target, bytes] of assets) {
      await checkParents(repoRoot, target, true);
      if (await hasIdenticalTarget(target, bytes)) continue;
      // Exclusive creation closes the overwrite race after the preflight.
      const handle = await open(target, 'wx', 0o600);
      created.push(target);
      try { await handle.writeFile(bytes); } finally { await handle.close(); }
    }
  } catch (error) {
    // Never remove pre-existing files, including equal-content rerun targets.
    await Promise.all(created.map((target) => unlink(target)));
    throw error;
  }
  return { output, written: created.length, unchanged: assets.size - created.length };
}

async function main() {
  const args = process.argv.slice(2);
  const options = {};
  const names = { '--config': 'configPath', '--ref': 'ref', '--out': 'outDir' };
  for (let index = 0; index < args.length; index += 1) {
    const flag = args[index];
    if (flag === '--help') {
      console.log('Usage: node scripts/restore-branding-from-git.mjs --config FILE --ref FULL_COMMIT_SHA --out .local/DIR\nReads only five standard web PNGs from local Git objects; no fetch, upload or overwrite.');
      return;
    }
    if (!names[flag] || options[names[flag]] !== undefined || !args[index + 1] || args[index + 1].startsWith('--')) throw new Error(`invalid argument: ${flag}`);
    options[names[flag]] = args[++index];
  }
  const result = await restoreBranding(options);
  console.log(`Restored PNG assets: ${result.written} written, ${result.unchanged} already identical. No network requests made.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
