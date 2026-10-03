// Firebase Auth sign-ins, created and removed on an admin's behalf.
//
// Why a server at all: the browser SDK can create a sign-in but never remove
// someone else's. Deleting a staff member used to delete only users/{uid}, the
// sign-in stayed, and adding the same email again failed with nothing the
// admin could do about it in the app. Here a service account limited to
// Firebase Authentication (ACCOUNT_ADMIN_KEY, set up by the installer) does
// both halves.
//
// users/{uid} stays the app's to write: this file only touches sign-ins, and
// firestore.rules keeps deciding who may change profiles. The one profile read
// here goes out with the caller's own token.

import { HttpError, readDocument, requireEnv } from './firebase_user.js';
import { serviceAccountToken } from './service_account.js';

export const ACCOUNTS_LOG_LABEL = 'accounts function failed';

const SECRET = 'ACCOUNT_ADMIN_KEY';
// The account's only role is Firebase Authentication Admin, which is what
// actually limits it; the scope just has to let that role through.
const SCOPE = 'https://www.googleapis.com/auth/cloud-platform';
const AUTH_API = 'https://identitytoolkit.googleapis.com/v1';
const UPSTREAM_TIMEOUT_MS = 10000;

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
// Uids the app and the installer create: Firebase's 28 characters, or
// install-<hex>. Anything else cannot be one of ours and never reaches Google.
const UID = /^[A-Za-z0-9_-]{1,128}$/;

/// Sites set up before account management, or deployed by hand without the
/// secret, answer 501 so the app falls back to what it did before.
export function requireAccountAdmin(env) {
  const value = env?.[SECRET];
  if (typeof value !== 'string' || value.trim() === '') {
    throw new HttpError(501, '這個網站還沒有設定帳號管理');
  }
}

/// POSTs to accounts[suffix] as the service account. Returns `{ data }` on
/// success, `{ reason }` with Google's error code (EMAIL_EXISTS, …) otherwise.
async function callAuth(env, suffix, body, fetchImpl) {
  const token = await serviceAccountToken(env, {
    secret: SECRET,
    scope: SCOPE,
    unreachable: '無法連上帳號服務，請稍後再試',
  }, fetchImpl);
  const projectId = requireEnv(env, 'FIREBASE_PROJECT_ID');
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  let response;
  try {
    response = await fetchImpl(
      `${AUTH_API}/projects/${encodeURIComponent(projectId)}/accounts${suffix}`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'content-type': 'application/json' },
        body: JSON.stringify(body),
        signal: controller.signal,
      },
    );
  } catch (error) {
    console.error('auth request failed', suffix, error);
    throw new HttpError(502, '無法連上帳號服務，請稍後再試');
  } finally {
    clearTimeout(timer);
  }
  let data = {};
  try {
    data = await response.json();
  } catch {
    // Reported below by status.
  }
  if (response.ok) return { data };
  // "WEAK_PASSWORD : Password should be at least 6 characters" → WEAK_PASSWORD
  const reason = String(data?.error?.message ?? '').split(/[\s:]/)[0];
  if (response.status === 401 || response.status === 403) {
    // A grant still spreading (minutes after install), or a key that was
    // revoked or lost its role: not something the admin typed wrong.
    console.error('auth request refused', suffix, response.status, reason);
    throw new HttpError(500, '帳號管理暫時無法使用。剛裝好的網站請過幾分鐘再試；一直不行的話，請用安裝精靈「更新網站」一次');
  }
  return { reason, status: response.status };
}

function signInFields(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new HttpError(400, '資料格式不正確');
  }
  const email = typeof body.email === 'string' ? body.email.trim() : '';
  if (!EMAIL.test(email) || email.length > 254) throw new HttpError(400, 'Email 格式不正確');
  const password = typeof body.password === 'string' ? body.password : '';
  if (password.length < 6) throw new HttpError(400, '密碼至少要 6 個字元');
  if (password.length > 128) throw new HttpError(400, '密碼太長了，請少於 128 個字元');
  const name = typeof body.name === 'string' ? body.name.trim().slice(0, 100) : '';
  return { email, password, name };
}

function failure(reason, status, action) {
  if (reason === 'WEAK_PASSWORD') return new HttpError(400, '密碼至少要 6 個字元');
  if (reason === 'INVALID_EMAIL') return new HttpError(400, 'Email 格式不正確');
  console.error(`${action} failed`, status, reason);
  return new HttpError(502, `${action}失敗，請稍後再試`);
}

function profileName(document) {
  const value = document?.fields?.name?.stringValue;
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

/// Creates the sign-in for a new staff member and returns its uid.
///
/// When the email already has a sign-in that no staff profile uses — what a
/// delete left behind before this existed — that sign-in is taken over: the
/// admin's new password replaces the old one and every session it had is
/// ended, so whoever knew the old password is out. A sign-in that belongs to
/// an existing profile is refused instead; that is a duplicate, not leftovers.
export async function createSignIn(env, body, caller, fetchImpl = fetch) {
  const { email, password, name } = signInFields(body);
  const created = await callAuth(env, '', {
    email,
    password,
    ...(name ? { displayName: name } : {}),
  }, fetchImpl);
  if (created.data) {
    if (!UID.test(created.data.localId ?? '')) throw new HttpError(502, '建立登入帳號失敗，請稍後再試');
    return { uid: created.data.localId, reused: false };
  }
  if (created.reason !== 'EMAIL_EXISTS') throw failure(created.reason, created.status, '建立登入帳號');

  const found = await callAuth(env, ':lookup', { email: [email] }, fetchImpl);
  const uid = found.data?.users?.[0]?.localId;
  if (typeof uid !== 'string' || !UID.test(uid)) throw failure(found.reason, found.status, '查詢登入帳號');
  const profile = await readDocument(env, `users/${encodeURIComponent(uid)}`, caller.token, fetchImpl);
  if (profile) {
    const owner = profileName(profile);
    throw new HttpError(409, owner ? `這個 Email 已經是「${owner}」的帳號` : '這個 Email 已經有同工在用了');
  }
  const updated = await callAuth(env, ':update', {
    localId: uid,
    password,
    ...(name ? { displayName: name } : {}),
    disableUser: false,
    // Sessions from before this moment stop working.
    validSince: String(Math.floor(Date.now() / 1000)),
  }, fetchImpl);
  if (!updated.data) throw failure(updated.reason, updated.status, '重設登入帳號');
  return { uid, reused: true };
}

/// Removes a staff member's sign-in. One that is already gone counts as done,
/// so an admin can retry a delete whose profile half failed.
export async function deleteSignIn(env, uid, caller, fetchImpl = fetch) {
  if (typeof uid !== 'string' || !UID.test(uid)) throw new HttpError(400, '找不到這個帳號');
  // Same as firestore.rules: an admin removing themselves leaves no one in charge.
  if (uid === caller.uid) throw new HttpError(403, '不能刪除自己的帳號。要刪的話，請另一位管理員幫你刪。');
  const result = await callAuth(env, ':delete', { localId: uid }, fetchImpl);
  if (result.data || result.reason === 'USER_NOT_FOUND') return;
  throw failure(result.reason, result.status, '刪除登入帳號');
}
