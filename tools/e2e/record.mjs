// Records the website's videos (landing/media/<language>/<clip>.mp4 and a
// .jpg of its first frame): short clips of the showcase demo, a church
// settled in, at iPhone size, each a few taps with a dot where the finger
// goes.
//
//   cd app && flutter build web --wasm --dart-define=MARTHA_ENV=demo \
//     --dart-define=DEMO_SHOWCASE=true --dart-define=E2E=true -o build/web-showcase
//   cd tools/e2e && node record.mjs ../../app/build/web-showcase ../../landing/media [--only=plan,swap] [--lang=en]
//
// Each clip finds what it taps by what the app says, in the language it
// records (the app's ARB files), and the demo church's own words by their
// place, so one script records every language.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { chromium } from 'playwright';

const [webdir, outdir, ...flags] = process.argv.slice(2);
const flag = (name) => flags.find((f) => f.startsWith(`--${name}=`))?.split('=')[1]?.split(',');
const arbDir = path.join(path.dirname(new URL(import.meta.url).pathname), '../../app/lib/l10n');

/** The website's languages: the browser's locale, the app's strings. */
const LANGUAGES = {
  'zh-Hant': { locale: 'zh-TW', arb: 'app_zh.arb' },
  'zh-Hans': { locale: 'zh-CN', arb: 'app_zh_Hans.arb' },
  en: { locale: 'en-US', arb: 'app_en.arb' },
  ja: { locale: 'ja-JP', arb: 'app_ja.arb' },
  ko: { locale: 'ko-KR', arb: 'app_ko.arb' },
};

const types = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf' };
const server = http.createServer((req, res) => {
  let file = path.join(webdir, decodeURIComponent(req.url.split('?')[0]));
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(webdir, 'index.html');
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const base = `http://localhost:${server.address().port}`;

// A dot where the finger touches, drawn over the app (which ignores it).
const FINGER = () => {
  addEventListener('DOMContentLoaded', () => {
    const dot = document.createElement('div');
    dot.id = 'finger';
    dot.style.cssText = 'position:fixed;z-index:99999;pointer-events:none;width:44px;height:44px;margin:-22px 0 0 -22px;border-radius:50%;background:rgba(120,120,128,.35);border:2px solid rgba(255,255,255,.9);box-shadow:0 1px 6px rgba(0,0,0,.25);opacity:0;transform:scale(.6);transition:opacity .15s,transform .15s';
    document.body.appendChild(dot);
  });
};

/** One language's session: taps, waits and the app's words. */
function session(page, words) {
  const t = (key) => {
    const s = words[key];
    if (typeof s !== 'string') throw new Error(`no string ${key}`);
    return s;
  };
  const finger = (x, y, down) =>
    page.evaluate(([x, y, down]) => {
      const dot = document.getElementById('finger');
      dot.style.left = `${x}px`;
      dot.style.top = `${y}px`;
      dot.style.opacity = down ? '1' : '0';
      dot.style.transform = down ? 'scale(1)' : 'scale(.6)';
    }, [x, y, down]);
  const center = async (locator) => {
    await locator.waitFor({ state: 'attached' });
    const box = await locator.boundingBox();
    if (!box) throw new Error(`not on screen: ${locator}`);
    return [box.x + box.width / 2, box.y + box.height / 2];
  };
  const wait = (ms) => page.waitForTimeout(ms);
  const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const named = (name, role) =>
    page.getByRole(role, { name: name.startsWith('^') ? new RegExp(`^${escape(name.slice(1))}`) : name, exact: true });
  return {
    t,
    wait,
    /** Flutter's accessibility node named [name] (a prefix with `^`). */
    node: (name, role = 'button') => named(name, role).first(),
    nodes: (prefix, role = 'button') => named(`^${prefix}`, role),
    /** Taps [target], a node or [x, y]; [dy] moves it down (up when negative). */
    async tap(target, { hold = 120, dy = 0 } = {}) {
      const [x, y0] = Array.isArray(target) ? target : await center(target);
      const y = y0 + dy;
      await page.mouse.move(x, y);
      await finger(x, y, true);
      await wait(180);
      await page.mouse.down();
      await wait(hold);
      await page.mouse.up();
      await wait(120);
      await finger(x, y, false);
    },
    async drag(from, to, { hold = 600, steps = 24 } = {}) {
      const [x0, y0] = await center(from);
      const [x1, y1] = await center(to);
      await page.mouse.move(x0, y0);
      await finger(x0, y0, true);
      await page.mouse.down();
      await wait(hold);
      for (let i = 1; i <= steps; i++) {
        const x = x0 + ((x1 - x0) * i) / steps;
        const y = y0 + ((y1 - y0) * i) / steps;
        await page.mouse.move(x, y);
        await finger(x, y, true);
        await wait(25);
      }
      await wait(200);
      await page.mouse.up();
      await finger(x1, y1, false);
    },
    async type(text) {
      await page.keyboard.type(text, { delay: 90 });
    },
    /** What the accessibility tree has now, to write a clip with RECORD_DEBUG=1. */
    async dump() {
      const names = await page.evaluate(() => [...document.querySelectorAll('flt-semantics[role]')].filter((e) => !e.querySelector('flt-semantics')).map((e) => `${e.getAttribute('role')}|${e.textContent.replace(/\n/g, ' ')}`));
      console.log(names.join('\n'));
    },
    async scroll(dy, at = [196, 500]) {
      await page.mouse.move(...at);
      await page.mouse.wheel(0, dy);
      await wait(500);
    },
  };
}

/**
 * Records [page] at the phone's pixels (Playwright's own video is at CSS
 * pixels, too blurry for text) into JPEG frames in [dir]; stop() returns
 * an ffmpeg concat list, each frame shown until the next.
 */
async function screencast(page, dir) {
  fs.mkdirSync(dir, { recursive: true });
  const cdp = await page.context().newCDPSession(page);
  const frames = [];
  cdp.on('Page.screencastFrame', ({ data, metadata, sessionId }) => {
    const file = path.join(dir, `${String(frames.length).padStart(5, '0')}.jpg`);
    fs.writeFileSync(file, Buffer.from(data, 'base64'));
    frames.push({ file, at: metadata.timestamp });
    cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
  });
  await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: 786, maxHeight: 1704 });
  return {
    async stop() {
      await page.waitForTimeout(300);
      const end = Date.now() / 1000;
      await cdp.send('Page.stopScreencast');
      const lines = frames.map((f, i) => `file '${f.file}'\nduration ${((frames[i + 1]?.at ?? end) - f.at).toFixed(3)}`);
      // The concat demuxer takes the last file's duration only if it is listed again.
      lines.push(`file '${frames.at(-1).file}'`);
      const list = path.join(dir, 'frames.txt');
      fs.writeFileSync(list, lines.join('\n'));
      return list;
    },
  };
}

/** The clips: where each starts and what it does. */
const CLIPS = {
  // 同工: 首頁 lists what I serve next; one opens its day.
  home: {
    route: '/home',
    async play(s) {
      await s.wait(1500);
      // The first button is the bell; then the days, nearest first.
      await s.tap(s.nodes('').nth(1));
      await s.wait(2500);
    },
  },
  // 排好幾週: the weeks not arranged yet, a 司會 each, then 通知同工.
  plan: {
    route: '/rosters/plan/sunday',
    async play(s, { duties }) {
      await s.wait(1200);
      for (const week of [2, 3]) {
        await s.tap(s.nodes(`${duties[0]}, `).nth(week));
        await s.wait(900);
        // The picker's buttons: the scrim, 關閉, 編輯 and 完成, then the people.
        await s.tap(s.nodes('').nth(4 + week));
        await s.wait(900);
      }
      await s.tap(s.node(s.t('planNotify')));
      await s.wait(2200);
    },
  },
  // 排好幾週: a 司會 held and dropped on another week trades the two.
  swap: {
    route: '/rosters/plan/sunday',
    async play(s, { duties }) {
      await s.wait(1200);
      await s.drag(s.nodes(`${duties[0]}, `).nth(0), s.nodes(`${duties[0]}, `).nth(1));
      await s.wait(2200);
    },
  },
  // 小組長: people added to a 小組 just started, one at a time.
  addStaff: {
    route: '/me/groups/small/sg2',
    async play(s) {
      await s.wait(1200);
      for (const person of [2, 5]) {
        // 加入同工 is not in the web build's accessibility tree; it is the
        // row above 關閉小組's section.
        await s.tap(s.node(s.t('deleteSmallGroup')), { dy: -68 });
        await s.wait(1000);
        // The sheet's buttons: the scrim and 關閉, then the people.
        await s.tap(s.nodes('').nth(person));
        await s.wait(1200);
      }
      await s.wait(800);
    },
  },
  // 小組長: when the 小組 meets, so 回報人數 knows which days to ask about.
  meets: {
    route: '/me/groups/small/sg2',
    async play(s) {
      await s.wait(1200);
      await s.tap(s.nodes(s.t('smallGroupMeets')).first());
      await s.wait(1000);
      // The sheet's buttons: the scrim, 關閉, 儲存, 每週, 隔週, then Monday to Sunday.
      await s.tap(s.nodes('').nth(9));
      await s.wait(600);
      await s.tap(s.node(s.t('save')));
      await s.wait(1800);
    },
  },
  // 小組長: the last meeting's 人數.
  attendance: {
    route: '/me/groups/small/sg1',
    async play(s) {
      await s.wait(1200);
      await s.tap(s.nodes('').filter({ hasText: s.t('attendanceMissing') }).first());
      await s.wait(1000);
      await s.type('9');
      await s.wait(500);
      await s.tap(s.node(s.t('save')));
      await s.wait(1800);
    },
  },
  // 管理員: an invite link for the 同工 group chat.
  invite: {
    route: '/me/invites',
    async play(s) {
      await s.wait(1200);
      await s.tap(s.node(s.t('inviteCreate')));
      await s.wait(2500);
    },
  },
  // 通知: what to be told, from 設定.
  notifications: {
    route: '/me',
    async play(s) {
      await s.wait(1000);
      await s.tap(s.node(s.t('notifications')));
      await s.wait(1300);
      await s.tap(s.node(s.t('notifReminderBoth')));
      await s.wait(1800);
    },
  },
};

const only = flag('only');
const languages = flag('lang') ?? Object.keys(LANGUAGES);
// Headless Chromium sends its screencast at CSS pixels unless the scale is forced too.
const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--force-device-scale-factor=2'] });
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'martha-record-'));

/** The demo church's duties in each language (app/lib/data/memory/demo_data.dart), for finding cells. */
const DUTIES = {
  'zh-Hant': ['司會', '敬拜主領', '司琴', '鼓', '音控', '投影', '招待', '奉獻'],
  'zh-Hans': ['领会', '敬拜主领', '司琴', '鼓手', '音控', '投影', '招待', '奉献'],
  en: ['Host', 'Worship Leader', 'Piano', 'Drums', 'Sound', 'Slides', 'Usher', 'Offering'],
  ja: ['司会', '賛美リード', '奏楽', 'ドラム', '音響', 'スライド', '受付', '献金'],
  ko: ['사회', '찬양 인도', '반주', '드럼', '음향', '자막', '안내', '헌금'],
};

let failed = false;
for (const language of languages) {
  const words = JSON.parse(fs.readFileSync(path.join(arbDir, LANGUAGES[language].arb), 'utf8'));
  for (const [name, clip] of Object.entries(CLIPS)) {
    if (only && !only.includes(name)) continue;
    const context = await browser.newContext({
      viewport: { width: 393, height: 852 },
      deviceScaleFactor: 2,
      locale: LANGUAGES[language].locale,
      // 建立邀請連結 copies the link where there is no share sheet.
      permissions: ['clipboard-read', 'clipboard-write'],
    });
    await context.addInitScript(FINGER);
    const page = await context.newPage();
    page.on('pageerror', (e) => console.error(`${language}/${name} pageerror: ${e.message}`));
    await page.goto(`${base}${clip.route}`);
    await page.waitForTimeout(4000);
    const frames = await screencast(page, path.join(tmp, `${language}-${name}`));
    try {
      await clip.play(session(page, words), { duties: DUTIES[language] });
    } catch (e) {
      failed = true;
      console.error(`${language}/${name}: ${e.message}`);
      await page.screenshot({ path: path.join(tmp, `${language}-${name}-failed.png`) });
    }
    const list = await frames.stop();
    await context.close();
    const dir = path.join(outdir, language);
    fs.mkdirSync(dir, { recursive: true });
    const mp4 = path.join(dir, `${name}.mp4`);
    // H.264 for every browser; small enough to play on a phone at once.
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-an', '-vf', 'fps=30,scale=trunc(iw/2)*2:trunc(ih/2)*2', '-c:v', 'libx264', '-preset', 'slow', '-crf', '26', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', mp4]);
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', mp4, '-frames:v', '1', '-q:v', '4', mp4.replace(/\.mp4$/, '.jpg')]);
    console.log(`${mp4} ${(fs.statSync(mp4).size / 1024).toFixed(0)} KB`);
  }
}
await browser.close();
server.close();
if (failed) {
  console.error(`failed: screenshots in ${tmp}`);
  process.exit(1);
}
