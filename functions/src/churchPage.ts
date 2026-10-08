import type { Storage } from 'firebase-admin/storage';

import { CHURCH_ID, isChurchOpen } from './access.js';
import type { Deps } from './common.js';
import { publicLogoPath } from './church.js';
import { ICON_FILES, iconStoragePath, type IconFile } from './icons.js';

/**
 * 教會頁: Hosting sends /c/** here, so each church URL is its own web app
 * install. The page is the web app's shell with the church's name and logo
 * in the head; the manifest names the church and starts at its URL. Adding
 * /c/ID to the home screen therefore gives the church's name and icon, and a
 * link pasted into LINE previews with them.
 *
 * Closed (suspended, deleted) churches get the plain page: the app explains
 * why. An unknown ID gets the plain page with a 404; the app says the church
 * was not found.
 */
export interface PageDeps extends Deps {
  bucket: Pick<ReturnType<Storage['bucket']>, 'file'>;
  /** The hosting origin, e.g. https://marthasit.web.app. */
  appUrl: string;
}

export interface PageResponse {
  status: number;
  headers: Record<string, string>;
  body: string | Buffer;
}

/** The web app's shell on the hosting origin: index.html is the landing page. */
export const APP_SHELL = '/app.html';
/** How long a fetched app shell is reused. */
export const TEMPLATE_MINUTES = 5;
const CACHE = 'public, max-age=300';
const IMMUTABLE = 'public, max-age=31536000, immutable';
const HTML = 'text/html; charset=utf-8';

/** The web app's own icons, used when a church has no logo. */
export const DEFAULT_ICONS = [
  { src: '/icons/Icon-192.png', sizes: '192x192', type: 'image/png' },
  { src: '/icons/Icon-512.png', sizes: '512x512', type: 'image/png' },
  { src: '/icons/Icon-maskable-192.png', sizes: '192x192', type: 'image/png', purpose: 'maskable' },
  { src: '/icons/Icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
];
const DEFAULT_TOUCH_ICON = '/icons/Icon-192.png';
const DEFAULT_OG_IMAGE = '/icons/Icon-512.png';

let template: { html: string; at: number } | null = null;

/** Forgets the cached app shell (tests). */
export function clearTemplateCache() {
  template = null;
}

/** The deployed app shell, fetched from the hosting origin and kept a few minutes. */
async function appShell(deps: PageDeps): Promise<string | null> {
  const now = deps.now().getTime();
  if (template && now - template.at < TEMPLATE_MINUTES * 60e3) return template.html;
  try {
    const res = await deps.fetch(`${deps.appUrl}${APP_SHELL}`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) throw new Error(`${APP_SHELL} ${res.status}`);
    const html = await res.text();
    // Only the app gets a church's name, never the landing page.
    if (!html.includes('flutter_bootstrap.js')) throw new Error(`${APP_SHELL} is not the app`);
    template = { html, at: now };
  } catch (e) {
    // A stale copy is better than no page.
    if (!template) {
      console.error('churchPage: no app shell', e);
      return null;
    }
  }
  return template.html;
}

export interface ChurchFace {
  name: string;
  /** Under the icon on the home screen. */
  shortName: string;
  /** Paths on the hosting origin. */
  icons: { src: string; sizes: string; type: string; purpose?: string }[];
  touchIcon: string;
  ogImage: string;
}

/** How an active church presents itself; null for a closed one. */
function face(cid: string, church: FirebaseFirestore.DocumentSnapshot): ChurchFace | null {
  if (!isChurchOpen(church)) return null;
  const name = church.get('name') as string;
  const homeName = church.get('homeName') as string | undefined;
  const version = church.get('logoVersion') as string | undefined;
  const base = { name, shortName: homeName || name };
  if (!version) return { ...base, icons: DEFAULT_ICONS, touchIcon: DEFAULT_TOUCH_ICON, ogImage: DEFAULT_OG_IMAGE };
  const logo = publicLogoPath(cid, version);
  // Until the icons for this logo exist, the logo itself.
  if (church.get('logoIcons') !== version) {
    return { ...base, icons: [{ src: logo, sizes: '512x512', type: 'image/png' }], touchIcon: logo, ogImage: logo };
  }
  const icon = (file: IconFile) => publicLogoPath(cid, version, file);
  return {
    ...base,
    icons: [
      { src: icon('icon-192.png'), sizes: '192x192', type: 'image/png' },
      { src: icon('icon-512.png'), sizes: '512x512', type: 'image/png' },
      { src: icon('maskable-512.png'), sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ],
    touchIcon: icon('apple-touch-180.png'),
    ogImage: logo,
  };
}

const escape = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** The app shell with the church's name and icons in its head. */
export function personalize(html: string, cid: string, f: ChurchFace, appUrl: string): string {
  const name = escape(f.name);
  const og = [
    `<meta property="og:type" content="website">`,
    `<meta property="og:title" content="${name}">`,
    `<meta property="og:image" content="${escape(appUrl + f.ogImage)}">`,
    `<meta property="og:url" content="${escape(`${appUrl}/c/${cid}`)}">`,
  ].join('\n  ');
  return html
    .replace(/<title>[^<]*<\/title>/, `<title>${name}</title>`)
    .replace(/<meta name="apple-mobile-web-app-title" content="[^"]*">/, `<meta name="apple-mobile-web-app-title" content="${escape(f.shortName)}">`)
    .replace(/<link rel="apple-touch-icon" href="[^"]*">/, `<link rel="apple-touch-icon" href="${escape(f.touchIcon)}">`)
    .replace(/<link rel="manifest" href="[^"]*">/, `<link rel="manifest" href="/c/${cid}/manifest.json">`)
    .replace('</head>', `  ${og}\n</head>`);
}

export function manifest(cid: string, f: ChurchFace | null) {
  return {
    name: f?.name ?? '馬大別忙',
    short_name: f?.shortName ?? '馬大別忙',
    id: `/c/${cid}`,
    start_url: `/c/${cid}`,
    scope: '/',
    display: 'standalone',
    background_color: '#F2F2F7',
    theme_color: '#1F5FD1',
    description: '馬大！馬大！你為許多的事思慮煩擾，但是不可少的只有一件；馬利亞已經選擇那上好的福分，是不能奪去的。（路加福音 10:41–42）',
    orientation: 'portrait-primary',
    prefer_related_applications: false,
    lang: 'zh-Hant',
    icons: f?.icons ?? DEFAULT_ICONS,
  };
}

const notFound = (body = ''): PageResponse => ({ status: 404, headers: { 'content-type': 'text/plain' }, body });

/** Answers one request under /c/. [path] is the request path. */
export async function churchPage(deps: PageDeps, path: string): Promise<PageResponse> {
  const match = new RegExp(`^/c/(${CHURCH_ID})(/.*)?$`).exec(path);
  const cid = match?.[1];
  const rest = match?.[2] ?? '';
  const church = cid ? await deps.db.doc(`churches/${cid}`).get() : null;

  if (cid && church?.exists && rest === '/manifest.json') {
    return {
      status: 200,
      headers: { 'content-type': 'application/manifest+json; charset=utf-8', 'cache-control': CACHE },
      body: JSON.stringify(manifest(cid, face(cid, church))),
    };
  }

  const icon = /^\/icons\/([A-Za-z0-9_-]{1,64})\/([a-z0-9-]{1,40}\.png)$/.exec(rest);
  if (icon) {
    if (!cid || !isChurchOpen(church) || church?.get('logoVersion') !== icon[1]) return notFound();
    const bytes = await readIcon(deps, cid, icon[1], icon[2]);
    if (!bytes) return notFound();
    return { status: 200, headers: { 'content-type': 'image/png', 'cache-control': IMMUTABLE }, body: bytes };
  }

  const html = await appShell(deps);
  if (html === null) return { status: 503, headers: { 'content-type': 'text/plain', 'retry-after': '30' }, body: '' };
  if (!cid || !church?.exists) {
    return { status: 404, headers: { 'content-type': HTML, 'cache-control': CACHE }, body: html };
  }
  const f = face(cid, church);
  return {
    status: 200,
    headers: { 'content-type': HTML, 'cache-control': CACHE },
    body: f ? personalize(html, cid, f, deps.appUrl) : html,
  };
}

/** The logo or one of the icons made from it, from Storage; null when missing. */
async function readIcon(deps: PageDeps, cid: string, version: string, file: string): Promise<Buffer | null> {
  const path =
    file === 'logo.png'
      ? `churches/${cid}/logo.png`
      : (ICON_FILES as readonly string[]).includes(file)
        ? iconStoragePath(cid, version, file as IconFile)
        : null;
  if (!path) return null;
  try {
    const [bytes] = await deps.bucket.file(path).download();
    return bytes;
  } catch (e) {
    if ((e as { code?: number }).code === 404) return null;
    throw e;
  }
}
