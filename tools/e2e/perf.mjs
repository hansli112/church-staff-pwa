// Times the screens the design doc sets targets for, on a profile web build
// made with PERF_MARKS=true (the app prints `[perf] <name>` after the frame
// that shows a screen):
//
//   cd app && flutter build web --profile --dart-define=MARTHA_ENV=demo \
//     --dart-define=PERF_MARKS=true -o build/web-perf-demo
//   cd tools/e2e && node perf.mjs ../../app/build/web-perf-demo [--engine=webkit] [--runs=3]
//
// The demo build holds the 150-member, one-year sample church in memory,
// so this measures the app and the web engine, not the network.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { chromium, webkit } from 'playwright';

const [webdir, ...flags] = process.argv.slice(2);
const engine = flags.find((f) => f.startsWith('--engine='))?.split('=')[1] ?? 'chromium';
const runs = Number(flags.find((f) => f.startsWith('--runs='))?.split('=')[1] ?? 3);
const types = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf' };
const server = http.createServer((req, res) => {
  let file = path.join(webdir, decodeURIComponent(req.url.split('?')[0]));
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(webdir, 'index.html');
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const base = `http://localhost:${server.address().port}`;
const browser = await (engine === 'webkit' ? webkit : chromium).launch();

function waitMark(page, name, timeout = 30000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`no [perf] ${name}`)), timeout);
    const onConsole = (m) => {
      if (m.text() === `[perf] ${name}`) {
        clearTimeout(timer);
        page.off('console', onConsole);
        resolve(performance.now());
      }
    };
    page.on('console', onConsole);
  });
}

async function fps(page) {
  await page.mouse.move(196, 450);
  await page.evaluate(() => {
    window.__frames = [];
    const tick = (t) => {
      window.__frames.push(t);
      if (window.__frames.length < 1000) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
  const t0 = await page.evaluate(() => performance.now());
  for (let i = 0; i < 30; i++) {
    await page.mouse.wheel(0, i < 15 ? 260 : -260);
    await page.waitForTimeout(66);
  }
  return page.evaluate((start) => {
    const f = window.__frames.filter((t) => t >= start);
    const gaps = f.slice(1).map((t, i) => t - f[i]);
    const span = (f.at(-1) - f[0]) / 1000;
    const longest = Math.max(...gaps);
    const janky = gaps.filter((g) => g > 1000 / 50).length;
    return { fps: Math.round((f.length - 1) / span), longestFrameMs: Math.round(longest), framesOver20ms: janky };
  }, t0);
}

const results = [];
for (let run = 0; run < runs; run++) {
  const context = await browser.newContext({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 3, locale: 'zh-TW' });
  const page = await context.newPage();
  const r = {};

  const t0 = performance.now();
  const visible = waitMark(page, 'roster-visible', 60000);
  await page.goto(`${base}/rosters`);
  r.coldStartToRosterMs = Math.round((await visible) - t0);
  await page.waitForTimeout(800);

  // Tab switch to 首頁 (first visit builds it).
  const t1 = performance.now();
  const home = waitMark(page, 'home-visible');
  await page.mouse.click(49, 820);
  r.tabSwitchMs = Math.round((await home) - t1);
  await page.waitForTimeout(500);

  // Back to the roster tab, open the first day, open the picker.
  await page.mouse.click(147, 820);
  await page.waitForTimeout(600);
  r.scroll = await fps(page);
  await page.goto(`${base}/rosters`);
  await waitMark(page, 'roster-visible', 60000).catch(() => {});
  await page.waitForTimeout(800);
  await page.mouse.click(196, 128);
  await page.waitForTimeout(1200);
  if (process.env.PERF_DEBUG) await page.screenshot({ path: 'out/perf-day.png' });
  const t2 = performance.now();
  const picker = waitMark(page, 'picker-visible');
  await page.mouse.click(50, 157); // the duty label, not a name chip
  r.pickerOpenMs = Math.round((await picker) - t2);

  results.push(r);
  await context.close();
}
await browser.close();
server.close();

const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];
const summary = {
  engine,
  runs,
  coldStartToRosterMs: median(results.map((r) => r.coldStartToRosterMs)),
  tabSwitchMs: median(results.map((r) => r.tabSwitchMs)),
  pickerOpenMs: median(results.map((r) => r.pickerOpenMs)),
  scrollFps: median(results.map((r) => r.scroll.fps)),
  scrollLongestFrameMs: median(results.map((r) => r.scroll.longestFrameMs)),
  scrollFramesOver20ms: median(results.map((r) => r.scroll.framesOver20ms)),
};
console.log(JSON.stringify({ summary, results }, null, 1));
