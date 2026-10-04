// Smoke test of the emulator web build against the Firebase
// emulators: Google sign-in (auth emulator popup), create church (Cloud
// Function), edit a roster (Firestore), invite + join as a second user.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const webdir = process.argv[2];
const out = process.argv[3] ?? 'e2e';
fs.mkdirSync(out, { recursive: true });
const types = { '.js': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf' };
const server = http.createServer((req, res) => {
  let file = path.join(webdir, decodeURIComponent(req.url.split('?')[0]));
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(webdir, 'index.html');
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(5055, r));
const base = 'http://localhost:5055';

const browser = await chromium.launch();
const errors = [];
let step = 0;

async function newUser(email, name) {
  const context = await browser.newContext({ viewport: { width: 393, height: 852 }, locale: 'zh-TW' });
  // The emulator's warning banner sits over the tab bar.
  await context.addInitScript(() => {
    document.addEventListener('DOMContentLoaded', () => {
      const s = document.createElement('style');
      s.textContent = '.firebase-emulator-warning{display:none!important}';
      document.head.appendChild(s);
    });
  });
  const page = await context.newPage();
  page.on('pageerror', (e) => errors.push(`${email}: ${e.message}`));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`${email} console: ${m.text()}`); });
  return { context, page, email, name };
}

async function shot(page, label) {
  step++;
  await page.screenshot({ path: path.join(out, `${String(step).padStart(2, '0')}-${label}.png`) });
}

const button = (page, name) => page.getByRole('button', { name, exact: false }).or(page.getByRole('tab', { name, exact: false })).last();

async function googleSignIn({ page, email, name }) {
  const [popup] = await Promise.all([
    page.waitForEvent('popup'),
    button(page, '使用 Google 登入').click(),
  ]);
  await popup.waitForLoadState();
  await popup.getByText('Add new account').click();
  await popup.locator('#email-input').fill(email);
  await popup.locator('#display-name-input').fill(name);
  await popup.getByText('Sign in with Google.com').click();
  await page.waitForTimeout(2500);
}

await fetch('http://localhost:8181/emulator/v1/projects/demo-martha/databases/(default)/documents', { method: 'DELETE' });
await fetch('http://localhost:9199/emulator/v1/projects/demo-martha/accounts', { method: 'DELETE' });

try {
  const alice = await newUser('alice@gmail.com', '愛麗絲');
  await alice.page.goto(`${base}/`);
  await alice.page.waitForTimeout(4000);
  await shot(alice.page, 'login');
  await googleSignIn(alice);
  await shot(alice.page, 'welcome');

  await button(alice.page, '建立新教會').click();
  await alice.page.waitForTimeout(800);
  await alice.page.getByRole('textbox').first().fill('E2E 恩典堂');
  await alice.page.waitForTimeout(300);
  await button(alice.page, '建立').click();
  await alice.page.waitForTimeout(4000);
  await shot(alice.page, 'home-after-create');

  await button(alice.page, '服事表').click();
  await alice.page.waitForTimeout(2000);
  await shot(alice.page, 'rosters');

  // Open the first day and set 司會.
  await alice.page.getByRole('button', { name: /10月/ }).first().click();
  await alice.page.waitForTimeout(1500);
  await shot(alice.page, 'day');
  await button(alice.page, '司會').click();
  await alice.page.waitForTimeout(1200);
  await alice.page.getByRole('textbox').first().fill('外請講員');
  await alice.page.waitForTimeout(600);
  await button(alice.page, '用「外請講員」').click();
  await alice.page.waitForTimeout(400);
  await button(alice.page, '完成').click();
  await alice.page.waitForTimeout(2500);
  await shot(alice.page, 'day-after-edit');

  // Invite.
  await button(alice.page, '我的').click();
  await alice.page.waitForTimeout(1500);
  await button(alice.page, '教會資訊').click();
  await alice.page.waitForTimeout(1500);
  await button(alice.page, '邀請').click();
  await alice.page.waitForTimeout(2000);
  await shot(alice.page, 'invites-page');
  await button(alice.page, '7 天').click();
  await alice.page.waitForTimeout(3000);
  await shot(alice.page, 'invite-created');
  const invite = await alice.page.evaluate(async () => {
    const res = await fetch('http://localhost:8181/v1/projects/demo-martha/databases/(default)/documents/invites', {
      headers: { Authorization: 'Bearer owner' },
    });
    const json = await res.json();
    const d = json.documents?.[0];
    return { code: d?.name?.split('/').pop(), cid: d?.fields?.cid?.stringValue };
  });
  console.log('invite', invite);

  const bob = await newUser('bob@gmail.com', '鮑伯');
  await bob.page.goto(`${base}/c/${invite.cid}/join/${invite.code}`);
  await bob.page.waitForTimeout(4000);
  await shot(bob.page, 'bob-login');
  await googleSignIn(bob);
  await bob.page.waitForTimeout(2000);
  await shot(bob.page, 'bob-join');
  await button(bob.page, '加入').click();
  await bob.page.waitForTimeout(4000);
  await shot(bob.page, 'bob-home');
  await button(bob.page, '服事表').click();
  await bob.page.waitForTimeout(2500);
  await shot(bob.page, 'bob-rosters');
  const sees = await bob.page.getByText('外請講員').count();
  console.log('bob sees the edit:', sees > 0);
} catch (e) {
  console.error('E2E failed:', e.message);
  process.exitCode = 1;
} finally {
  console.log('errors:', errors.length ? errors.join('\n') : 'none');
  await browser.close();
  server.close();
}
