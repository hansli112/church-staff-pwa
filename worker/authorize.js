// May this caller do this — the one place the worker decides.
//
// Every Pages Function that writes on someone's behalf asks here, naming the
// action, and gets back the caller or an HttpError the app shows as is.
// firebase_user.js only finds out who is calling; what that person may do is
// decided below and nowhere else in worker/ or functions/.
//
// The same rules exist two more times, on purpose: firestore.rules (the real
// line for everything the app writes to Firestore directly) and User in the
// Flutter app (which only decides what the UI offers). The group names, the
// zone rule and "admin is root" must agree across all three.

import { HttpError, identifyCaller } from './firebase_user.js';
import { churchConfig } from './church_config.js';

/// Kept in sync with ServiceType in the Flutter app, the keys of
/// settings/roster_templates and hasValidZoneTypes in firestore.rules.
///
/// Lives here rather than with request parsing because the type *is* the thing
/// being authorized — zoneTypes on a user are drawn from the same list. A type
/// outside it is refused for everyone, admin included.
// Keep disabled services too: existing records and their zone grants survive
// hiding a service in the UI. Unknown IDs never inherit another service's grant.

/// What each action needs. The group names are part of the data format (they
/// are what users/{uid}.groups stores) and match inGroup() in firestore.rules
/// and UserGroup in the app.
///
/// [denied] names the specific thing the caller cannot do — the only part of
/// a 403 someone can act on.
const ACTIONS = {
  calendar: { group: 'calendar-editors', denied: '沒有編輯行事曆的權限' },
  roster: { group: 'roster-editors', denied: '沒有編輯服事表的權限' },
};

/// Rejects a caller who may not perform [action].
///
/// `{ edit: 'calendar' }` returns `{ uid, name, token }`.
///
/// `{ edit: 'roster' }` returns `{ uid, name, forRosterType(type) }`. The group
/// only says "may edit rosters"; which roster is in the request body, and the
/// body is not worth parsing — up to 4MB against a 10ms CPU budget — for
/// someone who is not even in the group. So the check comes in two halves:
/// this call settles who the caller is and the group, [forRosterType] settles
/// the type once the body has been read. It is also the only way to the token,
/// and every roster route needs the token for its Firestore reads — a handler
/// cannot skip the zone check and still work.
///
/// The name comes back because the user document already had to be read for
/// the check, and the LINE notification wants a person, not a uid. The token
/// comes back because every later Firestore read goes out as the caller.
export async function authorize(request, env, action, fetchImpl = fetch) {
  const rule = ACTIONS[action?.edit];
  if (!rule) throw new Error(`unknown action ${JSON.stringify(action)}`);

  const rosterTypes = new Set(churchConfig(env).services.map((service) => service.id));
  const caller = await identifyCaller(request, env, fetchImpl);
  // admin is root: every group, every zone, without holding either.
  const isAdmin = caller.role === 'admin';
  if (!isAdmin && !caller.groups.includes(rule.group)) {
    throw new HttpError(403, rule.denied);
  }

  const { uid, name, token } = caller;
  if (action.edit !== 'roster') return { uid, name, token };
  return {
    uid,
    name,
    /// The caller's token, if they may edit the roster of [type] — the same
    /// split canEditRosterType() makes in firestore.rules. Without it a 青崇
    /// editor could not write 主日, but could still spend the recognition
    /// quota on it.
    forRosterType(type) {
      if (!rosterTypes.has(type)) {
        throw new HttpError(400, '不知道這是哪一個崇拜的服事表');
      }
      if (!isAdmin && !caller.zoneTypes.includes(type)) {
        throw new HttpError(403, '沒有編輯這個崇拜服事表的權限');
      }
      return token;
    },
  };
}
