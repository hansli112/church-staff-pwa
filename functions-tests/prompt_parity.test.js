// Pins worker/roster_prompt.js to scripts/build-import-prompt.py.
//
// The prompt is filled twice by two different languages: the Python fills the
// copy under .local/ that a human eyeballs and that try-gemini-import.py sends,
// and the JS fills the one the deployed function sends. docs promise the two
// produce the same text.
//
// Nothing else would catch a drift. Change NAMES_PER_LINE on one side and every
// test still passes, every prompt still works, and the only symptom is that the
// prompt verified locally stopped being the prompt that goes out.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { parityConstants } from '../worker/roster_prompt.js';

const PY = readFileSync(new URL('../scripts/build-import-prompt.py', import.meta.url), 'utf8');

/// Reads a module-level constant out of the Python source.
///
/// Parsing the source rather than running it: invoking the script needs gcloud
/// credentials and network, and this test is about two literals agreeing.
function pythonConstant(name) {
  const match = new RegExp(`^${name}\\s*=\\s*(.+)$`, 'm').exec(PY);
  assert.ok(match, `scripts/build-import-prompt.py 裡找不到 ${name}`);
  return match[1].trim();
}

describe('prompt 兩邊的常數', () => {
  test('LIVE_FIELDS 一致', () => {
    const raw = pythonConstant('LIVE_FIELDS');
    const fields = [...raw.matchAll(/"([A-Z_]+)"/g)].map((m) => m[1]);
    assert.deepEqual(
      fields,
      parityConstants.liveFields,
      'worker 填的欄位跟 Python 留下來的對不上 —— 模板會帶著 {{...}} 送出去',
    );
  });

  test('NAMES_PER_LINE 一致', () => {
    assert.equal(Number(pythonConstant('NAMES_PER_LINE')), parityConstants.namesPerLine);
  });

  test('活動清單空的時候寫的字一致', () => {
    assert.equal(pythonConstant('NO_EVENTS').replace(/^"|"$/g, ''), parityConstants.noEvents);
  });

  // 上面三條守的是常數；這一條守的是「有沒有人新增了第四個常數卻沒接上」。
  test('Python 沒有留下 worker 不知道的欄位', () => {
    const used = [...PY.matchAll(/\{\{([A-Z_]+)\}\}/g)].map((m) => m[1]);
    const authored = ['LAYOUT_RULES', 'EXTRA_ROLE_RULES', 'NICKNAMES', 'TEAM_RULES'];
    for (const field of new Set(used)) {
      assert.ok(
        parityConstants.liveFields.includes(field) || authored.includes(field),
        `${field} 既不是 worker 會填的，也不在發佈時就填掉的那幾個`,
      );
    }
  });
});
