import { Timestamp } from 'firebase-admin/firestore';

import { dateKeyUtc8, DAY_MS, type Deps } from './common.js';
import { BY_THE_BACKEND } from './stats.js';

/**
 * 週報: the last full Monday–Sunday (Taipei) against the week before, as one
 * email to the operator. Firestore for churches and rosters; GA4 and Search
 * Console read as [Analytics.reader], a service account the runtime
 * impersonates, so no key file.
 */
export interface Analytics {
  /** A token of the runtime's own credentials, to impersonate [reader]. */
  accessToken: () => Promise<string>;
  reader: string;
  ga4Property: string;
  gscSite: string;
  /** Sent as x-goog-user-project: the project the API calls are billed to. */
  project: string;
}
export interface WeeklyReportDeps extends Deps {
  /** null where GA4 and Search Console are not read (tests, a preview of dev). */
  analytics: Analytics | null;
}
export interface Mail {
  subject: string;
  html: string;
  text: string;
}

// ---------------------------------------------------------------- weeks

const shift = (key: string, days: number) =>
  new Date(new Date(`${key}T00:00:00Z`).getTime() + days * DAY_MS).toISOString().slice(0, 10);
const at = (key: string) => new Date(`${key}T00:00:00+08:00`);
interface Week {
  from: string;
  to: string;
}
const inWeek = (key: string | undefined, w: Week) => !!key && key >= w.from && key <= w.to;
const dayOf = (t: unknown) => (t instanceof Timestamp ? dateKeyUtc8(t.toDate()) : undefined);
const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);
const count = <T>(xs: T[], f: (x: T) => boolean) => xs.filter(f).length;

/** The Sunday (Taipei) of the last full week before [now]. */
export function lastSunday(now: Date) {
  const today = dateKeyUtc8(now);
  return shift(today, -(new Date(`${today}T00:00:00Z`).getUTCDay() || 7));
}

// ---------------------------------------------------------------- data

interface Church {
  name: string;
  members: number;
  edits: number;
  editsBefore: number;
  created?: string;
}
type Pair = [number, number];
interface Ga {
  active: Pair;
  platforms: { label: string; active: Pair; fresh: Pair }[];
  events: { label: string; count: Pair }[];
  countries: { name: string; n: number }[];
  sources: { name: string; n: number }[];
  /** New users by phone language, this week and the last 4 weeks; most first. */
  languages: { name: string; supported: boolean; n: Pair }[];
}
interface Gsc {
  now: GscTotals;
  before: GscTotals;
  queries: { query: string; clicks: number; impressions: number; position: number }[];
}
interface GscTotals {
  clicks: number;
  impressions: number;
  ctr: number;
  position: number;
}
export interface WeeklyReport {
  now: Week;
  before: Week;
  made: string;
  users: Pair;
  churches: Pair;
  openedApp: [number | undefined, number | undefined];
  newUsers: Pair;
  newUsersByDay: number[];
  fresh: { count: number; before: number; invited: number; planned: number; tenPlus: number; biggest: Church[] };
  editing: Pair;
  busiest: Church[];
  quiet: Church[];
  paid: { count: number; amount: number };
  ga: Ga | null;
  gsc: Gsc | null;
}

export async function collectWeeklyReport(d: WeeklyReportDeps, end = lastSunday(d.now())): Promise<WeeklyReport> {
  const { db } = d;
  const now: Week = { from: shift(end, -6), to: end };
  const before: Week = { from: shift(end, -13), to: shift(end, -7) };
  const days = Array.from({ length: 14 }, (_, i) => shift(before.from, i));

  const [statsNow, statsBefore, users, churches, members, rosters, orders, analytics] = await Promise.all([
    db.doc(`stats/${now.to}`).get(),
    db.doc(`stats/${before.to}`).get(),
    db.collection('users').select('createdAt').get(),
    db.collection('churches').select('name', 'status', 'createdAt').get(),
    db.collectionGroup('members').select('uid').get(),
    db.collectionGroup('rosters')
      .where('updatedAt', '>=', Timestamp.fromDate(at(before.from)))
      .where('updatedAt', '<', Timestamp.fromDate(at(shift(end, 1))))
      .select('via', 'updatedAt')
      .get(),
    db.collection('ecpayOrders').where('status', '==', 'paid').select('amount', 'paidAt').get(),
    d.analytics ? readAnalytics(d, d.analytics, now, before) : Promise.resolve(null),
  ]);

  const stat = (field: string): [number | undefined, number | undefined] => [statsNow.get(field), statsBefore.get(field)];
  const userDays = users.docs.map((u) => dayOf(u.get('createdAt')));
  const newUsersByDay = days.map((k) => userDays.filter((u) => u === k).length);

  const byId = new Map<string, Church & { active: boolean }>();
  for (const c of churches.docs) {
    byId.set(c.id, { name: c.get('name') ?? c.id, active: c.get('status') === 'active', created: dayOf(c.get('createdAt')), members: 0, edits: 0, editsBefore: 0 });
  }
  for (const m of members.docs) {
    const c = byId.get(m.ref.parent.parent!.id);
    if (c) c.members++;
  }
  for (const r of rosters.docs) {
    if (BY_THE_BACKEND.has(r.get('via'))) continue;
    const c = byId.get(r.ref.parent.parent!.id);
    const day = dayOf(r.get('updatedAt'));
    if (!c || !day) continue;
    if (inWeek(day, now)) c.edits++;
    else c.editsBefore++;
  }
  const active = [...byId.values()].filter((c) => c.active);
  const fresh = active.filter((c) => inWeek(c.created, now));
  const paid = orders.docs.filter((o) => inWeek(dayOf(o.get('paidAt')), now));
  const plain = ({ name, members, edits, editsBefore }: Church): Church => ({ name, members, edits, editsBefore });

  return {
    now,
    before,
    made: dateKeyUtc8(d.now()),
    users: [count(userDays, (u) => !u || u <= now.to), count(userDays, (u) => !u || u <= before.to)],
    churches: [count(active, (c) => !c.created || c.created <= now.to), count(active, (c) => !c.created || c.created <= before.to)],
    openedApp: stat('users_active_7d'),
    newUsers: [sum(newUsersByDay.slice(7)), sum(newUsersByDay.slice(0, 7))],
    newUsersByDay,
    fresh: {
      count: fresh.length,
      before: active.filter((c) => inWeek(c.created, before)).length,
      invited: fresh.filter((c) => c.members >= 2).length,
      planned: fresh.filter((c) => c.edits > 0).length,
      tenPlus: fresh.filter((c) => c.members >= 10).length,
      biggest: [...fresh].sort((a, b) => b.members - a.members).slice(0, 5).map(plain),
    },
    editing: [active.filter((c) => c.edits > 0).length, active.filter((c) => c.editsBefore > 0).length],
    busiest: active.filter((c) => c.edits > 0).sort((a, b) => b.edits - a.edits).slice(0, 10).map(plain),
    quiet: active.filter((c) => c.editsBefore > 0 && c.edits === 0).sort((a, b) => b.editsBefore - a.editsBefore).map(plain),
    paid: { count: paid.length, amount: sum(paid.map((o) => Number(o.get('amount') ?? 0))) },
    ga: analytics?.ga ?? null,
    gsc: analytics?.gsc ?? null,
  };
}

// ---------------------------------------------------------------- GA4 and Search Console

const KEY_EVENTS: [string, string][] = [
  ['church_create', '建立教會'], ['join_group', '加入教會'], ['roster_edit', '改服事表'], ['roster_import', '匯入服事表'],
  ['roster_notify', '通知同工'], ['swap_ask', '找人代或交換'], ['attendance_report', '回報人數'], ['support_paid', '支持'],
];
const PLATFORMS: [string, string][] = [['iOS', 'iOS'], ['Android', 'Android'], ['web', '網頁']];
const SOURCES: [RegExp, string][] = [
  [/^\(direct\)$/, '直接開啟'], [/google-play/, 'Google Play'], [/facebook|^fb$/, 'Facebook'],
  [/instagram|^ig$/, 'Instagram'], [/threads/, 'Threads'], [/google/, 'Google 搜尋'], [/line/i, 'LINE'],
  [/youtube/, 'YouTube'], [/^\(not set\)$/, '其他'],
];
const SHORT_REGIONS: Record<string, string> = { HK: '香港', MO: '澳門', TW: '台灣', CN: '中國' };
/** Languages the app speaks, by the first part of the code. */
const APP_LANGUAGES = new Set(['zh', 'en', 'ja', 'ko']);
const LANGUAGE_NAMES = new Intl.DisplayNames(['zh-Hant'], { type: 'language' });
/** zh-tw and zh-hant-hk are one language, en-us and en-gb another. */
function languageOf(code: string): { name: string; supported: boolean } | null {
  const c = code.toLowerCase();
  if (!c || c === '(not set)') return null;
  const base = c.split(/[-_]/)[0];
  // As the app reads it (AppLanguage.of): Simplified when it says so or comes
  // from China, Singapore or Malaysia without saying Traditional; else
  // Traditional, plain zh too.
  if (base === 'zh') return { name: /hans/.test(c) || (!/hant/.test(c) && /-(cn|sg|my)\b/.test(c)) ? '簡體中文' : '繁體中文', supported: true };
  let name = base;
  try {
    name = LANGUAGE_NAMES.of(base) ?? base;
  } catch {
    // not a language code GA4 should send; show it as it is
  }
  return { name, supported: APP_LANGUAGES.has(base) };
}

async function readAnalytics(d: Deps, a: Analytics, now: Week, before: Week): Promise<{ ga: Ga; gsc: Gsc }> {
  const post = async <T>(url: string, token: string, body: unknown): Promise<T> => {
    const res = await d.fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', 'x-goog-user-project': a.project },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`${url}: ${res.status} ${await res.text()}`);
    return (await res.json()) as T;
  };
  const { accessToken } = await post<{ accessToken: string }>(
    `https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${a.reader}:generateAccessToken`,
    await a.accessToken(),
    { scope: ['https://www.googleapis.com/auth/analytics.readonly', 'https://www.googleapis.com/auth/webmasters.readonly'], lifetime: '600s' },
  );

  type GaRow = { dimensionValues?: { value: string }[]; metricValues: { value: string }[] };
  /** Per value of [dimension], each metric as [this week, last week]. */
  const ga = async (dimension: string | null, metrics: string[], extra: object = {}) => {
    const r = await post<{ rows?: GaRow[] }>(`https://analyticsdata.googleapis.com/v1beta/properties/${a.ga4Property}:runReport`, accessToken, {
      dateRanges: [{ startDate: now.from, endDate: now.to }, { startDate: before.from, endDate: before.to }],
      dimensions: dimension ? [{ name: dimension }] : [],
      metrics: metrics.map((name) => ({ name })),
      limit: 250,
      ...extra,
    });
    const out = new Map<string, Pair[]>();
    for (const row of r.rows ?? []) {
      const dims = (row.dimensionValues ?? []).map((v) => v.value);
      const key = dimension ? dims[0] : '';
      const w = dims[dims.length - 1] === 'date_range_1' ? 1 : 0;
      const v = out.get(key) ?? metrics.map((): Pair => [0, 0]);
      row.metricValues.forEach((m, i) => (v[i][w] = Number(m.value)));
      out.set(key, v);
    }
    return out;
  };
  type GscRow = { keys?: string[] } & GscTotals;
  const gsc = (w: Week, dimensions: string[] = [], rowLimit = 10) =>
    post<{ rows?: GscRow[] }>(`https://searchconsole.googleapis.com/webmasters/v3/sites/${encodeURIComponent(a.gscSite)}/searchAnalytics/query`, accessToken, {
      startDate: w.from, endDate: w.to, dimensions, rowLimit,
    }).then((r) => r.rows ?? []);

  const fourWeeks = { startDate: shift(now.to, -27), endDate: now.to };
  const [total, platform, events, country, source, language, gNow, gBefore, queries] = await Promise.all([
    ga(null, ['activeUsers']),
    ga('platform', ['activeUsers', 'newUsers']),
    ga('eventName', ['eventCount'], { dimensionFilter: { filter: { fieldName: 'eventName', inListFilter: { values: KEY_EVENTS.map(([e]) => e) } } } }),
    ga('countryId', ['newUsers']),
    ga('sessionSource', ['newUsers']),
    // [this week, the last 4 weeks] in place of [this week, last week]
    ga('languageCode', ['newUsers'], { dateRanges: [{ startDate: now.from, endDate: now.to }, fourWeeks] }),
    gsc(now),
    gsc(before),
    gsc(now, ['query'], 8),
  ]);

  const regions = new Intl.DisplayNames(['zh-Hant'], { type: 'region' });
  const top = (m: Map<string, number>, n: number) =>
    [...m].map(([name, v]) => ({ name, n: v })).filter((x) => x.n > 0).sort((x, y) => y.n - x.n).slice(0, n);
  const countries = new Map<string, number>();
  for (const [id, [[n]]] of country) {
    const name = id && id !== '(not set)' ? (SHORT_REGIONS[id] ?? regions.of(id) ?? id) : '其他';
    countries.set(name, (countries.get(name) ?? 0) + n);
  }
  const sources = new Map<string, number>();
  for (const [src, [[n]]] of source) {
    const name = SOURCES.find(([re]) => re.test(src))?.[1] ?? src;
    sources.set(name, (sources.get(name) ?? 0) + n);
  }
  const languages = new Map<string, { name: string; supported: boolean; n: Pair }>();
  for (const [code, [[n, n4]]] of language) {
    const l = languageOf(code) ?? { name: '其他', supported: true };
    const e = languages.get(l.name) ?? { ...l, n: [0, 0] as Pair };
    e.n = [e.n[0] + n, e.n[1] + n4];
    languages.set(l.name, e);
  }
  const ranked = [...languages.values()].filter((l) => l.n[1] > 0 && l.name !== '其他').sort((x, y) => y.n[1] - x.n[1]);
  const rest = [...ranked.slice(8), ...(languages.has('其他') ? [languages.get('其他')!] : [])];
  const totals = (rows: GscRow[]): GscTotals => rows[0] ?? { clicks: 0, impressions: 0, ctr: 0, position: 0 };
  return {
    ga: {
      active: total.get('')?.[0] ?? [0, 0],
      platforms: PLATFORMS.map(([key, label]) => {
        const v = platform.get(key) ?? [[0, 0], [0, 0]];
        return { label, active: v[0], fresh: v[1] };
      }),
      events: KEY_EVENTS.map(([e, label]) => ({ label, count: events.get(e)?.[0] ?? [0, 0] })),
      countries: top(countries, 8),
      sources: top(sources, 6),
      languages: [
        ...ranked.slice(0, 8),
        ...(rest.length ? [{ name: '其他', supported: true, n: [sum(rest.map((l) => l.n[0])), sum(rest.map((l) => l.n[1]))] as Pair }] : []),
      ],
    },
    gsc: {
      now: totals(gNow),
      before: totals(gBefore),
      queries: queries.map((q) => ({ query: q.keys![0], clicks: q.clicks, impressions: q.impressions, position: q.position })),
    },
  };
}

// ---------------------------------------------------------------- email
// Gmail keeps inline styles and tables, not SVG, flex or grid: every bar
// is a table cell or a div with a width, and every style is inline.

const C = {
  bg: '#f2f2f7', card: '#ffffff', label: '#000000', label2: '#5c5c62', label3: '#8a8a8f', sep: '#e5e5ea',
  fill: '#ececf0', accent: '#1f5fd1', accentSoft: '#e3ecfb', good: '#1e7b34', bad: '#c81e1e', muted: '#c7c7cc',
  series: ['#2a78d6', '#eb6834', '#1baf7a'],
};
const FONT = `-apple-system,BlinkMacSystemFont,'PingFang TC','Noto Sans TC','Microsoft JhengHei',Helvetica,Arial,sans-serif`;
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);
const num = (n: number) => n.toLocaleString('en-US');
const md = (key: string) => `${Number(key.slice(5, 7))}月${Number(key.slice(8))}日`;
const pct = (a: number, b: number) => (b ? `${Math.round((a / b) * 100)}%` : '—');
const T = (style: string, inner: string) => `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;${style}">${inner}</table>`;

function delta(a: number | undefined, b: number | undefined, fmt: (n: number) => string = num, lowerBetter = false) {
  if (a == null || b == null) return span(C.label3, '上週沒有資料');
  if (a === b) return span(C.label3, '和上週一樣');
  const better = lowerBetter ? a < b : a > b;
  return span(better ? C.good : C.bad, `${a > b ? '▲' : '▼'} ${fmt(Math.abs(a - b))}`);
}
const span = (color: string, text: string, size = 13) => `<span style="color:${color};font-size:${size}px;font-weight:500">${text}</span>`;

function card(title: string, body: string, note = '') {
  const head = title
    ? `<div style="font-size:17px;font-weight:600;margin:0 0 16px">${title}${note ? `<span style="font-size:13px;font-weight:400;color:${C.label3};margin-left:8px">${note}</span>` : ''}</div>`
    : '';
  return `<tr><td style="background:${C.card};border-radius:16px;padding:20px">${head}${body}</td></tr><tr><td height="16" style="font-size:0;line-height:0">&nbsp;</td></tr>`;
}
const group = (title: string) =>
  `<tr><td style="padding:24px 0 12px;font-size:22px;font-weight:700">${title}</td></tr>`;
const sub = (text: string, top = 20) => `<div style="font-size:13px;color:${C.label3};margin:${top}px 0 6px">${text}</div>`;
const empty = (text: string) => `<div style="font-size:15px;color:${C.label3}">${text}</div>`;

function bar(share: number, color = C.accent, track = C.fill) {
  const w = Math.max(0, Math.min(100, share * 100));
  return `<div style="background:${track};border-radius:4px;height:8px;line-height:8px;font-size:0">${w > 0 ? `<div style="width:${w.toFixed(1)}%;min-width:4px;background:${color};border-radius:4px;height:8px;line-height:8px;font-size:0">&nbsp;</div>` : '&nbsp;'}</div>`;
}

function tiles(items: { label: string; value: string; delta: string }[]) {
  const cell = (t: { label: string; value: string; delta: string }) =>
    `<td width="50%" valign="top" style="padding:4px 0 12px">
<div style="font-size:13px;color:${C.label2}">${t.label}</div>
<div style="font-size:30px;font-weight:700;line-height:1.25;margin:4px 0 2px">${t.value}</div>${t.delta}</td>`;
  const rows: string[] = [];
  for (let i = 0; i < items.length; i += 2) rows.push(`<tr>${cell(items[i])}${items[i + 1] ? cell(items[i + 1]) : '<td></td>'}</tr>`);
  return T('', rows.join(''));
}

function dailyBars(r: WeeklyReport) {
  const max = Math.max(1, ...r.newUsersByDay);
  const peak = r.newUsersByDay.indexOf(max);
  const days = Array.from({ length: 14 }, (_, i) => shift(r.before.from, i));
  const cols = r.newUsersByDay.map((v, i) => {
    const h = v ? Math.max(4, Math.round((v / max) * 110)) : 0;
    const color = i >= 7 ? C.accent : C.muted;
    return `<td valign="bottom" align="center" style="height:130px;padding:0 2px" title="${md(days[i])} ${v} 位">
${i === peak ? `<div style="font-size:12px;font-weight:600;margin-bottom:4px">${num(v)}</div>` : ''}
${h ? `<div style="height:${h}px;line-height:${h}px;font-size:0;background:${color};border-radius:4px 4px 0 0">&nbsp;</div>` : ''}</td>`;
  });
  const labels = days.map((_, i) => `<td align="center" style="font-size:11px;color:${C.label3};padding-top:6px;border-top:1px solid ${C.sep}">${'一二三四五六日'[i % 7]}</td>`);
  const legend = (color: string, text: string) =>
    `<span style="display:inline-block;width:10px;height:10px;border-radius:3px;background:${color};margin-right:6px;vertical-align:-1px"></span><span style="margin-right:20px">${text}</span>`;
  return `${T('table-layout:fixed', `<tr>${cols.join('')}</tr><tr>${labels.join('')}</tr>`)}
<div style="font-size:13px;color:${C.label2};margin-top:10px">${legend(C.accent, '這週')}${legend(C.muted, '上週')}</div>`;
}

function meter(label: string, n: number, of: number) {
  return `<tr><td style="font-size:15px;padding:6px 12px 6px 0;white-space:nowrap" width="100">${label}</td>
<td style="padding:6px 0">${bar(of ? n / of : 0, C.accent, C.accentSoft)}</td>
<td align="right" style="padding:6px 0 6px 12px;white-space:nowrap" width="90"><b style="font-size:17px">${num(n)}</b> ${span(C.label3, pct(n, of))}</td></tr>`;
}

function rank(list: Church[], value: (c: Church) => number, note: (c: Church) => string) {
  const max = Math.max(1, ...list.map(value));
  return T('', list.map((c, i) => `<tr>
<td style="padding:10px 0;${i ? `border-top:1px solid ${C.sep};` : ''}font-size:15px">
<span style="color:${C.label3};display:inline-block;width:22px">${i + 1}</span>${esc(c.name)}
<div style="font-size:13px;color:${C.label3};padding-left:22px">${note(c)}</div></td>
<td width="28%" style="padding:10px 12px;${i ? `border-top:1px solid ${C.sep};` : ''}">${bar(value(c) / max)}</td>
<td width="44" align="right" style="padding:10px 0;${i ? `border-top:1px solid ${C.sep};` : ''}font-weight:600;font-size:15px">${num(value(c))}</td></tr>`).join(''));
}

function hbars(list: { name: string; n: number }[]) {
  const max = Math.max(1, ...list.map((x) => x.n));
  return T('', list.map((x) => `<tr><td width="100" style="font-size:15px;padding:5px 12px 5px 0;white-space:nowrap">${esc(x.name)}</td>
<td style="padding:5px 0">${bar(x.n / max)}</td><td width="56" align="right" style="font-weight:600;font-size:15px;padding:5px 0">${num(x.n)}</td></tr>`).join(''));
}

function table(head: string[], rows: string[][]) {
  const th = head.map((h, i) => `<td ${i ? 'align="right"' : ''} style="font-size:13px;color:${C.label3};padding:0 0 6px ${i ? '12px' : '0'}">${h}</td>`).join('');
  const tr = rows.map((r) => `<tr>${r.map((c, i) => `<td ${i ? 'align="right"' : ''} valign="top" style="font-size:15px;padding:10px 0 10px ${i ? '12px' : '0'};border-top:1px solid ${C.sep};line-height:1.35">${c}</td>`).join('')}</tr>`).join('');
  return T('', `<tr>${th}</tr>${tr}`);
}

function gaSections(ga: Ga) {
  const sum0 = sum(ga.platforms.map((p) => p.active[0]));
  const parts = ga.platforms.map((p, i) => ({ ...p, color: C.series[i] })).filter((p) => p.active[0] > 0);
  const seg = parts.map((p) => {
    const share = p.active[0] / sum0;
    return `<td width="${(share * 100).toFixed(1)}%" style="background:${p.color};height:28px;border-radius:4px;color:#fff;font-size:13px;font-weight:600;padding-left:8px;white-space:nowrap">${share >= 0.12 ? `${Math.round(share * 100)}%` : ''}</td>`;
  }).join('<td width="2" style="font-size:0">&nbsp;</td>');
  const dot = (color: string) => `<span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${color};margin-right:8px"></span>`;
  const platformRows = ga.platforms.map((p, i) => [
    `${dot(C.series[i])}${p.label}`,
    `${num(p.active[0])}<br>${delta(p.active[0], p.active[1])}`,
    `${num(p.fresh[0])}<br>${delta(p.fresh[0], p.fresh[1])}`,
  ]);
  return [
    group('App 與網站'),
    card(`活躍使用者 ${num(ga.active[0])}`, `${sum0 ? T('table-layout:fixed', `<tr>${seg}</tr>`) : ''}
<div style="height:12px"></div>${table(['', '活躍', '新使用者'], platformRows)}`, `上週 ${num(ga.active[1])}`),
    card('大家做了什麼', table(['', '這週', '上週'], ga.events.map((e) => [e.label, num(e.count[0]), `<span style="color:${C.label3}">${num(e.count[1])}</span>`]))),
    card('新使用者從哪來', `${sub('國家', 0)}${hbars(ga.countries)}${sub('來源')}${hbars(ga.sources)}`),
    ga.languages.length ? card('新使用者的手機語言', languageRows(ga.languages)) : '',
  ].join('');
}

function languageRows(list: Ga['languages']) {
  const max = Math.max(1, ...list.map((l) => l.n[1]));
  const tag = `<span style="font-size:11px;color:${C.label2};background:${C.fill};border-radius:4px;padding:1px 5px;margin-left:6px;vertical-align:1px">尚未支援</span>`;
  const head = `<tr><td></td><td></td><td align="right" style="font-size:13px;color:${C.label3};padding:0 0 6px 12px;white-space:nowrap">這週</td><td align="right" style="font-size:13px;color:${C.label3};padding:0 0 6px 12px;white-space:nowrap">近 4 週</td></tr>`;
  return T('', head + list.map((l) => `<tr><td style="font-size:15px;padding:5px 12px 5px 0;white-space:nowrap">${esc(l.name)}${l.supported ? '' : tag}</td>
<td width="30%" style="padding:5px 0">${bar(l.n[1] / max)}</td>
<td width="48" align="right" style="font-weight:600;font-size:15px;padding:5px 0">${num(l.n[0])}</td>
<td width="60" align="right" style="font-size:15px;color:${C.label2};padding:5px 0">${num(l.n[1])}</td></tr>`).join(''));
}

function gscSection(g: Gsc) {
  const pct1 = (n: number) => `${(n * 100).toFixed(1)}%`;
  const pos = (n: number) => n.toFixed(1);
  const queries = g.queries.length
    ? table(['搜尋字詞', '點擊', '曝光', '排名'], g.queries.map((q) => [esc(q.query), num(q.clicks), `<span style="color:${C.label3}">${num(q.impressions)}</span>`, `<span style="color:${C.label3}">${pos(q.position)}</span>`]))
    : empty('沒有搜尋字詞');
  return group('Google 搜尋') + card('', `${tiles([
    { label: '點擊', value: num(g.now.clicks), delta: delta(g.now.clicks, g.before.clicks) },
    { label: '曝光', value: num(g.now.impressions), delta: delta(g.now.impressions, g.before.impressions) },
    { label: '點閱率', value: pct1(g.now.ctr), delta: g.before.impressions ? delta(g.now.ctr, g.before.ctr, pct1) : delta(1, undefined) },
    { label: '平均排名', value: pos(g.now.position), delta: g.before.impressions ? delta(g.now.position, g.before.position, pos, true) : delta(1, undefined) },
  ])}<div style="height:8px"></div>${queries}`);
}

export function weeklyMail(r: WeeklyReport): Mail {
  const sameMonth = r.now.from.slice(5, 7) === r.now.to.slice(5, 7);
  const range = `${md(r.now.from)} – ${sameMonth ? `${Number(r.now.to.slice(8))}日` : md(r.now.to)}`;
  const opened = r.openedApp[0];
  const body = [
    `<tr><td style="padding:0 0 24px">
<div style="font-size:13px;font-weight:600;color:${C.accent}">馬大別忙週報</div>
<div style="font-size:28px;font-weight:700;line-height:1.2;margin-top:4px">${range}</div>
<div style="margin-top:28px;font-size:56px;font-weight:700;line-height:1;letter-spacing:-1px">${num(r.newUsers[0])}<span style="font-size:20px;font-weight:600;letter-spacing:0;margin-left:8px">位新使用者</span></div>
<div style="margin-top:10px">${span(C.label3, `上週 ${num(r.newUsers[1])} 位`, 15)}</div></td></tr>`,
    card('', tiles([
      { label: '使用者', value: num(r.users[0]), delta: delta(r.users[0], r.users[1]) },
      { label: '使用中的教會', value: num(r.churches[0]), delta: delta(r.churches[0], r.churches[1]) },
      { label: '7 天內打開過 App', value: opened == null ? '—' : num(opened), delta: opened == null ? span(C.label3, '還沒有資料') : delta(opened, r.openedApp[1]) },
      { label: '有人排服事表的教會', value: num(r.editing[0]), delta: delta(r.editing[0], r.editing[1]) },
    ])),
    card('每天的新使用者', dailyBars(r)),
    group('教會與服事表'),
    card(`新教會 ${num(r.fresh.count)} 間`, r.fresh.count
      ? `${T('', meter('邀了第二個人', r.fresh.invited, r.fresh.count) + meter('排了服事表', r.fresh.planned, r.fresh.count) + meter('10 人以上', r.fresh.tenPlus, r.fresh.count))}
${sub('人數最多')}${rank(r.fresh.biggest, (c) => c.members, (c) => `改了 ${c.edits} 份服事表`)}`
      : empty('沒有新教會'), r.fresh.before ? `上週 ${num(r.fresh.before)} 間` : ''),
    card('改最多服事表的教會', r.busiest.length
      ? rank(r.busiest, (c) => c.edits, (c) => `${c.members} 人${c.editsBefore ? `・上週 ${c.editsBefore} 份` : ''}`)
      : empty('沒有人改服事表')),
    card('上週有排、這週停了', r.quiet.length
      ? T('', r.quiet.map((c, i) => `<tr><td style="font-size:15px;padding:10px 0;${i ? `border-top:1px solid ${C.sep}` : ''}">${esc(c.name)}</td>
<td align="right" style="font-size:13px;color:${C.label3};padding:10px 0;white-space:nowrap;${i ? `border-top:1px solid ${C.sep}` : ''}">上週 ${c.editsBefore} 份・${c.members} 人</td></tr>`).join(''))
      : empty('沒有')),
    r.ga ? gaSections(r.ga) : '',
    r.gsc ? gscSection(r.gsc) : '',
    r.ga || r.gsc ? '<tr><td height="8"></td></tr>' : '',
    card('網站線上支持', r.paid.count
      ? `<b style="font-size:28px;margin-right:10px">NT$${num(r.paid.amount)}</b>${span(C.label3, `${r.paid.count} 筆`)}`
      : empty('沒有')),
    `<tr><td style="font-size:12px;color:${C.label3};line-height:1.7;padding-top:8px">
服事表只算有人動手改的，不算 Google 日曆同步、改時區、復原和搬家。App 內購看商店後台。${r.gsc ? 'Google 搜尋的資料晚兩三天，最後幾天可能還沒算進來。' : ''}<br>
資料到 ${md(r.now.to)}，${md(r.made)}產生</td></tr>`,
  ].join('\n');

  const html = `<!doctype html>
<html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light"><title>馬大別忙週報 ${range}</title></head>
<body style="margin:0;padding:0;background:${C.bg};color:${C.label};font-family:${FONT};-webkit-font-smoothing:antialiased">
${T(`background:${C.bg}`, `<tr><td align="center" style="padding:32px 12px 48px">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;width:100%;max-width:600px;font-family:${FONT};color:${C.label}">
${body}
</table></td></tr>`)}
</body></html>`;

  const text = [
    `馬大別忙週報 ${range}`,
    '',
    `新使用者 ${num(r.newUsers[0])}（上週 ${num(r.newUsers[1])}）`,
    `使用者 ${num(r.users[0])}、使用中的教會 ${num(r.churches[0])}、有人排服事表的教會 ${num(r.editing[0])}`,
    `新教會 ${num(r.fresh.count)} 間：邀了第二個人 ${r.fresh.invited}、排了服事表 ${r.fresh.planned}、10 人以上 ${r.fresh.tenPlus}`,
    r.ga ? `活躍使用者 ${num(r.ga.active[0])}（上週 ${num(r.ga.active[1])}）` : '',
    r.gsc ? `Google 搜尋：點擊 ${num(r.gsc.now.clicks)}、曝光 ${num(r.gsc.now.impressions)}` : '',
    r.quiet.length ? `上週有排、這週停了：${r.quiet.map((c) => c.name).join('、')}` : '',
  ].filter((l) => l !== '').join('\n');

  return { subject: `馬大別忙週報 ${range}：${num(r.newUsers[0])} 位新使用者`, html, text };
}

// ---------------------------------------------------------------- send

export interface Resend {
  apiKey: string;
  from: string;
  to: string;
}

export async function sendWeeklyReport(d: WeeklyReportDeps & { resend: Resend }) {
  const mail = weeklyMail(await collectWeeklyReport(d));
  const res = await d.fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${d.resend.apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: d.resend.from, to: [d.resend.to], subject: mail.subject, html: mail.html, text: mail.text }),
  });
  if (!res.ok) throw new Error(`Resend: ${res.status} ${await res.text()}`);
  return mail;
}
