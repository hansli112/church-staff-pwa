#!/usr/bin/env node
// Original geometric PWA artwork, distributed under the repository's MIT license.
// Node standard library only: opaque background and all marks inside maskable safe area.
import { deflateSync } from 'node:zlib';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(name, body) {
  const type = Buffer.from(name);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(body.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([type, body])));
  return Buffer.concat([length, type, body, crc]);
}

const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

function insideRoundedRect(x, y, left, top, size, radius) {
  const dx = Math.max(left + radius - x, 0, x - (left + size - radius));
  const dy = Math.max(top + radius - y, 0, y - (top + size - radius));
  return x >= left && x <= left + size && y >= top && y <= top + size && dx * dx + dy * dy <= radius * radius;
}

// A 3×4 roster grid whose lit cells form a Latin cross, rather than a
// congregation-specific logo or lettering. The favicon drops the dim cells so
// the cross still reads at 16–32px.
function colorAt(x, y, { dimCells = true } = {}) {
  const background = mix([20, 184, 166], [15, 76, 92], Math.min(Math.max((x + y) / 2, 0), 1));
  const white = [255, 255, 255];
  for (let row = 0; row < 4; row++) {
    for (let col = 0; col < 3; col++) {
      if (!insideRoundedRect(x, y, (144 + col * 80) / 512, (104 + row * 80) / 512, 64 / 512, 17 / 512)) continue;
      if (col === 1 || row === 1) return white;
      return dimCells ? mix(background, white, 0.22) : background;
    }
  }
  return background;
}

function png(size, options) {
  const samples = 4;
  const rows = Buffer.alloc((size * 3 + 1) * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const rgb = [0, 0, 0];
      for (let sy = 0; sy < samples; sy++) {
        for (let sx = 0; sx < samples; sx++) {
          const color = colorAt((x + (sx + 0.5) / samples) / size, (y + (sy + 0.5) / samples) / size, options);
          for (let c = 0; c < 3; c++) rgb[c] += color[c];
        }
      }
      const offset = y * (size * 3 + 1) + 1 + x * 3;
      for (let c = 0; c < 3; c++) rows[offset + c] = Math.round(rgb[c] / (samples * samples));
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8;
  header[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
}

for (const [path, size] of [['favicon.png', 32], ['icons/Icon-192.png', 192], ['icons/Icon-512.png', 512], ['icons/Icon-maskable-192.png', 192], ['icons/Icon-maskable-512.png', 512]]) {
  writeFileSync(fileURLToPath(new URL(`../web/${path}`, import.meta.url)), png(size, { dimCells: path !== 'favicon.png' }));
  console.log(`Generated web/${path} (${size}x${size})`);
}
