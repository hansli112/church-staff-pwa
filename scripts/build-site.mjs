// Builds the website into <out>: the landing page, the support page, the
// blog and the legal pages, with one shared header and footer, in every
// language of LANGUAGES. Prints the path of every page search engines may
// list, for the sitemap.
//
//   node scripts/build-site.mjs <out> --origin https://marthasit.com --project marthasit [--payments on|off]
//
// --payments (default off) turns on 線上支持 on the support page: the
// amount picker and ECPay. Pages mark what shows only one way with
// <!-- payments:on --> … <!-- /payments:on --> and the same for off; with
// it off the support page only says 線上支持即將開放. Every other comment is
// left out of what is built.
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
// A clip of the app (tools/e2e/record.mjs, landing/media/<language>/) goes
// in a page or a post as an image whose address is media:<clip>:
//   ![排好幾週，再按完成](media:plan)
// It plays, muted and over and over, while it is on screen; for a visitor
// who asks for less motion it waits, with the player's buttons, to be played.
//
// Languages: Traditional Chinese is landing/ itself, at the site's root;
// each other language is landing/<tag>/, the same files translated, at
// /<tag>/ (functions/src/languages.ts's sitePath). Every page says where its
// other languages are, and sends a visitor to the one their browser asks
// for, as the app picks its language, until they pick one at the foot of
// a page.
import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const landing = join(root, 'landing');
const { marked } = createRequire(join(landing, 'package.json'))('marked');
// A guide's link off the site (Cloud Shell, GitHub) or to the web app opens a
// new tab, so the guide stays open to follow beside it.
marked.use({
  hooks: { postprocess: (html) => html.replace(/<a href="(https?:\/\/[^"]*|\/home)"/g, '<a href="$1" target="_blank" rel="noopener"') },
});

/** The picture links to the site show (the app's icon, app/web/icons/Icon-maskable-512.png), at the site's root. */
const OG_IMAGE = 'og-image.png';

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
    features: '功能',
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
    social: '社群',
    help: '幫助',
    policies: '政策',
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
    features: '功能',
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
    social: '社交媒体',
    help: '帮助',
    policies: '政策',
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
    features: 'Features',
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
    social: 'Social media',
    help: 'Help',
    policies: 'Legal',
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
    features: '機能',
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
    social: 'SNS',
    help: 'ヘルプ',
    policies: '規約',
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
    features: '기능',
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
    social: '소셜 미디어',
    help: '도움말',
    policies: '약관',
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
    // The language menu folds away when tapped outside, as a menu does.
    var menu = document.querySelector('details.langs[open]');
    if (menu && !menu.contains(e.target)) menu.open = false;
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

/** Plays a page's clips while they are on screen; with less motion asked for, only when played. */
const CLIPS = `<script>
(function () {
  var clips = document.querySelectorAll('video.clip');
  if (matchMedia('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window)) {
    for (var i = 0; i < clips.length; i++) clips[i].controls = true;
    return;
  }
  var seen = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) e.target.play().catch(function () {});
      else e.target.pause();
    });
  }, { threshold: 0.5 });
  for (var j = 0; j < clips.length; j++) seen.observe(clips[j]);
})();
</script>
`;

/** [html]'s media:<clip> images as [language]'s clips (a post's on a paragraph of their own). */
function clips(html, language) {
  const video = (clip, alt) =>
    `<figure class="clip"><video class="clip" src="/media/${language}/${clip}.mp4" poster="/media/${language}/${clip}.jpg" width="393" height="852" muted loop playsinline preload="none" aria-label="${alt}"></video></figure>`;
  const out = html.replace(/(?:<p>)?<img src="media:([A-Za-z]+)" alt="([^"]*)">(?:<\/p>)?/g, (_, clip, alt) => video(clip, alt));
  return out === html ? html : out.replace('</body>', `${CLIPS}</body>`);
}

/**
 * The iOS and Android apps open the privacy policy, the terms and the
 * guides with from=app (app/lib/features/common/site_pages.dart). The stores
 * forbid them to lead to paying elsewhere, so for the rest of the tab the
 * page hides the web app, which has the support page (every link to /home),
 * and every way to the support page or what says how to pay on the website
 * (data-from-app="hide"); site.css hides them.
 */
const FROM_APP = `<script id="from-app">
(function () {
  var app = /[?&]from=app(?:[&#]|$)/.test(location.search);
  try {
    if (app) sessionStorage.setItem('fromApp', '1');
    else app = sessionStorage.getItem('fromApp') === '1';
  } catch (e) {}
  if (app) document.documentElement.classList.add('from-app');
})();
</script>
`;

function header(language, page) {
  const w = LANGUAGES[language];
  const at = (p) => sitePath(language, p);
  // The landing page's hero runs up under the header; other pages get a rule.
  return `<header class="top${page === '/' ? '' : ' ruled'}">
  <div class="wrap">
    <a class="brand" href="${at('/')}"><img src="/icons/Icon-192.png" alt="" width="28" height="28"><span>${w.appName}</span></a>
    <nav class="top-nav" aria-label="${w.nav}">
      <a href="${at('/features')}"${page === '/features' ? ' aria-current="page"' : ''}>${w.features}</a>
      <a href="${at('/blog/')}"${page.startsWith('/blog/') ? ' aria-current="page"' : ''}>${w.blog}</a>
      <a href="${at('/support')}"${page === '/support' ? ' aria-current="page"' : ''} data-from-app="hide">${w.support}</a>
      <a class="top-link" href="/home">${w.openApp}</a>
    </nav>
  </div>
</header>`;
}

/**
 * Links to [page] in each language, for the foot of the page: folded under
 * the one being read, as a menu, and links all the same (no script needed,
 * and a pick is kept as any other).
 */
function languageLinks(language, page) {
  const links = TAGS.map((tag) => {
    const here = tag === language ? ' aria-current="true"' : '';
    return `<a href="${sitePath(tag, page)}" hreflang="${tag}" lang="${tag}" data-site-language="${tag}"${here}>${LANGUAGES[tag].label}</a>`;
  });
  return `<details class="langs">
      <summary><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 3.6 5.7 3.6 9s-1.1 6.3-3.6 9c-2.5-2.7-3.6-5.7-3.6-9S9.5 5.7 12 3z"/></svg><span class="vh">${LANGUAGES[language].languages}：</span>${LANGUAGES[language].label}</summary>
      <nav aria-label="${LANGUAGES[language].languages}">
        ${links.join('\n        ')}
      </nav>
    </details>`;
}

/**
 * 馬大別忙's own accounts, linked at the foot of every page by their marks
 * (Simple Icons, CC0), each with its name for screen readers.
 */
export const SOCIAL = [
  ['Instagram', 'https://www.instagram.com/marthasitapp/', 'M7.0301.084c-1.2768.0602-2.1487.264-2.911.5634-.7888.3075-1.4575.72-2.1228 1.3877-.6652.6677-1.075 1.3368-1.3802 2.127-.2954.7638-.4956 1.6365-.552 2.914-.0564 1.2775-.0689 1.6882-.0626 4.947.0062 3.2586.0206 3.6671.0825 4.9473.061 1.2765.264 2.1482.5635 2.9107.308.7889.72 1.4573 1.388 2.1228.6679.6655 1.3365 1.0743 2.1285 1.38.7632.295 1.6361.4961 2.9134.552 1.2773.056 1.6884.069 4.9462.0627 3.2578-.0062 3.668-.0207 4.9478-.0814 1.28-.0607 2.147-.2652 2.9098-.5633.7889-.3086 1.4578-.72 2.1228-1.3881.665-.6682 1.0745-1.3378 1.3795-2.1284.2957-.7632.4966-1.636.552-2.9124.056-1.2809.0692-1.6898.063-4.948-.0063-3.2583-.021-3.6668-.0817-4.9465-.0607-1.2797-.264-2.1487-.5633-2.9117-.3084-.7889-.72-1.4568-1.3876-2.1228C21.2982 1.33 20.628.9208 19.8378.6165 19.074.321 18.2017.1197 16.9244.0645 15.6471.0093 15.236-.005 11.977.0014 8.718.0076 8.31.0215 7.0301.0839m.1402 21.6932c-1.17-.0509-1.8053-.2453-2.2287-.408-.5606-.216-.96-.4771-1.3819-.895-.422-.4178-.6811-.8186-.9-1.378-.1644-.4234-.3624-1.058-.4171-2.228-.0595-1.2645-.072-1.6442-.079-4.848-.007-3.2037.0053-3.583.0607-4.848.05-1.169.2456-1.805.408-2.2282.216-.5613.4762-.96.895-1.3816.4188-.4217.8184-.6814 1.3783-.9003.423-.1651 1.0575-.3614 2.227-.4171 1.2655-.06 1.6447-.072 4.848-.079 3.2033-.007 3.5835.005 4.8495.0608 1.169.0508 1.8053.2445 2.228.408.5608.216.96.4754 1.3816.895.4217.4194.6816.8176.9005 1.3787.1653.4217.3617 1.056.4169 2.2263.0602 1.2655.0739 1.645.0796 4.848.0058 3.203-.0055 3.5834-.061 4.848-.051 1.17-.245 1.8055-.408 2.2294-.216.5604-.4763.96-.8954 1.3814-.419.4215-.8181.6811-1.3783.9-.4224.1649-1.0577.3617-2.2262.4174-1.2656.0595-1.6448.072-4.8493.079-3.2045.007-3.5825-.006-4.848-.0608M16.953 5.5864A1.44 1.44 0 1 0 18.39 4.144a1.44 1.44 0 0 0-1.437 1.4424M5.8385 12.012c.0067 3.4032 2.7706 6.1557 6.173 6.1493 3.4026-.0065 6.157-2.7701 6.1506-6.1733-.0065-3.4032-2.771-6.1565-6.174-6.1498-3.403.0067-6.156 2.771-6.1496 6.1738M8 12.0077a4 4 0 1 1 4.008 3.9921A3.9996 3.9996 0 0 1 8 12.0077'],
  ['Threads', 'https://www.threads.com/@marthasitapp', 'M12.186 24h-.007c-3.581-.024-6.334-1.205-8.184-3.509C2.35 18.44 1.5 15.586 1.472 12.01v-.017c.03-3.579.879-6.43 2.525-8.482C5.845 1.205 8.6.024 12.18 0h.014c2.746.02 5.043.725 6.826 2.098 1.677 1.29 2.858 3.13 3.509 5.467l-2.04.569c-1.104-3.96-3.898-5.984-8.304-6.015-2.91.022-5.11.936-6.54 2.717C4.307 6.504 3.616 8.914 3.589 12c.027 3.086.718 5.496 2.057 7.164 1.43 1.783 3.631 2.698 6.54 2.717 2.623-.02 4.358-.631 5.8-2.045 1.647-1.613 1.618-3.593 1.09-4.798-.31-.71-.873-1.3-1.634-1.75-.192 1.352-.622 2.446-1.284 3.272-.886 1.102-2.14 1.704-3.73 1.79-1.202.065-2.361-.218-3.259-.801-1.063-.689-1.685-1.74-1.752-2.964-.065-1.19.408-2.285 1.33-3.082.88-.76 2.119-1.207 3.583-1.291a13.853 13.853 0 0 1 3.02.142c-.126-.742-.375-1.332-.75-1.757-.513-.586-1.308-.883-2.359-.89h-.029c-.844 0-1.992.232-2.721 1.32L7.734 7.847c.98-1.454 2.568-2.256 4.478-2.256h.044c3.194.02 5.097 1.975 5.287 5.388.108.046.216.094.321.142 1.49.7 2.58 1.761 3.154 3.07.797 1.82.871 4.79-1.548 7.158-1.85 1.81-4.094 2.628-7.277 2.65Zm1.003-11.69c-.242 0-.487.007-.739.021-1.836.103-2.98.946-2.916 2.143.067 1.256 1.452 1.839 2.784 1.767 1.224-.065 2.818-.543 3.086-3.71a10.5 10.5 0 0 0-2.215-.221z'],
  ['Facebook', 'https://www.facebook.com/marthasitapp', 'M9.101 23.691v-7.98H6.627v-3.667h2.474v-1.58c0-4.085 1.848-5.978 5.858-5.978.401 0 .955.042 1.468.103a8.68 8.68 0 0 1 1.141.195v3.325a8.623 8.623 0 0 0-.653-.036 26.805 26.805 0 0 0-.733-.009c-.707 0-1.259.096-1.675.309a1.686 1.686 0 0 0-.679.622c-.258.42-.374.995-.374 1.752v1.297h3.919l-.386 2.103-.287 1.564h-3.246v8.245C19.396 23.238 24 18.179 24 12.044c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.628 3.874 10.35 9.101 11.647Z'],
  ['YouTube', 'https://www.youtube.com/@marthasitapp', 'M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z'],
];

function footer(language, page) {
  const w = LANGUAGES[language];
  const at = (p) => sitePath(language, p);
  const current = (p) => (p === page ? ' aria-current="page"' : '');
  // A few short columns, each under its name, as the apps' own sites do; the brand at the top leads home.
  const column = (title, links) => `<div>
        <h2>${title}</h2>
        ${links.join('\n        ')}
      </div>`;
  return `<footer class="foot">
  <div class="wrap">
    <nav class="foot-links" aria-label="${w.foot}">
      ${column(w.appName, [
        `<a href="${at('/features')}"${current('/features')}>${w.features}</a>`,
        `<a href="${at('/blog/')}"${current('/blog/')}>${w.posts}</a>`,
        `<a href="${at('/support')}"${current('/support')} data-from-app="hide">${w.supportUs}</a>`,
      ])}
      ${column(w.help, [
        `<a href="https://github.com/hansli112/church-staff-pwa/issues">${w.issues}</a>`,
        `<a href="mailto:support@marthasit.com">${w.contact}</a>`,
      ])}
      ${column(w.policies, [
        `<a href="${at('/privacy')}">${w.privacy}</a>`,
        `<a href="${at('/terms')}">${w.terms}</a>`,
      ])}
    </nav>
    <div class="foot-end">
      ${languageLinks(language, page)}
      <nav class="social" aria-label="${w.social}">
        ${SOCIAL.map(([name, url, d]) => `<a href="${url}" rel="me"><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="${d}"/></svg><span class="vh">${name}</span></a>`).join('\n        ')}
      </nav>
      <p>${w.operator}</p>
    </div>
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

  /**
   * What every page's head has: its one address (?lang= and ?from=app make
   * copies of it), the picture a link to it shows in chats and social
   * media, and the browser's colors, light and dark.
   */
  const shared = (language, page) => `<link rel="canonical" href="${origin}${sitePath(language, page)}">
<meta property="og:image" content="${origin}/${OG_IMAGE}">
<meta property="og:image:width" content="512">
<meta property="og:image:height" content="512">
<meta property="og:image:alt" content="${LANGUAGES[language].appName}">
<meta name="twitter:card" content="summary">
<meta name="theme-color" content="#FFFFFF" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">
`;

  /** A page from landing/ in [language] with the shared parts and this project's values. */
  function fill(html, language, page) {
    const pages = Object.fromEntries(TAGS.map((tag) => [tag, sitePath(tag, page)]));
    return withoutComments(
      clips(paymentParts(html), language)
        .replace('<head>\n', `<head>\n${toOrigin}${chooser(language, pages)}${FROM_APP}`)
        .replace('</head>', `${shared(language, page)}${alternates(page)}</head>`)
        .replace('<!-- site-header -->', header(language, page))
        .replace('<!-- site-footer -->', footer(language, page))
        .replace('<!-- site-languages -->', languageLinks(language, page)),
    )
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
  for (const file of ['site.css', OG_IMAGE]) copyFileSync(join(landing, file), join(out, file));
  if (existsSync(join(landing, 'media'))) cpSync(join(landing, 'media'), join(out, 'media'), { recursive: true });

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
    for (const [file, page] of [['index.html', '/'], ['features.html', '/features'], ['support.html', '/support'], ['privacy.html', '/privacy'], ['terms.html', '/terms'], ['delete-account.html', '/delete-account']]) {
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

/**
 * [html] without its comments, which are notes for whoever edits landing/
 * (what is to do, what a part is for), not for visitors. Run once the
 * markers (payments, site-header, …) have done their work.
 */
function withoutComments(html) {
  const comment = '<!--(?:(?!-->)[\\s\\S])*-->';
  return html.replace(new RegExp(`^[ \\t]*${comment}[ \\t]*\\n`, 'gm'), '').replace(new RegExp(comment, 'g'), '');
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
