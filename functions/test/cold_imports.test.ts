import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

/** A fresh process imports the deployed entry point, never invokes a function. */
function coldImports() {
  const child = spawnSync(process.execPath, ['--import', 'tsx', '--input-type=module', '--eval', `
    import { createRequire } from 'node:module';
    globalThis.fetch = async () => { throw new Error('No network in cold-import tests'); };
    const functions = await import('./src/index.ts');
    const paths = Object.keys(createRequire(import.meta.url).cache);
    console.log(JSON.stringify({
      functions: Object.keys(functions),
      secrets: Object.fromEntries(Object.entries(functions).map(([name, f]) =>
        [name, (f.__endpoint?.secretEnvironmentVariables ?? []).map((s) => s.key).sort()])),
      apple: paths.some((path) => path.includes('/@apple/app-store-server-library/')),
      sharp: paths.some((path) => path.includes('/sharp/')),
    }));
  `], {
    cwd: fileURLToPath(new URL('..', import.meta.url)),
    env: {
      PATH: process.env.PATH,
      TMPDIR: process.env.TMPDIR,
      GCLOUD_PROJECT: 'demo-martha',
      FIREBASE_CONFIG: JSON.stringify({ projectId: 'demo-martha', storageBucket: 'demo-martha.appspot.com' }),
    },
    encoding: 'utf8',
    timeout: 15_000,
  });
  assert.equal(child.status, 0, child.stderr);
  return JSON.parse(child.stdout) as { functions: string[]; secrets: Record<string, string[]>; apple: boolean; sharp: boolean };
}

test('ordinary Functions do not load Apple payment verification on cold import', () => {
  const loaded = coldImports();
  assert.ok(loaded.functions.includes('appStoreNotifications'), 'the payment function is still declared');
  assert.equal(loaded.apple, false);
});

test('ordinary Functions do not load logo processing on cold import', () => {
  const loaded = coldImports();
  assert.ok(loaded.functions.includes('onLogoUploaded'), 'the logo function is still declared');
  assert.equal(loaded.sharp, false);
});

test('each function lists the secrets its dependencies read, and no others', () => {
  const { secrets } = coldImports();
  const calendar = ['CALENDAR_TOKEN_KEY', 'GOOGLE_OAUTH_CLIENT_ID', 'GOOGLE_OAUTH_CLIENT_SECRET'];
  const webhook = ['CALENDAR_TOKEN_KEY'];
  const ecpay = ['ECPAY_HASH_IV', 'ECPAY_HASH_KEY'];
  assert.deepEqual(Object.fromEntries(Object.entries(secrets).filter(([, s]) => s.length)), {
    setChurchTimeZone: calendar,
    purgeDeletedChurches: calendar,
    webhookSave: webhook,
    webhookRotateSecret: webhook,
    webhookTest: webhook,
    ecpayStart: ecpay,
    ecpayNotify: ecpay,
    onMemberDeleted: calendar,
    onMemberDemoted: calendar,
    onEventRosterCreated: calendar,
    sendRosterChanges: webhook,
    syncEventRosters: calendar,
    calendarAuthUrl: calendar,
    calendarList: calendar,
    calendarSelect: calendar,
    calendarDisconnect: calendar,
    calendarEvents: calendar,
    calendarWrite: calendar,
    calendarCallback: calendar,
  });
});

test('a warm-up call is answered at once, reading and checking nothing', () => {
  const child = spawnSync(process.execPath, ['--import', 'tsx', '--input-type=module', '--eval', `
    globalThis.fetch = async () => { throw new Error('No network in cold-import tests'); };
    const functions = await import('./src/index.ts');
    const answers = {};
    for (const name of ['calendarWrite', 'editService', 'redeemInvite', 'createChurch']) {
      answers[name] = await functions[name].run({ data: { warmup: true } });
    }
    let refused = false;
    try { await functions.redeemInvite.run({ data: { warmup: 'yes' } }); } catch { refused = true; }
    console.log(JSON.stringify({ answers, refused }));
  `], {
    cwd: fileURLToPath(new URL('..', import.meta.url)),
    env: {
      PATH: process.env.PATH,
      TMPDIR: process.env.TMPDIR,
      GCLOUD_PROJECT: 'demo-martha',
      FIREBASE_CONFIG: JSON.stringify({ projectId: 'demo-martha', storageBucket: 'demo-martha.appspot.com' }),
    },
    encoding: 'utf8',
    timeout: 15_000,
  });
  assert.equal(child.status, 0, child.stderr);
  const { answers, refused } = JSON.parse(child.stdout.trim().split('\n').at(-1)!);
  for (const answer of Object.values(answers)) assert.deepEqual(answer, { warm: true });
  assert.equal(refused, true, 'anything else is an ordinary call, which needs a signed-in caller');
});
