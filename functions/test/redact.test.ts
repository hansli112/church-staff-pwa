import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { inspect } from 'node:util';

import { loggable, scrub } from '../src/redact.js';

describe('what errors log', () => {
  test('scrubs emails and phone numbers', () => {
    assert.equal(scrub('user john@example.com failed'), 'user <email> failed');
    assert.equal(scrub('call 0912 345 678'), 'call <number>');
  });

  test('a Google API error logs its code and message, not the request it carried', () => {
    const e = Object.assign(new Error('The caller does not have permission'), {
      code: 403,
      status: 'PERMISSION_DENIED',
      config: { headers: { Authorization: 'Bearer ya29.secret' }, data: { summary: '李美玉 生日' } },
      response: { data: { attendees: [{ email: 'mei@example.com' }] } },
    });
    const logged = inspect(loggable(e));
    assert.match(logged, /The caller does not have permission/);
    assert.match(logged, /403/);
    assert.match(logged, /PERMISSION_DENIED/);
    assert.match(logged, /redact\.test\.ts/, 'where it was thrown');
    for (const hidden of ['ya29', '李美玉', 'mei@example.com']) assert.doesNotMatch(logged, new RegExp(hidden));
  });

  test('an email in the message is scrubbed from the stack too', () => {
    const logged = inspect(loggable(new TypeError('no member mei@example.com')));
    assert.match(logged, /TypeError/);
    assert.match(logged, /no member <email>/);
    assert.doesNotMatch(logged, /mei@example\.com/);
  });

  test('what is not an error logs as its scrubbed text', () => {
    assert.equal(loggable('mei@example.com refused').message, '<email> refused');
  });
});
