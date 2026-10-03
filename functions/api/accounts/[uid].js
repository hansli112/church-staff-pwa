// DELETE /api/accounts/:uid — remove a staff member's sign-in (admin only)
//
// The app deletes users/{uid} after this succeeds.

import { ACCOUNTS_LOG_LABEL, deleteSignIn, requireAccountAdmin } from '../../../worker/account_admin.js';
import { authorize } from '../../../worker/authorize.js';
import { handleWith } from '../../../worker/http.js';

export const onRequestDelete = ({ request, env, params }) =>
  handleWith(ACCOUNTS_LOG_LABEL, async () => {
    const caller = await authorize(request, env, { edit: 'accounts' });
    requireAccountAdmin(env);
    await deleteSignIn(env, params?.uid, caller);
    return new Response(null, { status: 204, headers: { 'cache-control': 'no-store' } });
  });
