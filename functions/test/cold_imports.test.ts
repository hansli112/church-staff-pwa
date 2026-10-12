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
  assert.deepEqual(secrets.calendarWrite, calendar);
  assert.deepEqual(secrets.setChurchTimeZone, calendar);
  assert.deepEqual(secrets.syncEventRosters, calendar);
  assert.deepEqual(secrets.webhookSave, ['CALENDAR_TOKEN_KEY']);
  assert.deepEqual(secrets.sendRosterChanges, ['CALENDAR_TOKEN_KEY']);
  assert.deepEqual(secrets.newebpayNotify, ['NEWEBPAY_HASH_IV', 'NEWEBPAY_HASH_KEY']);
  assert.deepEqual(secrets.createChurch, []);
});
