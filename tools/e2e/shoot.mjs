// Usage: node shoot.mjs <webdir> <outdir> <route>[,<route>...] [--dark] [--engine=webkit] [--scale=1]
// Serves a Flutter web build and screenshots each route at iPhone size.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { chromium, webkit } from 'playwright';

const [webdir, outdir, routesArg = '/home', ...flags] = process.argv.slice(2);
const dark = flags.includes('--dark');
const engine = flags.find((f) => f.startsWith('--engine='))?.split('=')[1] ?? 'chromium';
const textScale = Number(flags.find((f) => f.startsWith('--scale='))?.split('=')[1] ?? 1);
const waitMs = Number(flags.find((f) => f.startsWith('--wait='))?.split('=')[1] ?? 2500);
const types = { '.js': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  let file = path.join(webdir, p);
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(webdir, 'index.html');
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const port = server.address().port;
fs.mkdirSync(outdir, { recursive: true });

const browser = await (engine === 'webkit' ? webkit : chromium).launch();
const context = await browser.newContext({
  viewport: { width: 393, height: 852 },
  deviceScaleFactor: 2,
  colorScheme: dark ? 'dark' : 'light',
  locale: 'zh-TW',
});
const page = await context.newPage();
page.on('console', (m) => { if (m.type() === 'error') console.error('console:', m.text()); });
page.on('pageerror', (e) => console.error('pageerror:', e.message));
for (const route of routesArg.split(',')) {
  await page.goto(`http://localhost:${port}${route}`);
  await page.waitForTimeout(waitMs);
  if (textScale !== 1) {
    await page.evaluate((s) => { document.documentElement.style.fontSize = `${16 * s}px`; }, textScale);
  }
  const name = route.replace(/[^a-z0-9]+/gi, '_').replace(/^_|_$/g, '') || 'root';
  const out = path.join(outdir, `${name}${dark ? '_dark' : ''}${engine === 'webkit' ? '_webkit' : ''}.png`);
  await page.screenshot({ path: out });
  console.log(out);
  const pages = Number(flags.find((f) => f.startsWith('--pages='))?.split('=')[1] ?? 1);
  for (let i = 1; i < pages; i++) {
    await page.mouse.move(196, 500);
    await page.mouse.wheel(0, 700);
    await page.waitForTimeout(600);
    const more = out.replace(/\.png$/, `_p${i + 1}.png`);
    await page.screenshot({ path: more });
    console.log(more);
  }
}
await browser.close();
server.close();
