import { randomBytes, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { publicError } from './core.mjs';

const STATIC = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
  ['/style.css', ['style.css', 'text/css; charset=utf-8']],
]);
const equal = (left, right) => {
  const a = Buffer.from(String(left ?? ''));
  const b = Buffer.from(String(right ?? ''));
  return a.length === b.length && timingSafeEqual(a, b);
};

async function jsonBody(request) {
  if (!/^application\/json(?:\s*;.*)?$/i.test(request.headers['content-type'] ?? '')) {
    throw Object.assign(new Error('只接受 JSON 請求'), { httpStatus: 415 });
  }
  let bytes = 0;
  const chunks = [];
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > 64 * 1024) throw Object.assign(new Error('請求內容過大'), { httpStatus: 413 });
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch { throw Object.assign(new Error('JSON 格式不正確'), { httpStatus: 400 }); }
}

export async function startInstallerServer({
  manager, port = 8765, publicOrigin,
  idleTimeoutMs = 30 * 60_000, absoluteTimeoutMs = 2 * 60 * 60_000,
  bootstrapTimeoutMs = 15 * 60_000, now = Date.now,
} = {}) {
  const bootstrapToken = randomBytes(32).toString('base64url');
  let bootstrapUsed = false;
  const bootAt = now();
  let session;
  let origin;
  let closed = false;
  let expired = false;
  let expiryPromise;
  const headers = {
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; font-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  };
  const send = (response, status, body, extra = {}) => {
    response.writeHead(status, { ...headers, 'Content-Type': 'application/json; charset=utf-8', ...extra });
    response.end(JSON.stringify(body));
  };
  const expire = () => {
    if (expired) return expiryPromise;
    expired = true;
    session = undefined;
    expiryPromise = Promise.resolve(manager.dispose()).catch(() => {});
    return expiryPromise;
  };
  const checkExpired = () => {
    // Closing the tab only stops the progress display. A running step keeps
    // the session alive, so expiry never aborts an installation midway. The
    // idle and absolute limits apply once the step has stopped, with at least
    // one idle period of grace to come back and read the result.
    if (session && manager.snapshot().busy) {
      session.touchedAt = now();
      session.graceUntil = now() + idleTimeoutMs;
    } else if (session && now() > (session.graceUntil ?? 0) &&
        (now() - session.touchedAt > idleTimeoutMs || now() - session.createdAt > absoluteTimeoutMs)) void expire();
    return expired;
  };
  const server = createServer(async (request, response) => {
    try {
      const expected = new URL(origin);
      const portNumber = server.address().port;
      const hosts = new Set([expected.host, `127.0.0.1:${portNumber}`, `localhost:${portNumber}`]);
      if (!hosts.has(request.headers.host) ||
          (request.headers['x-forwarded-host'] && request.headers['x-forwarded-host'] !== expected.host)) {
        return send(response, 403, { message: '主機驗證失敗' });
      }
      if (request.headers.origin && request.headers.origin !== origin) return send(response, 403, { message: '來源驗證失敗' });
      if (!request.url?.startsWith('/') || request.url.startsWith('//')) return send(response, 400, { message: '請求路徑不正確' });
      const url = new URL(request.url, origin);
      // Opening the link from the Cloud Shell terminal is a cross-site
      // top-level navigation. Only that page load is exempt; it holds no
      // secret and cannot be framed. Every script, style and API call must
      // still come from the wizard page itself.
      const pageNavigation = request.method === 'GET' && url.pathname === '/' &&
        request.headers['sec-fetch-mode'] === 'navigate' && request.headers['sec-fetch-dest'] === 'document';
      if (request.headers['sec-fetch-site'] && !['same-origin', 'none'].includes(request.headers['sec-fetch-site']) && !pageNavigation) {
        return send(response, 403, { message: '不接受跨網站請求' });
      }
      if (request.method === 'GET' && STATIC.has(url.pathname)) {
        const [file, type] = STATIC.get(url.pathname);
        const body = await readFile(new URL(`./web/${file}`, import.meta.url));
        response.writeHead(200, { ...headers, 'Content-Type': type });
        return response.end(body);
      }
      if (request.method === 'GET' && url.pathname === '/favicon.ico') { response.writeHead(204, headers); return response.end(); }
      if (!url.pathname.startsWith('/api/')) return send(response, 404, { message: '找不到頁面' });
      if (checkExpired()) return send(response, 401, { message: '安裝工作階段已到期。請重新啟動精靈，使用安裝識別碼接續。' });
      if (request.headers['x-installer-request'] !== '1') return send(response, 403, { message: '請從安裝精靈操作' });
      if (request.method !== 'GET' && request.headers.origin !== origin) return send(response, 403, { message: '來源驗證失敗' });
      if (url.pathname === '/api/session' && request.method === 'POST') {
        const input = await jsonBody(request);
        if (bootstrapUsed || now() - bootAt > bootstrapTimeoutMs || !equal(input.token, bootstrapToken)) {
          return send(response, 401, { message: '開啟連結已失效，請重新啟動精靈' });
        }
        bootstrapUsed = true;
        session = {
          id: randomBytes(32).toString('base64url'), csrf: randomBytes(32).toString('base64url'),
          createdAt: now(), touchedAt: now(),
        };
        const secure = expected.protocol === 'https:' ? '; Secure' : '';
        return send(response, 200, { csrf: session.csrf }, {
          'Set-Cookie': `installer_session=${session.id}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${Math.floor(absoluteTimeoutMs / 1000)}${secure}`,
        });
      }
      const cookies = (request.headers.cookie ?? '').split(';').map((cookie) => cookie.trim());
      const cookie = cookies.find((entry) => entry.startsWith('installer_session='))?.slice('installer_session='.length);
      if (!session || !equal(cookie, session.id)) return send(response, 401, { message: '請使用啟動工具顯示的私人連結開啟精靈' });
      session.touchedAt = now();
      if (request.method === 'GET' && url.pathname === '/api/session') return send(response, 200, { csrf: session.csrf });
      if (request.method === 'GET' && url.pathname === '/api/state') return send(response, 200, manager.snapshot());
      if (request.method === 'GET' && url.pathname === '/api/runs') return send(response, 200, await manager.listRuns());
      if (request.method !== 'POST') return send(response, 405, { message: '不支援此操作' });
      if (!equal(request.headers['x-installer-csrf'], session.csrf)) return send(response, 403, { message: '工作階段驗證失敗' });
      const input = await jsonBody(request);
      if (url.pathname === '/api/cancel') {
        manager.cancel();
        return send(response, 200, { accepted: true });
      }
      if (manager.snapshot().busy) return send(response, 409, { message: '目前步驟尚未結束' });
      let task;
      if (url.pathname === '/api/connect/google') task = manager.connectGoogle();
      else if (url.pathname === '/api/connect/cloudflare') task = manager.connectCloudflare();
      else if (url.pathname === '/api/plan') return send(response, 200, await manager.plan(input));
      else if (url.pathname === '/api/resume') return send(response, 200, await manager.load(input.runId));
      else if (url.pathname === '/api/apply') task = manager.apply(input);
      else return send(response, 404, { message: '找不到操作' });
      // Progress and typed errors are read through /api/state, never raw subprocess output.
      void task.catch(() => {});
      return send(response, 202, { accepted: true });
    } catch (error) {
      if (response.headersSent) return response.destroy();
      const status = error.httpStatus ?? (error.code === 'BUSY' ? 409 : 400);
      send(response, status, error.httpStatus ? { message: error.message } : publicError(error));
    }
  });
  server.requestTimeout = 30_000;
  server.headersTimeout = 10_000;
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  const localOrigin = `http://127.0.0.1:${server.address().port}`;
  try {
    origin = publicOrigin ?? localOrigin;
    const parsed = new URL(origin);
    if (parsed.origin !== origin || parsed.username || parsed.password ||
        (publicOrigin && (parsed.protocol !== 'https:' || !parsed.hostname.endsWith('.cloudshell.dev')))) {
      throw new Error('Public installer origin must be an HTTPS Cloud Shell preview origin');
    }
  } catch (error) { server.close(); throw error; }
  const timer = setInterval(checkExpired, Math.min(idleTimeoutMs, 30_000));
  timer.unref();
  return {
    origin, localOrigin, url: `${origin}/#${bootstrapToken}`,
    async close() {
      if (closed) return;
      closed = true;
      clearInterval(timer);
      await expire();
      server.closeIdleConnections();
      await new Promise((resolve) => server.close(resolve));
    },
  };
}
