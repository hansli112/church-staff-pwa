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

function colorAt(x, y) {
  const background = [30, 72, 98];
  const white = [247, 250, 248];
  const accent = [148, 212, 202];
  // Three people, rather than a congregation-specific logo or lettering.
  for (const [cx, cy, r] of [[0.5, 0.32, 0.072], [0.315, 0.39, 0.059], [0.685, 0.39, 0.059]]) {
    if ((x - cx) ** 2 + (y - cy) ** 2 <= r ** 2) return cx === 0.5 ? white : accent;
  }
  for (const [cx, top, width, bottom] of [[0.5, 0.44, 0.085, 0.735], [0.315, 0.49, 0.07, 0.69], [0.685, 0.49, 0.07, 0.69]]) {
    if (Math.abs(x - cx) <= width && y >= top + width && y <= bottom) return cx === 0.5 ? white : accent;
    if ((x - cx) ** 2 + (y - top - width) ** 2 <= width ** 2) return cx === 0.5 ? white : accent;
  }
  return background;
}

function png(size) {
  const samples = 4;
  const rows = Buffer.alloc((size * 3 + 1) * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const rgb = [0, 0, 0];
      for (let sy = 0; sy < samples; sy++) {
        for (let sx = 0; sx < samples; sx++) {
          const color = colorAt((x + (sx + 0.5) / samples) / size, (y + (sy + 0.5) / samples) / size);
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
  writeFileSync(fileURLToPath(new URL(`../web/${path}`, import.meta.url)), png(size));
  console.log(`Generated web/${path} (${size}x${size})`);
}
