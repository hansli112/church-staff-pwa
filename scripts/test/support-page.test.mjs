import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const pages = ['support.html', 'zh-Hans/support.html', 'en/support.html', 'ja/support.html', 'ko/support.html'];

// The payment section's fine print, in every language: who handles the
// payment, that it takes a fee, and that what arrives is less.
test('every support page says ECPay takes a fee out of each payment', () => {
  for (const page of pages) {
    const html = readFileSync(join(root, 'landing', page), 'utf8');
    const on = html.slice(html.indexOf('<!-- payments:on -->'), html.indexOf('<!-- /payments:on -->'));
    const fine = [...on.matchAll(/<p class="fine">([^<]*)<\/p>/g)].map((m) => m[1]);
    assert.equal(fine.length, 1, `${page}: one line of fine print`);
    assert.match(fine[0], /綠界|绿界|ECPay/, `${page}: who handles the payment`);
    assert.match(fine[0], /[（(][^）)]+[）)]/, `${page}: the amount paid is not the amount received, in brackets`);
  }
});
