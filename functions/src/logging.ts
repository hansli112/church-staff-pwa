import { logger } from 'firebase-functions/v2';

import { isChurchId } from './access.js';
import { fail, requireCaller, type Caller } from './common.js';

const MAX_MESSAGE = 1000;
const MAX_STACK = 8000;

/** Removes things that look like emails or phone numbers. */
export function scrub(text: string): string {
  return text
    .replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '<email>')
    .replace(/\+?\d[\d -]{7,}\d/g, '<number>');
}

/**
 * Web clients report uncaught errors here (Crashlytics does not support
 * the web). The entry is shaped as a ReportedErrorEvent so Error Reporting
 * groups it and emails the project owner about new kinds of errors.
 *
 * Only uid, church ID and the error itself are kept: no names, emails or
 * roster content.
 */
export function logClientError(caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const input = data as { message?: unknown; stack?: unknown; churchId?: unknown };
  if (typeof input?.message !== 'string' || input.message.length > MAX_MESSAGE) {
    fail('invalid-argument', 'unknown');
  }
  if (typeof input.stack !== 'string' || input.stack.length > MAX_STACK) {
    fail('invalid-argument', 'unknown');
  }
  const cid = isChurchId(input.churchId) ? input.churchId : null;
  const message = scrub(input.message);
  const stack = scrub(input.stack);
  // write(), not error(): error() appends this function's own stack trace,
  // which Error Reporting would group by instead of the client's.
  logger.write({
    severity: 'ERROR',
    message: `${message}\n${stack}`,
    '@type': 'type.googleapis.com/google.devtools.clouderrorreporting.v1beta1.ReportedErrorEvent',
    serviceContext: { service: 'web-client' },
    context: { user: c.uid },
    uid: c.uid,
    cid,
  });
  return {};
}
