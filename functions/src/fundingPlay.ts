import { logger } from 'firebase-functions/v2';

import { DAY_MS, type Deps } from './common.js';
import { BUNDLE_ID, recordPayment, setRefund } from './funding.js';

/**
 * Google Play Real-time Developer Notifications for 雲端費用進度. Play
 * Console sends one app's notices to one topic, in prod; test purchases
 * are left out here. Amounts come from the Orders API: what Google pays
 * us, in the buyer's currency.
 */

const PLAY_API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${BUNDLE_ID}`;
const TOKEN_URL =
  'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token?scopes=https://www.googleapis.com/auth/androidpublisher';

/** An order still unsettled after this long is given up on, and logged. */
const GIVE_UP_MS = 3 * DAY_MS;

interface DeveloperNotification {
  packageName?: string;
  oneTimeProductNotification?: { notificationType?: number; purchaseToken?: string; sku?: string };
  subscriptionNotification?: { notificationType?: number; purchaseToken?: string };
  voidedPurchaseNotification?: { orderId?: string; refundType?: number };
}

interface Money {
  currencyCode?: string;
  units?: string;
  nanos?: number;
}

/** SUBSCRIPTION_RECOVERED, _RENEWED, _PURCHASED: each one is a charge. */
const CHARGES = new Set([1, 2, 4]);
const PARTIAL_REFUND = 2;

const amountOf = (m: Money | undefined) => Number(m?.units ?? 0) + (m?.nanos ?? 0) / 1e9;

async function playGet(deps: Deps, token: string, path: string) {
  const res = await deps.fetch(`${PLAY_API}/${path}`, { headers: { authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`Play API ${path}: ${res.status}`);
  return (await res.json()) as Record<string, unknown>;
}

async function playToken(deps: Deps) {
  const res = await deps.fetch(TOKEN_URL, { headers: { 'Metadata-Flavor': 'Google' } });
  if (!res.ok) throw new Error(`metadata token: ${res.status}`);
  return ((await res.json()) as { access_token: string }).access_token;
}

const getOrder = (deps: Deps, token: string, orderId: string) =>
  playGet(deps, token, `orders/${encodeURIComponent(orderId)}`);

/** Counts a Play order. [publishedAt] is when Google first sent the notice. */
async function recordOrder(deps: Deps, token: string, orderId: string, publishedAt: Date) {
  const order = await getOrder(deps, token, orderId);
  const revenue = order.developerRevenueInBuyerCurrency as Money | undefined;
  if (!revenue?.currencyCode) {
    if (deps.now().getTime() - publishedAt.getTime() > GIVE_UP_MS) {
      logger.error('Play order never settled; not counted', { orderId });
      return;
    }
    // Not settled yet: throwing makes Pub/Sub deliver the notice again.
    throw new Error(`Play order ${orderId} has no revenue yet`);
  }
  await recordPayment(deps, {
    id: `google_${orderId}`,
    store: 'google',
    productId: ((order.lineItems as { productId?: string }[] | undefined) ?? [])[0]?.productId ?? '',
    amount: amountOf(revenue),
    currency: revenue.currencyCode,
    at: typeof order.createTime === 'string' ? new Date(order.createTime) : deps.now(),
  });
}

/** How much of an order was refunded so far, from its history. */
async function refundedShare(deps: Deps, orderId: string) {
  const order = await getOrder(deps, await playToken(deps), orderId);
  const history = (order.orderHistory ?? {}) as {
    refundEvent?: unknown;
    partialRefundEvents?: { state?: string; refundDetails?: { total?: Money } }[];
  };
  if (history.refundEvent) return 1;
  const total = amountOf(order.total as Money | undefined);
  if (total <= 0) throw new Error(`Play order ${orderId} has no total`);
  const refunded = (history.partialRefundEvents ?? [])
    .filter((e) => e.state === 'PROCESSED')
    .reduce((sum, e) => sum + amountOf(e.refundDetails?.total), 0);
  return Math.min(1, refunded / total);
}

/** Handles one notice: the Pub/Sub message's JSON, and when it was published. */
export async function playNotification(deps: Deps, data: unknown, publishedAt: Date) {
  const n = data as DeveloperNotification | null;
  if (n?.packageName !== BUNDLE_ID) return;
  const voided = n.voidedPurchaseNotification;
  if (voided?.orderId) {
    const share = voided.refundType === PARTIAL_REFUND ? await refundedShare(deps, voided.orderId) : 1;
    return setRefund(deps, `google_${voided.orderId}`, 'google', share);
  }

  const product = n.oneTimeProductNotification;
  if (product?.notificationType === 1 && product.purchaseToken && product.sku) {
    const token = await playToken(deps);
    const purchase = await playGet(
      deps,
      token,
      `purchases/products/${encodeURIComponent(product.sku)}/tokens/${encodeURIComponent(product.purchaseToken)}`,
    );
    // purchaseType is only there for test, promo and rewarded purchases: no money.
    if (purchase.purchaseType !== undefined || purchase.purchaseState !== 0) return;
    return recordOrder(deps, token, purchase.orderId as string, publishedAt);
  }

  const sub = n.subscriptionNotification;
  if (sub?.purchaseToken && CHARGES.has(sub.notificationType ?? 0)) {
    const token = await playToken(deps);
    const purchase = await playGet(deps, token, `purchases/subscriptionsv2/tokens/${encodeURIComponent(sub.purchaseToken)}`);
    if (purchase.testPurchase !== undefined) return;
    const items = (purchase.lineItems as { latestSuccessfulOrderId?: string }[] | undefined) ?? [];
    const orderId = items[0]?.latestSuccessfulOrderId ?? (purchase.latestOrderId as string | undefined);
    if (orderId) return recordOrder(deps, token, orderId, publishedAt);
  }
}
