import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const read = (path) => readFileSync(join(root, path), 'utf8');

test('iPhone and Android open the same links in the app', () => {
  const ios = [...read('app/ios/Runner/Runner.entitlements').matchAll(/<string>applinks:([^<]+)<\/string>/g)].map((m) => m[1]);
  const android = [...read('app/android/app/src/main/AndroidManifest.xml').matchAll(/android:host="([^"]+)" android:pathPrefix="\/c\/"/g)].map((m) => m[1]);
  assert.ok(ios.length > 0);
  assert.deepEqual(ios.sort(), android.sort());
});

test('the site lets the iPhone app open church URLs, and serves that as JSON', () => {
  const { applinks } = JSON.parse(read('app/web/.well-known/apple-app-site-association'));
  assert.deepEqual(applinks.details, [{ appIDs: ['VFF5B33QVD.app.marthasit'], components: [{ '/': '/c/*' }] }]);
  const { hosting } = JSON.parse(read('firebase.json'));
  const rule = hosting.headers.find((r) => r.source === '/.well-known/apple-app-site-association');
  assert.deepEqual(rule?.headers, [{ key: 'Content-Type', value: 'application/json' }]);
});
