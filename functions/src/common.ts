import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { HttpsError, type FunctionsErrorCode } from 'firebase-functions/v2/https';

import { withinTextLimit } from './limits.js';

/** Region for every function, the same as Firestore. */
export const REGION = 'asia-east1';

/** The prod Firebase project (docs/firebase-setup.md); everything else is dev. */
export const PROD_PROJECT = 'marthasit';

/** One day, in milliseconds. */
export const DAY_MS = 86_400_000;

/** An amount of money to the cent. */
export const round2 = (n: number) => Math.round(n * 100) / 100;

/** The hosted web app. */
export const appUrl = () => process.env.APP_URL ?? `https://${process.env.GCLOUD_PROJECT}.web.app`;

/**
 * Who is calling. Built from the callable request so handlers can be tested
 * without the Functions runtime.
 */
export interface Caller {
  uid: string;
  email?: string;
  emailVerified: boolean;
  name?: string;
  /** Platform operator (custom claim `operator`). */
  operator: boolean;
}

/** The global fetch, or a fake in tests. */
export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

export interface Deps {
  db: Firestore;
  now: () => Date;
  /** Every outgoing HTTP request goes through this, so tests can fake it. */
  fetch: Fetch;
}

/**
 * Reasons the app can tell apart. They match CloudErrorCode in
 * app/lib/data/backend.dart.
 */
export type Reason =
  | 'churchClosed'
  | 'unverifiedEmail'
  | 'duplicateName'
  | 'inviteInvalid'
  | 'inviteExpired'
  | 'lastAdmin'
  | 'moveInvalid'
  | 'moveTooLarge'
  | 'notFound'
  | 'permissionDenied'
  | 'quotaExceeded'
  | 'unavailable'
  | 'unknown';

export function fail(code: FunctionsErrorCode, reason: Reason, detail?: unknown): never {
  throw new HttpsError(code, reason, { reason, detail: detail ?? null });
}

export function requireCaller(caller: Caller | null): Caller {
  if (!caller) fail('unauthenticated', 'permissionDenied');
  return caller;
}

export function requireOperator(caller: Caller | null): Caller {
  const c = requireCaller(caller);
  if (!c.operator) fail('permission-denied', 'permissionDenied');
  return c;
}

/**
 * A trimmed string of 1 to [max] characters (TEXT_LIMITS, counted as a
 * person counts them), or a failure.
 */
export function text(value: unknown, max: number): string {
  if (typeof value !== 'string') fail('invalid-argument', 'unknown');
  const t = value.trim();
  if (t.length === 0 || !withinTextLimit(t, max)) fail('invalid-argument', 'unknown');
  return t;
}

/**
 * A uid or another document ID the caller names (a pending member). Church
 * IDs have their own, stricter check: churchId() in access.ts.
 */
export function id(value: unknown): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    fail('invalid-argument', 'unknown');
  }
  return value;
}

export const serverTime = () => FieldValue.serverTimestamp();

/** `YYYY-MM-DD` of [date] in Asia/Taipei (UTC+8, the same for HK and MY). */
export function dateKeyUtc8(date: Date): string {
  const shifted = new Date(date.getTime() + 8 * 3600 * 1000);
  return shifted.toISOString().slice(0, 10);
}
