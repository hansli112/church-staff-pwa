/* The release is the one that booted this page, never the server's latest. */
(() => {
  'use strict';
  const boot = window.marthaBootRelease;
  const supported = !!boot && boot.schema === 1 && /^[0-9a-f]{20}$/.test(boot.id) && 'serviceWorker' in navigator;
  let registration;
  let starting;
  let staged;
  let editing = false;
  const usedAssets = () => performance.getEntriesByType('resource').map((entry) => entry.name).filter((name) => {
    const url = new URL(name);
    // The main entries this browser ran (JS, or wasm and its module) and its
    // engine; the worker keeps only same-origin files of this release.
    return url.pathname.includes(`/releases/${boot.id}/canvaskit/`) || /^\/main\.dart\.[0-9a-f]{10}\.(?:js|wasm|mjs)$/.test(url.pathname) ||
      url.origin === 'https://www.gstatic.com' && /^\/firebasejs\/\d+\.\d+\.\d+\/firebase-[A-Za-z-]+\.js$/.test(url.pathname) ||
      url.origin === 'https://fonts.gstatic.com' && /^\/s\/(?:notosanstc|notosanssc|roboto)\/v\d+\/[A-Za-z0-9_.-]+\.woff2?$/.test(url.pathname);
  });
  async function send(type, data) {
    const reg = await start();
    const worker = reg.active || reg.waiting || reg.installing;
    if (!worker) throw new Error('App shell is not ready');
    return new Promise((resolve, reject) => {
      const channel = new MessageChannel();
      const timeout = setTimeout(() => { channel.port1.close(); reject(new Error('Update request did not complete')); }, 60000);
      channel.port1.onmessage = (event) => {
        clearTimeout(timeout);
        channel.port1.close();
        if (event.data?.ok) resolve(event.data);
        else reject(new Error(event.data?.error || 'Update failed'));
      };
      worker.postMessage({ type, ...data }, [channel.port2]);
    });
  }
  async function start() {
    if (!supported) throw new Error('Updates are unavailable in this build');
    if (registration) return registration;
    if (!starting) starting = navigator.serviceWorker.register('/martha_app_sw.js', { scope: '/', updateViaCache: 'none' }).then(async (reg) => {
      if (!reg.active) {
        const worker = reg.installing || reg.waiting;
        if (!worker) throw new Error('App shell installation failed');
        await new Promise((resolve, reject) => {
          const changed = () => {
            if (worker.state === 'activated') { worker.removeEventListener('statechange', changed); resolve(); }
            else if (worker.state === 'redundant') { worker.removeEventListener('statechange', changed); reject(new Error('App shell installation failed')); }
          };
          worker.addEventListener('statechange', changed);
          changed();
        });
      }
      registration = reg;
      return reg;
    }).catch((error) => { starting = null; throw error; });
    return starting;
  }
  window.marthaUpdate = Object.freeze({
    runningVersion: supported ? boot.id : 'development',
    supported,
    setEditing(value) { editing = value === true; },
    async check() {
      const result = await send('CHECK', { project: boot.project, runningId: boot.id });
      staged = result.available ? result.release : undefined;
      return { available: result.available === true, version: result.release?.id || boot.id };
    },
    async activate() {
      const focused = document.activeElement;
      if (editing || focused?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(focused?.tagName || '') ||
          !/^\/(?:c\/[^/]+\/)?me\/?$/.test(window.location.pathname)) throw new Error('Finish editing before updating');
      if (!staged) throw new Error('Check for an update first');
      await send('APPLY', { release: staged, safe: true });
    },
    reload() {
      const focused = document.activeElement;
      if (editing || focused?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(focused?.tagName || '') ||
          !/^\/(?:c\/[^/]+\/)?me\/?$/.test(window.location.pathname)) throw new Error('Finish editing before updating');
      window.location.reload();
    },
    async apply() { await window.marthaUpdate.activate(); window.marthaUpdate.reload(); },
  });
  if (!supported) return;
  // Registration/downloads begin only after the first usable destination has
  // removed its splash, then yield to browser idle work. Never on visibility.
  const ready = () => {
    if (document.getElementById('splash')) return false;
    const install = () => send('INIT', { boot, used: usedAssets() }).catch((error) => {
      console.warn('Offline app shell is unavailable:', error.message);
    });
    if (window.requestIdleCallback) window.requestIdleCallback(install);
    else setTimeout(install, 1500);
    return true;
  };
  if (!ready()) {
    const observer = new MutationObserver(() => { if (ready()) observer.disconnect(); });
    observer.observe(document.body, { childList: true, subtree: true });
  }
})();
