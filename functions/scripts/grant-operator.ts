// Gives (or with --revoke, removes) the platform operator claim, which opens
// the back office. Uses Application Default Credentials.
//
//   npx tsx scripts/grant-operator.ts --project martha-app-dev you@gmail.com
//
// The user must sign out and in again (or wait for the token to refresh,
// up to an hour) before the claim takes effect.
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const args = process.argv.slice(2);
const project = args[args.indexOf('--project') + 1];
const email = args.filter((a) => a.includes('@')).at(-1);
const revoke = args.includes('--revoke');
if (!args.includes('--project') || !project || !email) throw new Error('Usage: --project <id> [--revoke] <email>');

initializeApp({ projectId: project });
const auth = getAuth();
const user = await auth.getUserByEmail(email);
const claims = { ...(user.customClaims ?? {}) };
if (revoke) delete claims.operator;
else claims.operator = true;
await auth.setCustomUserClaims(user.uid, claims);
console.log(`${revoke ? 'Removed' : 'Granted'} operator for ${email} (${user.uid}) in ${project}.`);
