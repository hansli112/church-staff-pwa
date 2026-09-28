// Keeps one DevTools connection to the person's Chrome and exposes a tiny
// local command API: node cdpd.mjs  →  POST http://127.0.0.1:9333 {action,...}
import { createServer } from 'node:http';
import { writeFile } from 'node:fs/promises';

const ws = new WebSocket('ws://127.0.0.1:9222/devtools/browser');
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
let id = 0;
const pending = new Map();
const events = [];
ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  else if (msg.method) { events.push({ at: Date.now(), method: msg.method, params: msg.params, sessionId: msg.sessionId }); if (events.length > 300) events.shift(); }
};
ws.onclose = () => { console.log('closed'); process.exit(1); };
const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
  const n = ++id;
  pending.set(n, (msg) => msg.error ? reject(new Error(`${method}: ${msg.error.message}`)) : resolve(msg.result));
  ws.send(JSON.stringify({ id: n, method, params, ...(sessionId ? { sessionId } : {}) }));
});
const sessions = new Map();
let current;
async function session(targetId = current) {
  if (!targetId) throw new Error('no current tab');
  if (!sessions.has(targetId)) {
    const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
    sessions.set(targetId, sessionId);
    await send('Page.enable', {}, sessionId).catch(() => {});
    // Keep rendering and focus behaviour as if visible, without raising the window.
    await send('Emulation.setFocusEmulationEnabled', { enabled: true }, sessionId).catch(() => {});
    await send('Page.setWebLifecycleState', { state: 'active' }, sessionId).catch(() => {});
  }
  return sessions.get(targetId);
}
const pages = async () => (await send('Target.getTargets')).targetInfos.filter((t) => t.type === 'page');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const actions = {
  async tabs() { return (await pages()).map(({ targetId, title, url }) => ({ targetId, current: targetId === current, title, url: url.slice(0, 160) })); },
  async use({ targetId, match }) {
    const all = await pages();
    const found = targetId ? all.find((t) => t.targetId === targetId) : all.find((t) => (t.url + ' ' + t.title).includes(match));
    if (!found) throw new Error('tab not found');
    current = found.targetId;
    return { targetId: current, title: found.title, url: found.url.slice(0, 160) };
  },
  async open({ url }) {
    // A separate window that never takes focus, so the person keeps working.
    const { targetId } = await send('Target.createTarget', { url, newWindow: true, background: true });
    current = targetId;
    return { targetId };
  },
  async navigate({ url }) { await send('Page.navigate', { url }, await session()); return { ok: true }; },
  async shot({ file, scale = 0.6 }) {
    const s = await session();
    const { cssVisualViewport: v } = await send('Page.getLayoutMetrics', {}, s);
    const { data } = await send('Page.captureScreenshot', { format: 'png', clip: { x: v.pageX, y: v.pageY, width: v.clientWidth, height: v.clientHeight, scale } }, s);
    await writeFile(file, Buffer.from(data, 'base64'));
    return { file, cssWidth: v.clientWidth, cssHeight: v.clientHeight, note: `css = image px / ${scale}` };
  },
  async click({ x, y, count = 1 }) {
    const s = await session();
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y }, s);
    for (let i = 1; i <= count; i++) {
      await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: i }, s);
      await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: i }, s);
    }
    return { ok: true };
  },
  async scroll({ x = 400, y = 400, dy }) {
    await send('Input.dispatchMouseEvent', { type: 'mouseWheel', x, y, deltaX: 0, deltaY: dy }, await session());
    return { ok: true };
  },
  async type({ text }) { await send('Input.insertText', { text }, await session()); return { ok: true }; },
  async key({ key }) {
    const s = await session();
    const codes = { Enter: [13, '\r'], Tab: [9, '\t'], Escape: [27, ''], Backspace: [8, ''] };
    const [code, text] = codes[key] ?? [0, key];
    await send('Input.dispatchKeyEvent', { type: 'keyDown', key, windowsVirtualKeyCode: code, ...(text ? { text } : {}) }, s);
    await send('Input.dispatchKeyEvent', { type: 'keyUp', key, windowsVirtualKeyCode: code }, s);
    return { ok: true };
  },
  // Visible text of the top document only (what a person reads), trimmed.
  async text({ tail = 0 } = {}) {
    const cut = tail ? `slice(-${Number(tail)})` : 'slice(0, 6000)';
    const { result } = await send('Runtime.evaluate', { expression: `document.body ? document.body.innerText.${cut} : ""`, returnByValue: true }, await session());
    return { text: result.value };
  },
  // Locate visible elements by their text/label, like a person scanning the page.
  async find({ text }) {
    const expression = `(() => { const want = ${JSON.stringify(text)}; const out = [];
      for (const el of document.querySelectorAll('a,button,input,select,textarea,label,summary,[role=button],[role=link],[role=tab],[role=menuitem],img,span,div,li,h1,h2,h3,p,td')) {
        const label = (el.innerText || el.value || el.getAttribute('aria-label') || el.alt || el.title || '').trim();
        if (!label.includes(want) || label.length > want.length + 60) continue;
        const r = el.getBoundingClientRect(); if (!r.width || !r.height || r.bottom < 0 || r.top > innerHeight) continue;
        out.push({ tag: el.tagName, label: label.slice(0, 80), x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2), w: Math.round(r.width), h: Math.round(r.height) });
      } return out.slice(-8); })()`;
    const { result } = await send('Runtime.evaluate', { expression, returnByValue: true }, await session());
    return result.value;
  },
  async eval({ expression }) {
    const { result } = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }, await session());
    return result.value;
  },
  // Raw protocol call for anything else, so this helper never needs a restart.
  async cdp({ method, params = {}, target }) { return send(method, params, target === 'browser' ? undefined : await session()); },
  async events({ since = 0, match = '' }) { return events.filter((e) => e.at > since && e.method.includes(match)).map(({ at, method, params, sessionId }) => ({ at, method, sessionId, params: JSON.stringify(params).slice(0, 600) })); },
  async close({ targetId }) { await send('Target.closeTarget', { targetId }); return { ok: true }; },
  async wait({ ms }) { await sleep(ms); return { ok: true }; },
};
await send('Target.setDiscoverTargets', { discover: true });

createServer(async (req, res) => {
  let body = '';
  for await (const chunk of req) body += chunk;
  try {
    const input = JSON.parse(body || '{}');
    const result = await actions[input.action](input);
    res.end(JSON.stringify(result));
  } catch (error) { res.statusCode = 500; res.end(JSON.stringify({ error: error.message })); }
}).listen(9333, '127.0.0.1', () => console.log('cdpd ready'));
