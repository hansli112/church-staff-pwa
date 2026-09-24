// The small HTTP shapes every Pages Function here needs.
//
// Split out when /api/roster/ appeared: the bodies were generic already, but
// the error log line said "calendar function failed" no matter who failed,
// which is the kind of thing that sends you reading the wrong file at the wrong
// hour.

import { HttpError } from './firebase_user.js';

export function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      // These are private, admin-only responses; no intermediary should keep them.
      'cache-control': 'no-store',
    },
  });
}

export function errorResponse(error) {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }
  return jsonResponse({ error: '操作失敗，請稍後再試' }, 500);
}

/// Wraps a handler so thrown HttpErrors become responses instead of 500s.
///
/// [label] names the route in the log line for anything that was *not* a
/// deliberate HttpError — those are the ones nobody anticipated, so the log has
/// to say which route produced them.
export async function handleWith(label, fn) {
  try {
    return await fn();
  } catch (error) {
    if (!(error instanceof HttpError)) {
      console.error(label, error);
    }
    return errorResponse(error);
  }
}

export async function readJsonBody(request) {
  try {
    return await request.json();
  } catch {
    throw new HttpError(400, '資料格式不正確');
  }
}
