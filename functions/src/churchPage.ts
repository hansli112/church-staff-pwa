import type { Storage } from 'firebase-admin/storage';

import type { Deps } from './common.js';
import { publicLogoPath } from './church.js';
import { ICON_FILES, iconStoragePath, type IconFile } from './icons.js';

/**
 * 教會頁: Hosting sends /c/** here, so each church URL is its own web app
 * install. The page is the web app's index.html with the church's name and
 * logo in the head; the manifest names the church and starts at its URL.
 * Adding /c/ID to the home screen therefore gives the church's name and
 * icon, and a link pasted into LINE previews with them.
 *
 * Closed (suspended, deleted) churches get the plain page: the app explains
 * why. An unknown ID gets the plain page with a 404; the app says the church
 * was not found.
 */
export interface PageDeps extends Deps {
  bucket: Pick<ReturnType<Storage['bucket']>, 'file'>;
  /** The hosting origin, e.g. https://martha-app.web.app. */
  appUrl: string;
}

export interface PageResponse {
  status: number;
  headers: Record<string, string>;
  body: string | Buffer;
}

/** How long a fetched index.html is reused. */
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

/** Forgets the cached index.html (tests). */
export function clearTemplateCache() {
  template = null;
}

/** The deployed index.html, fetched from the hosting origin and kept a few minutes. */
async function indexHtml(deps: PageDeps): Promise<string | null> {
  const now = deps.now().getTime();
  if (template && now - template.at < TEMPLATE_MINUTES * 60e3) return template.html;
  try {
    const res = await deps.fetch(`${deps.appUrl}/index.html`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) throw new Error(`index.html ${res.status}`);
    template = { html: await res.text(), at: now };
  } catch (e) {
    // A stale copy is better than no page.
    if (!template) {
      console.error('churchPage: no index.html', e);
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
  if (church.get('status') !== 'active') return null;
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

/** index.html with the church's name and icons in its head. */
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
    description: '教會同工的服事表，大家一起看',
    orientation: 'portrait-primary',
    prefer_related_applications: false,
    lang: 'zh-Hant',
    icons: f?.icons ?? DEFAULT_ICONS,
  };
}

const notFound = (body = ''): PageResponse => ({ status: 404, headers: { 'content-type': 'text/plain' }, body });

/** Answers one request under /c/. [path] is the request path. */
export async function churchPage(deps: PageDeps, path: string): Promise<PageResponse> {
  const match = /^\/c\/([A-Za-z0-9]{1,64})(\/.*)?$/.exec(path);
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
    if (!cid || church?.get('status') !== 'active' || church.get('logoVersion') !== icon[1]) return notFound();
    const bytes = await readIcon(deps, cid, icon[1], icon[2]);
    if (!bytes) return notFound();
    return { status: 200, headers: { 'content-type': 'image/png', 'cache-control': IMMUTABLE }, body: bytes };
  }

  const html = await indexHtml(deps);
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
