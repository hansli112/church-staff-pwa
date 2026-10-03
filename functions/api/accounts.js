// POST /api/accounts — create a staff member's sign-in (admin only)
//
// Answers { uid, reused }. The app then writes users/{uid} itself, under
// firestore.rules; see worker/account_admin.js for why this half is here.

import { ACCOUNTS_LOG_LABEL, createSignIn, requireAccountAdmin } from '../../worker/account_admin.js';
import { authorize } from '../../worker/authorize.js';
import { handleWith, jsonResponse, readJsonBody } from '../../worker/http.js';

export const onRequestPost = ({ request, env }) =>
  handleWith(ACCOUNTS_LOG_LABEL, async () => {
    const caller = await authorize(request, env, { edit: 'accounts' });
    requireAccountAdmin(env);
    return jsonResponse(await createSignIn(env, await readJsonBody(request), caller), 201);
  });
