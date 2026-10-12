// Builds the website into <out>: the landing page, the support page, the
// blog and the legal pages, with one shared header and footer, in every
// language of LANGUAGES. Prints the path of every page search engines may
// list, for the sitemap.
//
//   node scripts/build-site.mjs <out> --origin https://marthasit.com --project marthasit [--payments on|off]
//
// --payments (default off) turns on 線上支持 on the support page: the
// amount picker and NewebPay. Pages mark what shows only one way with
// <!-- payments:on --> … <!-- /payments:on --> and the same for off; with
// it off the support button only says 即將開放.
//
// Pages in landing/ mark where the shared parts go with <!-- site-header -->,
// <!-- site-footer --> and (in pages with their own footer) <!-- site-languages -->,
// and use __ORIGIN__ / __FIREBASE_PROJECT__ for what differs between
// projects. Blog posts are landing/blog/<path>.md and start with front matter:
//   ---
//   title: 第一次使用：建立教會、邀請同工
//   date: 2026-10-07
//   description: 一兩句摘要，列表和搜尋結果會顯示
//   ---
//
// Languages: Traditional Chinese is landing/ itself, at the site's root;
// each other language is landing/<tag>/, the same files translated, at
// /<tag>/ (functions/src/languages.ts's sitePath). Every page says where its
// other languages are, and sends a visitor to the one their browser asks
// for, as the app picks its language, until they pick one at the foot of
// a page.
import { copyFileSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const landing = join(root, 'landing');
const { marked } = createRequire(join(landing, 'package.json'))('marked');

const zhDate = (iso) => {
  const [y, m, d] = iso.split('-').map(Number);
  return `${y} 年 ${m} 月 ${d} 日`;
};
const EN_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** The website's languages, as the app's (functions/src/languages.ts); what the shared parts say in each. */
export const LANGUAGES = {
  'zh-Hant': {
    label: '繁體中文',
    ogLocale: 'zh_TW',
    appName: '馬大別忙',
    nav: '網站',
    blog: '教學',
    support: '支持',
    openApp: '開啟網頁版',
    foot: '頁尾',
    home: '首頁',
    posts: '教學文章',
    supportUs: '支持馬大別忙',
    privacy: '隱私權政策',
    terms: '服務條款',
    issues: '問題回報',
    contact: '聯絡我們',
    operator: '本服務由個人營運。',
    languages: '語言',
    blogTitle: '教學文章｜馬大別忙',
    blogDescription: '馬大別忙的使用教學：建立教會、邀請同工、安排服事表。',
    blogLead: '馬大別忙怎麼用，一篇講一件事。',
    postTitle: (title) => `${title}｜馬大別忙`,
    date: zhDate,
  },
  'zh-Hans': {
    label: '简体中文',
    ogLocale: 'zh_CN',
    appName: '马大别忙',
    nav: '网站',
    blog: '教学',
    support: '支持',
    openApp: '打开网页版',
    foot: '页脚',
    home: '首页',
    posts: '教学文章',
    supportUs: '支持马大别忙',
    privacy: '隐私政策',
    terms: '服务条款',
    issues: '问题反馈',
    contact: '联系我们',
    operator: '本服务由个人运营。',
    languages: '语言',
    blogTitle: '教学文章｜马大别忙',
    blogDescription: '马大别忙的使用教学：建立教会、邀请同工、安排事奉表。',
    blogLead: '马大别忙怎么用，一篇讲一件事。',
    postTitle: (title) => `${title}｜马大别忙`,
    date: zhDate,
  },
  en: {
    label: 'English',
    ogLocale: 'en_US',
    appName: 'Martha, sit',
    nav: 'Site',
    blog: 'Guides',
    support: 'Support',
    openApp: 'Open web app',
    foot: 'Footer',
    home: 'Home',
    posts: 'Guides',
    supportUs: 'Support Martha, sit',
    privacy: 'Privacy Policy',
    terms: 'Terms of Service',
    issues: 'Report a problem',
    contact: 'Contact us',
    operator: 'Run by one person.',
    languages: 'Language',
    blogTitle: 'Guides | Martha, sit',
    blogDescription: 'How to use Martha, sit: set up your church, invite your team, and plan the schedule.',
    blogLead: 'How Martha, sit works, one thing at a time.',
    postTitle: (title) => `${title} | Martha, sit`,
    date: (iso) => {
      const [y, m, d] = iso.split('-').map(Number);
      return `${EN_MONTHS[m - 1]} ${d}, ${y}`;
    },
  },
  ja: {
    label: '日本語',
    ogLocale: 'ja_JP',
    appName: 'マルタ、ひと休み',
    nav: 'サイト',
    blog: '使い方',
    support: '応援',
    openApp: 'Web版を開く',
    foot: 'フッター',
    home: 'ホーム',
    posts: '使い方ガイド',
    supportUs: '「マルタ、ひと休み」を応援',
    privacy: 'プライバシーポリシー',
    terms: '利用規約',
    issues: '不具合の報告',
    contact: 'お問い合わせ',
    operator: '個人で運営しています。',
    languages: '言語',
    blogTitle: '使い方ガイド｜マルタ、ひと休み',
    blogDescription: 'マルタ、ひと休みの使い方：教会の作成、メンバーの招待、奉仕表の作成。',
    blogLead: 'マルタ、ひと休みの使い方を、1回にひとつずつ。',
    postTitle: (title) => `${title}｜マルタ、ひと休み`,
    date: (iso) => {
      const [y, m, d] = iso.split('-').map(Number);
      return `${y}年${m}月${d}日`;
    },
  },
  ko: {
    label: '한국어',
    ogLocale: 'ko_KR',
    appName: '마르다의 쉼표',
    nav: '사이트',
    blog: '사용법',
    support: '후원',
    openApp: '웹 버전 열기',
    foot: '바닥글',
    home: '홈',
    posts: '사용 가이드',
    supportUs: '마르다의 쉼표 후원하기',
    privacy: '개인정보처리방침',
    terms: '서비스 이용약관',
    issues: '문제 신고',
    contact: '문의하기',
    operator: '개인이 운영하는 서비스예요.',
    languages: '언어',
    blogTitle: '사용 가이드 | 마르다의 쉼표',
    blogDescription: '마르다의 쉼표 사용법: 교회 만들기, 멤버 초대, 봉사표 만들기.',
    blogLead: '마르다의 쉼표 사용법을 한 번에 하나씩 알려 드려요.',
    postTitle: (title) => `${title} | 마르다의 쉼표`,
    date: (iso) => {
      const [y, m, d] = iso.split('-').map(Number);
      return `${y}년 ${m}월 ${d}일`;
    },
  },
};
const TAGS = Object.keys(LANGUAGES);

/** [page] (/support, /blog/x/) in [language]. */
export const sitePath = (language, page) => (language === 'zh-Hant' ? page : `/${language}${page}`);
const sourceDir = (language) => (language === 'zh-Hant' ? landing : join(landing, language));

/**
 * The language the app would show a browser asking for [tag], or null when
 * it speaks none of it: app/lib/core/languages.dart's AppLanguage.of, kept
 * to testdata/languages.json (scripts/test/build-site.test.mjs). Runs in the
 * page, so plain old JavaScript.
 */
export function speaks(tag) {
  var parts = String(tag).toLowerCase().split(/[-_]/);
  var rest = parts.slice(1);
  if (parts[0] === 'en' || parts[0] === 'ja' || parts[0] === 'ko') return parts[0];
  if (parts[0] !== 'zh') return null;
  var script = rest.filter(function (p) { return p.length === 4; })[0];
  var region = rest.filter(function (p) { return p.length === 2; })[0];
  return script === 'hans' || (!script && ['cn', 'sg', 'my'].indexOf(region) >= 0) ? 'zh-Hans' : 'zh-Hant';
}

/**
 * Sends the visitor to [pages][their language]: the one they picked at the
 * foot of a page (or the app asked for with ?lang=), else their browser's,
 * else English. Search engines stay
 * (each page lists the others for them).
 */
function chooser(language, pages) {
  return `<script>
(function () {
  ${speaks.toString().replace(/\n/g, '\n  ')}
  var pages = ${JSON.stringify(pages)};
  var picked = null;
  try { picked = localStorage.getItem('siteLanguage'); } catch (e) {}
  // ?lang=: the app opening a page in its language, kept as a pick.
  var asked = (location.search.match(/[?&]lang=([^&#]*)/) || [])[1];
  if (pages[asked]) {
    picked = asked;
    try { localStorage.setItem('siteLanguage', asked); } catch (e) {}
  }
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[data-site-language]');
    if (a) try { localStorage.setItem('siteLanguage', a.getAttribute('data-site-language')); } catch (e) {}
  });
  if (!pages[picked]) {
    if (/bot|crawl|spider|slurp|preview|lighthouse/i.test(navigator.userAgent)) return;
    var langs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || ''];
    picked = 'en';
    for (var i = 0; i < langs.length; i++) {
      if (speaks(langs[i])) { picked = speaks(langs[i]); break; }
    }
  }
  if (picked !== ${JSON.stringify(language)} && pages[picked]) location.replace(pages[picked] + location.search + location.hash);
})();
</script>
`;
}

function header(language, page) {
  const w = LANGUAGES[language];
  const at = (p) => sitePath(language, p);
  // The landing page's hero runs up under the header; other pages get a rule.
  return `<header class="top${page === '/' ? '' : ' ruled'}">
  <div class="wrap">
    <a class="brand" href="${at('/')}"><img src="/icons/Icon-192.png" alt="" width="28" height="28">${w.appName}</a>
    <nav class="top-nav" aria-label="${w.nav}">
      <a href="${at('/blog/')}"${page.startsWith('/blog/') ? ' aria-current="page"' : ''}>${w.blog}</a>
      <a href="${at('/support')}"${page === '/support' ? ' aria-current="page"' : ''}>${w.support}</a>
      <a class="top-link" href="/home">${w.openApp}</a>
    </nav>
  </div>
</header>`;
}

/** Links to [page] in each language, for the foot of the page. */
function languageLinks(language, page) {
  const links = TAGS.map((tag) => {
    const here = tag === language ? ' aria-current="true"' : '';
    return `<a href="${sitePath(tag, page)}" hreflang="${tag}" lang="${tag}" data-site-language="${tag}"${here}>${LANGUAGES[tag].label}</a>`;
  });
  return `<nav class="langs" aria-label="${LANGUAGES[language].languages}">
      ${links.join('\n      ')}
    </nav>`;
}

function footer(language, page) {
  const w = LANGUAGES[language];
  const at = (p) => sitePath(language, p);
  const current = (p) => (p === page ? ' aria-current="page"' : '');
  return `<footer class="foot">
  <div class="wrap">
    <nav aria-label="${w.foot}">
      <a href="${at('/')}"${current('/')}>${w.home}</a>
      <a href="${at('/blog/')}"${current('/blog/')}>${w.posts}</a>
      <a href="${at('/support')}"${current('/support')}>${w.supportUs}</a>
      <a href="${at('/privacy')}">${w.privacy}</a>
      <a href="${at('/terms')}">${w.terms}</a>
      <a href="https://github.com/hansli112/church-staff-pwa/issues">${w.issues}</a>
      <a href="mailto:hansli112871114@gmail.com">${w.contact}</a>
    </nav>
    ${languageLinks(language, page)}
    <p>${w.operator}</p>
  </div>
</footer>`;
}

/** Builds the site; returns the paths for the sitemap. */
export function buildSite({ out, origin, project = '', payments = 'off' }) {
  /** Keeps the <!-- payments:<payments> --> parts of [html] and drops the others. */
  function paymentParts(html) {
    const other = payments === 'on' ? 'off' : 'on';
    return html
      .replace(new RegExp(`[ \\t]*<!-- payments:${other} -->[\\s\\S]*?<!-- /payments:${other} -->\\n?`, 'g'), '')
      .replace(new RegExp(`[ \\t]*<!-- /?payments:${payments} -->\\n?`, 'g'), '');
  }

  // On a custom domain, the project's Firebase hosts send visitors there with
  // the same path, before anything else in the head runs (app/web/index.html
  // does the same for the app).
  const firebaseHosts = project ? [`${project}.web.app`, `${project}.firebaseapp.com`] : [];
  const toOrigin = firebaseHosts.some((host) => origin === `https://${host}`) ? '' : `<script>
if (${JSON.stringify(firebaseHosts)}.indexOf(location.hostname) >= 0) {
  location.replace(${JSON.stringify(origin)} + location.pathname + location.search + location.hash);
}
</script>
`;

  /** The page in every language, for search engines; x-default is English, as the app falls back to it. */
  const alternates = (page) =>
    [...TAGS.map((tag) => [tag, sitePath(tag, page)]), ['x-default', sitePath('en', page)]]
      .map(([tag, path]) => `<link rel="alternate" hreflang="${tag}" href="${origin}${path}">\n`)
      .join('');

  /** A page from landing/ in [language] with the shared parts and this project's values. */
  function fill(html, language, page) {
    const pages = Object.fromEntries(TAGS.map((tag) => [tag, sitePath(tag, page)]));
    return paymentParts(html)
      .replace('<head>\n', `<head>\n${toOrigin}${chooser(language, pages)}`)
      .replace('</head>', `${alternates(page)}</head>`)
      .replace('<!-- site-header -->', header(language, page))
      .replace('<!-- site-footer -->', footer(language, page))
      .replace('<!-- site-languages -->', languageLinks(language, page))
      .replaceAll('__ORIGIN__', origin)
      .replaceAll('__FIREBASE_PROJECT__', project);
  }

  function blogPage(language, { title, description, page, type, main }) {
    const w = LANGUAGES[language];
    return fill(`<!doctype html>
<html lang="${language}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}">
<meta name="color-scheme" content="light dark">
<meta property="og:type" content="${type}">
<meta property="og:locale" content="${w.ogLocale}">
<meta property="og:site_name" content="${w.appName}">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
<meta property="og:url" content="__ORIGIN__${sitePath(language, page)}">
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
`, language, page);
  }

  const listed = [];
  mkdirSync(out, { recursive: true });
  copyFileSync(join(landing, 'site.css'), join(out, 'site.css'));

  for (const language of TAGS) {
    const w = LANGUAGES[language];
    const from = sourceDir(language);
    const to = language === 'zh-Hant' ? out : join(out, language);
    mkdirSync(to, { recursive: true });
    const write = (file, page, html) => {
      mkdirSync(dirname(join(to, file)), { recursive: true });
      writeFileSync(join(to, file), html);
      listed.push(sitePath(language, page));
    };

    // Pages written by hand. The legal pages (and how to delete an account)
    // are opened from the app and the stores, so they keep their own header
    // with no way to the support page (app stores forbid steering to
    // outside payment).
    for (const [file, page] of [['index.html', '/'], ['support.html', '/support'], ['privacy.html', '/privacy'], ['terms.html', '/terms'], ['delete-account.html', '/delete-account']]) {
      write(file, page, fill(readFileSync(join(from, file), 'utf8'), language, page));
    }

    // The blog.
    const posts = readdirSync(join(from, 'blog'))
      .filter((f) => f.endsWith('.md'))
      .map((f) => readPost(join(from, 'blog', f)))
      .sort((a, b) => b.date.localeCompare(a.date));
    for (const post of posts) {
      const page = `/blog/${post.slug}/`;
      write(`blog/${post.slug}/index.html`, page, blogPage(language, {
        title: w.postTitle(post.title),
        description: post.description,
        page,
        type: 'article',
        main: `    <article class="prose">
      <p class="meta"><a href="${sitePath(language, '/blog/')}">${w.posts}</a> · <time datetime="${post.date}">${w.date(post.date)}</time></p>
      <h1>${escapeHtml(post.title)}</h1>
${post.body}    </article>`,
      }));
    }
    const items = posts.map((post) => `      <li>
        <a href="${sitePath(language, `/blog/${post.slug}/`)}">
          <h2>${escapeHtml(post.title)}</h2>
          <p>${escapeHtml(post.description)}</p>
          <time datetime="${post.date}">${w.date(post.date)}</time>
        </a>
      </li>`).join('\n');
    write('blog/index.html', '/blog/', blogPage(language, {
      title: w.blogTitle,
      description: w.blogDescription,
      page: '/blog/',
      type: 'website',
      main: `    <h1>${w.posts}</h1>
    <p class="lead">${w.blogLead}</p>
    <ul class="posts">
${items}
    </ul>`,
    }));
  }
  return listed;
}

function escapeHtml(s) {
  return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
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

// Run as a script (not imported by its test); /var is /private/var on macOS.
if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const flag = (name) => {
    const i = args.indexOf(`--${name}`);
    return i >= 0 ? args[i + 1] : undefined;
  };
  const out = args[0];
  const origin = flag('origin');
  const payments = flag('payments') ?? 'off';
  if (!out || out.startsWith('--') || !origin || !['on', 'off'].includes(payments)) {
    throw new Error('usage: build-site.mjs <out> --origin <https://…> [--project <id>] [--payments on|off]');
  }
  for (const path of buildSite({ out, origin, project: flag('project') ?? '', payments })) console.log(path);
}
