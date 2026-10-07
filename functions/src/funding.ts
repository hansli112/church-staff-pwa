import { FieldValue, type DocumentSnapshot } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

import { dateKeyUtc8, fail, requireOperator, serverTime, text, type Caller, type Deps } from './common.js';
import { TEXT_LIMITS } from './limits.js';

/**
 * 雲端費用進度: what supporters gave this month against what the platform
 * costs. Payments come in on their own (fundingApple.ts, fundingPlay.ts);
 * the platform operator only enters the costs. Everyone signed in reads
 * `platform/funding`.
 *
 * A payment keeps its amount, product and time, not the account or name
 * of whoever paid (its ID is the store's transaction or order ID, which
 * the store's own console can trace).
 *
 * - `platform/fundingCosts`: { items: CostItem[] }, the operator's list.
 * - `fundingMonths/{YYYY-MM}`: { received, target } in NT$. A month keeps
 *   the target it had last; changing the costs only moves this month's.
 *   A month without a doc (before any costs, or with no exchange rate)
 *   counts as target 0, so whatever came in carries on.
 * - `fundingPayments/{store_id}`: one per payment, so a notice sent twice
 *   counts once and a refund knows what to take off. A refund that comes
 *   before its payment leaves a placeholder, so the payment is not counted
 *   when it arrives later.
 * - `platform/fxRates`: today's rates, kept for days the rate service is down.
 */

export const BUNDLE_ID = 'app.marthasit';

/** Exchange Rate API's open endpoint; the support page credits it. */
export const RATES_URL = 'https://open.er-api.com/v6/latest/TWD';

/** Rates older than this are still used, but logged as an error. */
const STALE_RATE_DAYS = 7;

export const COST_CURRENCIES = ['TWD', 'USD'] as const;
export type CostCurrency = (typeof COST_CURRENCIES)[number];

export interface CostItem {
  name: string;
  amount: number;
  currency: CostCurrency;
  per: 'month' | 'year';
}

/** How much of each currency one NT$ buys. */
export type Rates = Record<string, number>;

export interface MonthTotal {
  month: string;
  received: number;
  target: number;
}

export const monthOf = (d: Date) => dateKeyUtc8(d).slice(0, 7);

const monthTotal = (d: DocumentSnapshot): MonthTotal => ({
  month: d.id,
  received: (d.get('received') as number | undefined) ?? 0,
  target: (d.get('target') as number | undefined) ?? 0,
});

export function toTwd(amount: number, currency: string, rates: Rates): number | null {
  if (currency === 'TWD') return amount;
  const rate = rates[currency];
  return rate ? amount / rate : null;
}

/** NT$ a month: monthly items in full, yearly ones a twelfth. Null when a rate is missing. */
export function monthlyTarget(items: CostItem[], rates: Rates): number | null {
  let total = 0;
  for (const item of items) {
    const twd = toTwd(item.amount, item.currency, rates);
    if (twd === null) return null;
    total += item.per === 'year' ? twd / 12 : twd;
  }
  return Math.round(total);
}

/**
 * This month against its target. What a month gets over its target
 * carries on; a shortfall does not (the platform operator covers it).
 * [monthsLeft] is how many whole months beyond this one the money covers.
 */
export function summarize(months: MonthTotal[], current: string) {
  let carried = 0;
  for (const m of [...months].sort((a, b) => a.month.localeCompare(b.month))) {
    if (m.month >= current) continue;
    carried = Math.max(0, carried + m.received - m.target);
  }
  const now = months.find((m) => m.month === current);
  const target = now?.target ?? 0;
  const received = now?.received ?? 0;
  const over = carried + received - target;
  const monthsLeft = target > 0 && over > 0 ? Math.floor(over / target) : 0;
  return { target, received, carried, monthsLeft };
}

/** Today's rates: fetched once a day, the last ones when that fails. */
async function currentRates(deps: Deps): Promise<Rates> {
  const ref = deps.db.doc('platform/fxRates');
  const saved = await ref.get();
  const today = dateKeyUtc8(deps.now());
  if (saved.get('fetchedOn') === today) return saved.get('rates') as Rates;
  try {
    const res = await deps.fetch(RATES_URL, { signal: AbortSignal.timeout(10_000) });
    const body = (await res.json()) as { result?: string; rates?: Rates };
    if (!res.ok || body.result !== 'success' || !body.rates) throw new Error(`rates: ${res.status}`);
    await ref.set({ rates: body.rates, fetchedOn: today });
    return body.rates;
  } catch (e) {
    const fetchedOn = saved.get('fetchedOn') as string | undefined;
    const days = fetchedOn ? (Date.parse(today) - Date.parse(fetchedOn)) / 86_400_000 : Infinity;
    const log = days > STALE_RATE_DAYS ? logger.error : logger.warn;
    log('Exchange rates unavailable; using the last ones', { error: String(e), fetchedOn: fetchedOn ?? null });
    return (saved.get('rates') as Rates | undefined) ?? {};
  }
}

/**
 * Sets this month's target from the costs and republishes the summary
 * everyone reads. Runs after every change and once a day, so a month with
 * no payments still gets its target.
 */
export async function publishFunding(deps: Deps, rates?: Rates) {
  const { db } = deps;
  const items = ((await db.doc('platform/fundingCosts').get()).get('items') as CostItem[] | undefined) ?? [];
  const target = monthlyTarget(items, rates ?? (await currentRates(deps)));
  const month = monthOf(deps.now());
  await db.runTransaction(async (tx) => {
    const months = (await tx.get(db.collection('fundingMonths'))).docs.map(monthTotal);
    if (target !== null) {
      tx.set(db.doc(`fundingMonths/${month}`), { target }, { merge: true });
      const now = months.find((m) => m.month === month);
      if (now) now.target = target;
      else months.push({ month, received: 0, target });
    }
    tx.set(db.doc('platform/funding'), { month, ...summarize(months, month), updatedAt: serverTime() });
  });
}

export interface Payment {
  /** `apple_<transactionId>` or `google_<orderId>`. */
  id: string;
  store: 'apple' | 'google';
  productId: string;
  /** What we get, in [currency]. */
  amount: number;
  currency: string;
  at: Date;
}

/**
 * Adds a payment to its month, once, less any refund that came first.
 * Throws (so the store sends it again) when it cannot be changed into NT$.
 */
export async function recordPayment(deps: Deps, p: Payment) {
  const rates = await currentRates(deps);
  const twd = toTwd(p.amount, p.currency, rates);
  if (twd === null) throw new Error(`No exchange rate for ${p.currency}`);
  const amountTwd = Math.round(twd);
  const month = monthOf(p.at);
  const { db } = deps;
  const added = await db.runTransaction(async (tx) => {
    const ref = db.doc(`fundingPayments/${p.id}`);
    const existing = await tx.get(ref);
    if (existing.get('amountTwd') !== undefined) return false;
    const refundedTwd = Math.round(amountTwd * ((existing.get('refundShare') as number | undefined) ?? 0));
    tx.set(ref, {
      store: p.store,
      productId: p.productId,
      amount: p.amount,
      currency: p.currency,
      amountTwd,
      refundedTwd,
      month,
      at: p.at,
    });
    tx.set(
      db.doc(`fundingMonths/${month}`),
      { received: FieldValue.increment(amountTwd - refundedTwd) },
      { merge: true },
    );
    return true;
  });
  if (added) await publishFunding(deps, rates);
}

/**
 * Sets how much of a payment was refunded: [share] 1 for all of it, 0 when
 * a refund was reversed. Only the difference moves the month it was paid
 * in, so a notice sent twice changes nothing.
 */
export async function setRefund(deps: Deps, id: string, store: Payment['store'], share: number) {
  const { db } = deps;
  const changed = await db.runTransaction(async (tx) => {
    const ref = db.doc(`fundingPayments/${id}`);
    const payment = await tx.get(ref);
    const amountTwd = payment.get('amountTwd') as number | undefined;
    if (amountTwd === undefined) {
      // The payment has not come in yet: remember the refund for it.
      tx.set(ref, { store, refundShare: share });
      return false;
    }
    const refundedTwd = Math.round(amountTwd * share);
    const delta = refundedTwd - ((payment.get('refundedTwd') as number | undefined) ?? 0);
    if (delta === 0) return false;
    tx.update(ref, { refundedTwd });
    tx.set(db.doc(`fundingMonths/${payment.get('month')}`), { received: FieldValue.increment(-delta) }, { merge: true });
    return true;
  });
  if (changed) await publishFunding(deps);
}

// Platform operator

function costItem(value: unknown): CostItem {
  const v = value as Partial<CostItem> | null;
  const name = text(v?.name, TEXT_LIMITS.costName);
  const amount = v?.amount;
  if (typeof amount !== 'number' || !Number.isFinite(amount) || amount <= 0 || amount > 10_000_000) {
    fail('invalid-argument', 'unknown');
  }
  const currency = COST_CURRENCIES.find((c) => c === v?.currency);
  if (!currency) fail('invalid-argument', 'unknown');
  if (v?.per !== 'month' && v?.per !== 'year') fail('invalid-argument', 'unknown');
  return { name, amount, currency, per: v.per };
}

/** The cost list and the last 12 months, newest first. */
export async function adminFunding(deps: Deps, caller: Caller | null, _data: unknown) {
  requireOperator(caller);
  const { db } = deps;
  const [costs, months, summary] = await Promise.all([
    db.doc('platform/fundingCosts').get(),
    // A few docs a year: sorting here beats a descending index on the ID.
    db.collection('fundingMonths').get(),
    db.doc('platform/funding').get(),
  ]);
  return {
    costs: (costs.get('items') as CostItem[] | undefined) ?? [],
    months: months.docs
      .map(monthTotal)
      .sort((a, b) => b.month.localeCompare(a.month))
      .slice(0, 12),
    funding: summary.exists ? { ...summary.data(), updatedAt: summary.get('updatedAt')?.toMillis() ?? null } : null,
  };
}

export async function adminSetFundingCosts(deps: Deps, caller: Caller | null, data: unknown) {
  requireOperator(caller);
  const raw = (data as { items?: unknown })?.items;
  if (!Array.isArray(raw) || raw.length > 30) fail('invalid-argument', 'unknown');
  const items = raw.map(costItem);
  await deps.db.doc('platform/fundingCosts').set({ items, updatedAt: serverTime() });
  await publishFunding(deps);
  return {};
}
