import { logger } from 'firebase-functions/v2';

import { isChurchId } from './access.js';
import { fail, type Caller } from './common.js';
import { scrub } from './redact.js';

const MAX_MESSAGE = 1000;
const MAX_STACK = 8000;
const MAX_FIELD = 200;
const MAX_AGENT = 300;

/**
 * Web clients report uncaught errors here (Crashlytics does not support
 * the web). The entry is shaped as a ReportedErrorEvent so Error Reporting
 * groups it and emails the project owner about new kinds of errors.
 *
 * Only uid, church ID and the error itself are kept: no names, emails or
 * roster content. With it, to tell where it happened: the page up (its
 * route's pattern), what the framework was doing ("while dispatching a
 * pointer event", cut before any widget's arguments by the app), its
 * library, whether nothing caught it (fatal), and the browser (agent). To
 * tell what led to it: the last pages up, each with how long before it
 * (trail, route patterns too), and how much memory the page used (memory),
 * as the wasm renderer can fail once it runs short. These are fields of the
 * entry, not of the message, so they do not split Error Reporting's groups;
 * an app too old to send them, or one sending something else, still has
 * its error logged.
 *
 * Signed out too: the loading and sign-in pages fail as well, and the
 * first error of a page load is the one that tells most.
 */
export function logClientError(caller: Caller | null, data: unknown) {
  const input = data as {
    message?: unknown; stack?: unknown; churchId?: unknown;
    screen?: unknown; during?: unknown; library?: unknown; fatal?: unknown; agent?: unknown;
    trail?: unknown; memory?: unknown;
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
    ...(caller ? { context: { user: caller.uid } } : {}),
    uid: caller?.uid ?? null,
    cid,
    screen: short(input.screen),
    during: short(input.during),
    library: short(input.library),
    fatal: typeof input.fatal === 'boolean' ? input.fatal : null,
    // The browser: an error can be its engine's (skwasm), not the app's.
    agent: typeof input.agent === 'string' && input.agent.length <= MAX_AGENT ? scrub(input.agent) : null,
    trail: short(input.trail),
    memory: short(input.memory),
  });
  return {};
}

/** A short string as sent, scrubbed; else null. */
const short = (v: unknown) => (typeof v === 'string' && v.length > 0 && v.length <= MAX_FIELD ? scrub(v) : null);
