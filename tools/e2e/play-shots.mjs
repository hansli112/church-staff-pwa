// Google Play's phone screenshots (store/screenshots/<locale>-<n>.png): the
// showcase demo the website's videos use (record.mjs has the build), 360×640
// at 3×, in each language, the same four pages as the App Store and the
// website's homepage.
//
//   cd tools/e2e && node play-shots.mjs ../../app/build/web-showcase ../../store/screenshots <next Sunday, 2026-11-15>
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const [webdir, outdir, sunday] = process.argv.slice(2);
if (!sunday) throw new Error('usage: node play-shots.mjs <webdir> <outdir> <next Sunday>');
const types = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf' };
const server = http.createServer((req, res) => {
  let file = path.join(webdir, decodeURIComponent(req.url.split('?')[0]));
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(webdir, 'index.html');
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const base = `http://localhost:${server.address().port}`;

/** Play's locales, as store/<language>.json lists them. */
const LOCALES = ['zh-TW', 'zh-CN', 'en-US', 'ja-JP', 'ko-KR'];
/** 首頁, a 主日崇拜 serving schedule, 行事曆, 安排服事. */
const ROUTES = ['/home', `/rosters/sunday/${sunday}`, '/calendar', '/rosters/plan/sunday'];

const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'] });
fs.mkdirSync(outdir, { recursive: true });
for (const locale of LOCALES) {
  for (const [i, route] of ROUTES.entries()) {
    // A desktop browser's user agent: on a phone's, 首頁 asks to be added to the home screen.
    const context = await browser.newContext({ viewport: { width: 360, height: 640 }, deviceScaleFactor: 3, locale });
    const page = await context.newPage();
    page.on('pageerror', (e) => console.error(`${locale} ${route}: ${e.message}`));
    // Once to bring the fonts into the cache, then again for the picture.
    await page.goto(base + route);
    await page.waitForTimeout(4000);
    await page.goto(base + route);
    await page.waitForTimeout(5000);
    const out = path.join(outdir, `${locale}-${i + 1}.png`);
    await page.screenshot({ path: out });
    console.log(out);
    await context.close();
  }
}
await browser.close();
server.close();
