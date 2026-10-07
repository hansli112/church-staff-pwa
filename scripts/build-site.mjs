// Builds the website into <out>: the landing page, the support page, the
// blog and the legal pages, with one shared header and footer. Prints the
// path of every page search engines may list, for the sitemap.
//
//   node scripts/build-site.mjs <out> --origin https://marthasit.web.app --project marthasit [--payments on|off]
//
// --payments (default off) turns on 線上支持 on the support page: the
// amount picker and NewebPay. Pages mark what shows only one way with
// <!-- payments:on --> … <!-- /payments:on --> and the same for off; with
// it off the support button only says 即將開放.
//
// Pages in landing/ mark where the shared parts go with <!-- site-header -->
// and <!-- site-footer -->, and use __ORIGIN__ / __FIREBASE_PROJECT__ for
// what differs between projects. Blog posts are landing/blog/<path>.md and
// start with front matter:
//   ---
//   title: 第一次使用：建立教會、邀請同工
//   date: 2026-10-07
//   description: 一兩句摘要，列表和搜尋結果會顯示
//   ---
import { copyFileSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const landing = join(root, 'landing');
const { marked } = createRequire(join(landing, 'package.json'))('marked');

const args = process.argv.slice(2);
const flag = (name) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};
const out = args[0];
const origin = flag('origin');
const project = flag('project') ?? '';
const payments = flag('payments') ?? 'off';
if (!out || out.startsWith('--') || !origin || !['on', 'off'].includes(payments)) {
  throw new Error('usage: build-site.mjs <out> --origin <https://…> [--project <id>] [--payments on|off]');
}

const escapeHtml = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const formatDate = (iso) => {
  const [y, m, d] = iso.split('-').map(Number);
  return `${y} 年 ${m} 月 ${d} 日`;
};
const current = (path, here) => (path === here ? ' aria-current="page"' : '');

function header(path) {
  // The landing page's hero runs up under the header; other pages get a rule.
  return `<header class="top${path === '/' ? '' : ' ruled'}">
  <div class="wrap">
    <a class="brand" href="/"><img src="/icons/Icon-192.png" alt="" width="28" height="28">馬大別忙</a>
    <nav class="top-nav" aria-label="網站">
      <a href="/blog/"${path.startsWith('/blog/') ? ' aria-current="page"' : ''}>教學</a>
      <a href="/support"${current(path, '/support')}>支持</a>
      <a class="top-link" href="/home">開啟網頁版</a>
    </nav>
  </div>
</header>`;
}

function footer(path) {
  return `<footer class="foot">
  <div class="wrap">
    <nav aria-label="頁尾">
      <a href="/"${current(path, '/')}>首頁</a>
      <a href="/blog/"${current(path, '/blog/')}>教學文章</a>
      <a href="/support"${current(path, '/support')}>支持馬大別忙</a>
      <a href="/privacy">隱私權政策</a>
      <a href="/terms">服務條款</a>
      <a href="https://github.com/hansli112/church-staff-pwa/issues">問題回報</a>
      <a href="mailto:hansli112871114@gmail.com">聯絡我們</a>
    </nav>
    <p>本服務由個人營運。</p>
  </div>
</footer>`;
}

/** Keeps the <!-- payments:<payments> --> parts of [html] and drops the others. */
function paymentParts(html) {
  const other = payments === 'on' ? 'off' : 'on';
  return html
    .replace(new RegExp(`[ \\t]*<!-- payments:${other} -->[\\s\\S]*?<!-- /payments:${other} -->\\n?`, 'g'), '')
    .replace(new RegExp(`[ \\t]*<!-- /?payments:${payments} -->\\n?`, 'g'), '');
}

/** A page from landing/ with the shared parts and this project's values. */
function fill(html, path) {
  return paymentParts(html)
    .replace('<!-- site-header -->', header(path))
    .replace('<!-- site-footer -->', footer(path))
    .replaceAll('__ORIGIN__', origin)
    .replaceAll('__FIREBASE_PROJECT__', project);
}

function blogPage({ title, description, path, type, main }) {
  return fill(`<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}">
<meta name="color-scheme" content="light dark">
<meta property="og:type" content="${type}">
<meta property="og:locale" content="zh_TW">
<meta property="og:site_name" content="馬大別忙">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
<meta property="og:url" content="__ORIGIN__${path}">
<link rel="stylesheet" href="/site.css">
<link rel="icon" type="image/png" href="/favicon.png">
<link rel="apple-touch-icon" href="/icons/Icon-192.png">
</head>
<body>

<!-- site-header -->

<main class="page">
  <div class="wrap narrow">
${main}
  </div>
</main>

<!-- site-footer -->

</body>
</html>
`, path);
}

function readPost(file) {
  const text = readFileSync(file, 'utf8');
  const front = /^---\n([\s\S]*?)\n---\n/.exec(text);
  if (!front) throw new Error(`${file}: no front matter`);
  const meta = Object.fromEntries(
    front[1].split('\n').filter(Boolean).map((line) => {
      const i = line.indexOf(':');
      return [line.slice(0, i).trim(), line.slice(i + 1).trim()];
    }),
  );
  for (const key of ['title', 'date', 'description']) {
    if (!meta[key]) throw new Error(`${file}: missing ${key}`);
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(meta.date)) throw new Error(`${file}: date must be YYYY-MM-DD`);
  return { ...meta, slug: basename(file, '.md'), body: marked.parse(text.slice(front[0].length)) };
}

const listed = [];

// Pages written by hand.
mkdirSync(out, { recursive: true });
copyFileSync(join(landing, 'site.css'), join(out, 'site.css'));
for (const [file, path] of [['index.html', '/'], ['support.html', '/support']]) {
  writeFileSync(join(out, file), fill(readFileSync(join(landing, file), 'utf8'), path));
  listed.push(path);
}
// The legal pages are opened from the app, so they keep their own header
// with no way to the support page (app stores forbid steering to outside
// payment); they are not listed while they are drafts.
for (const file of ['privacy.html', 'terms.html']) {
  writeFileSync(join(out, file), fill(readFileSync(join(landing, file), 'utf8'), `/${basename(file, '.html')}`));
}

// The blog.
const dir = join(landing, 'blog');
const posts = readdirSync(dir)
  .filter((f) => f.endsWith('.md'))
  .map((f) => readPost(join(dir, f)))
  .sort((a, b) => b.date.localeCompare(a.date));
mkdirSync(join(out, 'blog'), { recursive: true });
for (const post of posts) {
  const path = `/blog/${post.slug}/`;
  mkdirSync(join(out, 'blog', post.slug), { recursive: true });
  writeFileSync(join(out, 'blog', post.slug, 'index.html'), blogPage({
    title: `${post.title}｜馬大別忙`,
    description: post.description,
    path,
    type: 'article',
    main: `    <article class="prose">
      <p class="meta"><a href="/blog/">教學文章</a> · <time datetime="${post.date}">${formatDate(post.date)}</time></p>
      <h1>${escapeHtml(post.title)}</h1>
${post.body}    </article>`,
  }));
  listed.push(path);
}
const items = posts.map((post) => `      <li>
        <a href="/blog/${post.slug}/">
          <h2>${escapeHtml(post.title)}</h2>
          <p>${escapeHtml(post.description)}</p>
          <time datetime="${post.date}">${formatDate(post.date)}</time>
        </a>
      </li>`).join('\n');
writeFileSync(join(out, 'blog', 'index.html'), blogPage({
  title: '教學文章｜馬大別忙',
  description: '馬大別忙的使用教學：建立教會、邀請同工、安排服事表。',
  path: '/blog/',
  type: 'website',
  main: `    <h1>教學文章</h1>
    <p class="lead">馬大別忙怎麼用，一篇講一件事。</p>
    <ul class="posts">
${items}
    </ul>`,
}));
listed.push('/blog/');

for (const path of listed) console.log(path);
