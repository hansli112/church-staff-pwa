import { logger } from 'firebase-functions/v2';

import { isChurchId } from './access.js';
import { fail, requireCaller, type Caller } from './common.js';
import { scrub } from './redact.js';

const MAX_MESSAGE = 1000;
const MAX_STACK = 8000;
const MAX_FIELD = 200;

/**
 * Web clients report uncaught errors here (Crashlytics does not support
 * the web). The entry is shaped as a ReportedErrorEvent so Error Reporting
 * groups it and emails the project owner about new kinds of errors.
 *
 * Only uid, church ID and the error itself are kept: no names, emails or
 * roster content. With it, to tell where it happened: the page up (its
 * route's pattern), what the framework was doing ("while dispatching a
 * pointer event", cut before any widget's arguments by the app), its
 * library, and whether nothing caught it (fatal). These are fields of the
 * entry, not of the message, so they do not split Error Reporting's groups;
 * an app too old to send them, or one sending something else, still has
 * its error logged.
 */
export function logClientError(caller: Caller | null, data: unknown) {
  const c = requireCaller(caller);
  const input = data as {
    message?: unknown; stack?: unknown; churchId?: unknown;
    screen?: unknown; during?: unknown; library?: unknown; fatal?: unknown;
  };
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
    screen: short(input.screen),
    during: short(input.during),
    library: short(input.library),
    fatal: typeof input.fatal === 'boolean' ? input.fatal : null,
  });
  return {};
}

/** A short string as sent, scrubbed; else null. */
const short = (v: unknown) => (typeof v === 'string' && v.length > 0 && v.length <= MAX_FIELD ? scrub(v) : null);
