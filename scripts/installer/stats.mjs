import { randomUUID } from 'node:crypto';

// Anonymous progress counts (stats-worker/): how many wizards open, start,
// stop at which step and code, and finish. Never names, emails or project IDs.
// Fire and forget: a slow, blocked or failing endpoint never touches the install.
export const STATS_URL = 'https://church-install-stats.zhuweichurch.workers.dev/event';
const CODE = /^[A-Z][A-Z0-9_]{0,59}$/;

export function createStatsReporter({ url = STATS_URL, revision, fetchImpl = fetch, session = randomUUID() } = {}) {
  return (event, { runId, step, code } = {}) => {
    const body = JSON.stringify({ event, session, runId, step, code: code && (CODE.test(code) ? code : 'OTHER'), revision });
    try {
      Promise.resolve(fetchImpl(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body, signal: AbortSignal.timeout(5000) }))
        .catch(() => {});
    } catch { /* Never let counting affect the install. */ }
  };
}
