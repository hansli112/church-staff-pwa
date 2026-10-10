import { readFileSync } from 'node:fs';

import type { Environment, SignedDataVerifier } from '@apple/app-store-server-library';
import { logger } from 'firebase-functions/v2';

import { round2, type Deps } from './common.js';
import { BUNDLE_ID, recordPayment, setRefund } from './funding.js';

/**
 * App Store Server Notifications (V2) for 雲端費用進度. App Store Connect
 * sends production notices to the prod project and sandbox ones (TestFlight
 * too) to dev; each project only accepts its own environment.
 */

/** From App Store Connect once the app exists there (#38); Apple requires it for production notices. */
export const APPLE_APP_ID: number | undefined = undefined;

/** Apple's cut with the Small Business Program. */
const APPLE_COMMISSION = 0.15;

/**
 * Sales tax inside App Store prices, by storefront (2026-10). Apple only
 * tells us the price, so what we get is an estimate. US and Canadian prices
 * leave the tax out. Storefronts not listed are taken as 10%, so a guess
 * errs low rather than high.
 */
const SALES_TAX: Record<string, number> = {
  TWN: 0.05,
  HKG: 0,
  MYS: 0.08,
  SGP: 0.09,
  JPN: 0.1,
  KOR: 0.1,
  AUS: 0.1,
  NZL: 0.15,
  GBR: 0.2,
  DEU: 0.19,
  FRA: 0.2,
  USA: 0,
  CAN: 0,
};
const UNLISTED_SALES_TAX = 0.1;

/** What Apple pays us out of [priceMilli] (milliunits of the buyer's currency). */
export function appleNet(priceMilli: number, storefront?: string): number {
  const tax = SALES_TAX[storefront ?? ''] ?? UNLISTED_SALES_TAX;
  return round2((priceMilli / 1000 / (1 + tax)) * (1 - APPLE_COMMISSION));
}

/** What we read from Apple's signed notices; faked in tests. */
export interface AppleVerifier {
  notification(signedPayload: string): Promise<{ notificationType?: string; signedTransactionInfo?: string }>;
  transaction(signed: string): Promise<{
    transactionId?: string;
    productId?: string;
    price?: number;
    currency?: string;
    storefront?: string;
    purchaseDate?: number;
    /** FAMILY_SHARED: a family member's access, not a payment. */
    inAppOwnershipType?: string;
  }>;
}

const INCOME = new Set(['ONE_TIME_CHARGE', 'SUBSCRIBED', 'DID_RENEW']);
/** How much of the payment ends up refunded, by notice. */
const REFUNDS: Record<string, number> = { REFUND: 1, REFUND_REVERSED: 0 };

/**
 * Handles one notice. The status code is the answer: anything but 200
 * makes Apple send it again later.
 */
export async function appStoreNotification(deps: Deps, apple: AppleVerifier, body: unknown): Promise<number> {
  const signed = (body as { signedPayload?: unknown } | null)?.signedPayload;
  if (typeof signed !== 'string') return 400;
  let tx: Awaited<ReturnType<AppleVerifier['transaction']>>;
  let type: string;
  try {
    const n = await apple.notification(signed);
    if (!n.notificationType || !n.signedTransactionInfo) return 200;
    type = n.notificationType;
    if (!INCOME.has(type) && !(type in REFUNDS)) return 200;
    tx = await apple.transaction(n.signedTransactionInfo);
  } catch (e) {
    logger.warn('App Store notification failed verification', { error: String(e) });
    return 400;
  }
  if (!tx.transactionId) return 200;
  const id = `apple_${tx.transactionId}`;
  if (type in REFUNDS) {
    await setRefund(deps, id, 'apple', REFUNDS[type]);
    return 200;
  }
  if (tx.inAppOwnershipType && tx.inAppOwnershipType !== 'PURCHASED') return 200;
  if (typeof tx.price !== 'number' || !tx.currency) {
    logger.error('App Store payment without a price', { id });
    return 200;
  }
  await recordPayment(deps, {
    id,
    store: 'apple',
    productId: tx.productId ?? '',
    amount: appleNet(tx.price, tx.storefront),
    currency: tx.currency,
    at: new Date(tx.purchaseDate ?? deps.now().getTime()),
  });
  return 200;
}

/**
 * Verifies Apple's JWS against Apple's root certificate. A notice from the
 * other environment fails, so sandbox money never reaches prod.
 */
export function appleVerifier(environment: Environment.PRODUCTION | Environment.SANDBOX): AppleVerifier {
  // Built on first use, so a missing APPLE_APP_ID in production fails the
  // check (and is logged) instead of the whole function.
  let v: SignedDataVerifier | undefined;
  const verifier = async () => {
    const { SignedDataVerifier } = await import('@apple/app-store-server-library');
    return (v ??= new SignedDataVerifier(
      [readFileSync(new URL('../certs/AppleRootCA-G3.cer', import.meta.url))],
      true,
      environment,
      BUNDLE_ID,
      APPLE_APP_ID,
    ));
  };
  return {
    notification: async (s) => {
      const n = await (await verifier()).verifyAndDecodeNotification(s);
      return { notificationType: n.notificationType, signedTransactionInfo: n.data?.signedTransactionInfo };
    },
    transaction: async (s) => (await verifier()).verifyAndDecodeTransaction(s),
  };
}
