import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { HttpsError, type FunctionsErrorCode } from 'firebase-functions/v2/https';

/** Region for every function, the same as Firestore. */
export const REGION = 'asia-east1';

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
  | 'unverifiedEmail'
  | 'duplicateName'
  | 'inviteInvalid'
  | 'inviteExpired'
  | 'lastAdmin'
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

/** A trimmed string between 1 and [max] characters, or a failure. */
export function text(value: unknown, max: number): string {
  if (typeof value !== 'string') fail('invalid-argument', 'unknown');
  const t = value.trim();
  if (t.length === 0 || t.length > max) fail('invalid-argument', 'unknown');
  return t;
}

export function id(value: unknown): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    fail('invalid-argument', 'unknown');
  }
  return value;
}

/** Requires [caller] to be an admin of the church, whatever its status. */
export async function requireChurchAdmin(db: Firestore, cid: string, caller: Caller) {
  const member = await db.doc(`churches/${cid}/members/${caller.uid}`).get();
  if (member.get('role') !== 'admin') fail('permission-denied', 'permissionDenied');
}

export const serverTime = () => FieldValue.serverTimestamp();

/** `YYYY-MM-DD` of [date] in Asia/Taipei (UTC+8, the same for HK and MY). */
export function dateKeyUtc8(date: Date): string {
  const shifted = new Date(date.getTime() + 8 * 3600 * 1000);
  return shifted.toISOString().slice(0, 10);
}
