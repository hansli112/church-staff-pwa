// Checks the web build fetches its Chinese fonts as it starts, not when a
// word first shows: on 邀請, 建立邀請連結's toast (已複製邀請連結, whose 複
// nothing else on the page has) must not send for a font file. Chromium
// runs the wasm build, as Chrome and Android do; WebKit the JS one, as
// Safari does. The engines ask for fonts at different steps, so each is
// checked.
//
//   cd app && flutter build web --wasm --dart-define=MARTHA_ENV=demo \
//     --dart-define=E2E=true -o build/web-demo
//   cd tools/e2e && node fonts.mjs ../../app/build/web-demo
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { chromium, webkit } from 'playwright';

const webdir = process.argv[2];
const words = JSON.parse(fs.readFileSync(path.join(path.dirname(new URL(import.meta.url).pathname), '../../app/lib/l10n/app_zh.arb'), 'utf8'));

const types = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf' };
const server = http.createServer((req, res) => {
  let file = path.join(webdir, decodeURIComponent(req.url.split('?')[0]));
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(webdir, 'index.html');
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const base = `http://localhost:${server.address().port}`;

const ENGINES = [
  // Software WebGL: without it Chromium falls back from the wasm build to JS.
  { name: 'chromium (wasm)', type: chromium, args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'], wasm: true },
  { name: 'webkit (js)', type: webkit, args: [], wasm: false },
];

let failed = false;
for (const engine of ENGINES) {
  const browser = await engine.type.launch({ args: engine.args });
  const context = await browser.newContext({ viewport: { width: 393, height: 852 }, locale: 'zh-TW' });
  // 建立邀請連結 shares the link, or copies it where there is no share
  // sheet; neither leaves the page here.
  await context.addInitScript(() => {
    delete Navigator.prototype.share;
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: async () => {} } });
  });
  const page = await context.newPage();
  const fonts = [];
  let ranWasm = false;
  page.on('request', (r) => {
    if (r.url().includes('fonts.gstatic.com')) fonts.push(r.url());
    if (r.url().endsWith('.wasm') && r.url().includes('main.dart')) ranWasm = true;
  });
  /** Until no font file has been asked for in a while. */
  const settle = async () => {
    for (let seen = -1; seen !== fonts.length; ) {
      seen = fonts.length;
      await page.waitForTimeout(2500);
    }
  };
  const fail = (why) => {
    failed = true;
    console.error(`✗ ${engine.name}: ${why}`);
  };
  try {
    await page.goto(`${base}/me/invites`);
    await page.getByRole('button', { name: words.inviteCreate, exact: true }).waitFor({ timeout: 30000 });
    await settle();
    const before = fonts.length;
    // Through its accessibility node: a tap where WebKit draws it is lost.
    await page.getByRole('button', { name: words.inviteCreate, exact: true }).dispatchEvent('click');
    await page.getByText(words.inviteCopied).first().waitFor({ timeout: 10000 });
    await settle();
    if (engine.wasm && !ranWasm) fail('ran the JS build, not the wasm one');
    else if (before === 0) fail('asked for no font files at all');
    else if (fonts.length > before) fail(`the toast asked for ${fonts.slice(before).join(', ')}`);
    else console.log(`✓ ${engine.name}: ${before} font files as it started, none for the toast`);
  } catch (e) {
    fail(e.message.split('\n')[0]);
  }
  await browser.close();
}
server.close();
if (failed) process.exit(1);
