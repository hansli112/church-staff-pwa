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

/** The time zone every church is shown in (UTC+8, the same for HK and MY). */
export const CHURCH_TIME_ZONE = 'Asia/Taipei';

/** `YYYY-MM-DD` of [date] in Asia/Taipei (UTC+8, the same for HK and MY). */
export function dateKeyUtc8(date: Date): string {
  const shifted = new Date(date.getTime() + 8 * 3600 * 1000);
  return shifted.toISOString().slice(0, 10);
}

/**
 * Runs [steps] side by side, so one failing never stops another, and
 * returns what each gave. A failure is logged under [label] and its step's
 * name; once all have finished the first is thrown, so the invocation
 * still shows as failed.
 */
export async function runEach<T extends Record<string, () => Promise<unknown>>>(
  label: string,
  steps: T,
): Promise<{ [K in keyof T]: Awaited<ReturnType<T[K]>> }> {
  const names = Object.keys(steps);
  const results = await Promise.allSettled(names.map((n) => steps[n]()));
  const failures: unknown[] = [];
  results.forEach((r, i) => {
    if (r.status === 'fulfilled') return;
    console.error(`${label}: ${names[i]} failed`, r.reason);
    failures.push(r.reason);
  });
  if (failures.length) throw failures[0];
  return Object.fromEntries(
    names.map((n, i) => [n, (results[i] as PromiseFulfilledResult<unknown>).value]),
  ) as { [K in keyof T]: Awaited<ReturnType<T[K]>> };
}
