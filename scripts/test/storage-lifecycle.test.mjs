import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const read = (path) => readFileSync(join(root, path), 'utf8');
const { rule } = JSON.parse(read('storage-lifecycle.json'));

/** Whether Storage's lifecycle deletes [path] once it is [days] old. */
const deleted = (path, days) =>
  rule.some((r) => r.action.type === 'Delete' && days >= r.condition.age && r.condition.matchesPrefix.some((p) => path.startsWith(p)));

test('a 搬家檔 not moved goes after a day; a church logo stays', () => {
  const move = 'moves/uid123/1794389245771.json';
  assert.ok(new RegExp(read('functions/src/move.ts').match(/`\^(moves\/)\$\{/)[1]).test(move), 'where the app uploads a move file');
  assert.ok(read('storage.rules').includes('match /moves/{uid}/{file}'));
  assert.equal(deleted(move, 0), false, 'not while it may still be moved');
  assert.equal(deleted(move, 1), true);
  assert.equal(deleted('churches/grace/logo.png', 365), false);
});

test('a new project gets the rule', () => {
  assert.match(read('scripts/firebase-project.sh'), /storage\/v1\/b\/\$project\.firebasestorage\.app\?fields=lifecycle[\s\S]*storage-lifecycle\.json/);
});
