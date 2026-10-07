import { createCipheriv, createDecipheriv, createHash, randomBytes, timingSafeEqual } from 'node:crypto';

import { FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

import { DAY_MS, PROD_PROJECT, REGION, dateKeyUtc8, round2, type Deps } from './common.js';
import { recordPayment } from './funding.js';
import { SUPPORT_AMOUNT } from './limits.js';

/**
 * 線上支持: one-off payments on the website's support page, through
 * NewebPay (藍新金流) MPG, for 雲端費用進度. No sign-in: the page asks
 * [newebpayStart] for a signed form and posts it to NewebPay; NewebPay
 * tells [newebpayNotify] when it is paid, and that is what counts.
 *
 * Built to 線上交易─幕前支付技術串接手冊 (MPG), NDNF-1.2.6 (2026-10-01),
 * from https://www.newebpay.com/website/Page/content/download_api :
 * §4.1.1 AES256 (AES-256-CBC, PKCS7, hex), §4.1.2 SHA256 (TradeSha),
 * §4.2.1 request, §4.2.2 the notice, §6 (only HTTP 200 ends the retries).
 *
 * - `newebpayOrders/{MerchantOrderNo}`: { amount, status, createdAt,
 *   expiresAt } while pending; { tradeNo, paymentType, paidAt } once paid.
 *   No payer data: NewebPay keeps the card, email and IP. Pending ones
 *   are dropped after [ORDER_DAYS] (fundingDaily).
 * - `platform/newebpayRate`: { hour, count }, orders started this hour.
 */

/** NDNF-1.2.6 §4.2: the MPG gateway, by environment. */
export const GATEWAYS = {
  test: 'https://ccore.newebpay.com/MPG/mpg_gateway',
  production: 'https://core.newebpay.com/MPG/mpg_gateway',
} as const;
export type Gateway = keyof typeof GATEWAYS;

/** 串接程式版本 for NDNF-1.2.6. */
export const MPG_VERSION = '2.3';

/** On the payment page and in NewebPay's back office (at most 50 characters). */
const ITEM_DESC = '馬大別忙 雲端費用 線上支持';

/** Seconds the payer has on NewebPay's page (900 is the most it takes). */
const TRADE_LIMIT = 900;

/**
 * NewebPay's fee: its published rate for cards, Apple Pay and Google Pay
 * is 2.8%. Check it against the contract once the store is approved.
 */
const NEWEBPAY_FEE = 0.028;

/**
 * Orders anyone can start in an hour, all together. The page needs no
 * sign-in, so this bounds the writes a script can cause; a real supporter
 * meeting it is told to try again later.
 */
export const ORDERS_PER_HOUR = 60;

/** A pending order is dropped this long after it was started. */
const ORDER_DAYS = 3;

/** The product ID a 線上支持 payment is recorded with. */
export const WEB_PRODUCT = 'web_once';

export interface NewebpayConfig {
  merchantId: string;
  /** 32 characters, from the store's 「API 串接金鑰」. */
  hashKey: string;
  /** 16 characters. */
  hashIv: string;
  gateway: Gateway;
  notifyUrl: string;
  returnUrl: string;
  /** NewebPay's 返回商店 button. */
  backUrl: string;
}

/**
 * The config from the deployed values, or null while NewebPay is not set
 * up (no merchant ID, placeholder keys): then nothing starts. prod only
 * takes the production gateway, so test payments never count there.
 */
export function newebpayConfig(v: {
  merchantId?: string;
  gateway?: string;
  hashKey: string;
  hashIv: string;
  project: string;
  appUrl: string;
}): NewebpayConfig | null {
  const merchantId = v.merchantId?.trim() ?? '';
  if (!/^[A-Za-z0-9]{1,15}$/.test(merchantId)) return null;
  if (v.hashKey.length !== 32 || v.hashIv.length !== 16) return null;
  if (v.gateway !== 'test' && v.gateway !== 'production') return null;
  if (v.project === PROD_PROJECT && v.gateway !== 'production') return null;
  const functions = `https://${REGION}-${v.project}.cloudfunctions.net`;
  return {
    merchantId,
    hashKey: v.hashKey,
    hashIv: v.hashIv,
    gateway: v.gateway,
    notifyUrl: `${functions}/newebpayNotify`,
    returnUrl: `${functions}/newebpayReturn`,
    backUrl: `${v.appUrl}/support`,
  };
}

// NDNF-1.2.6 §4.1: AES-256-CBC with the HashKey and HashIV as they are
// (UTF-8), PKCS7 padding, hex; TradeSha is SHA-256 of
// "HashKey=…&<TradeInfo>&HashIV=…", in capitals.

export function encryptTradeInfo(plain: string, key: string, iv: string): string {
  const cipher = createCipheriv('aes-256-cbc', Buffer.from(key, 'utf8'), Buffer.from(iv, 'utf8'));
  return cipher.update(plain, 'utf8', 'hex') + cipher.final('hex');
}

/** Throws when [hex] is not something [key] and [iv] encrypted. */
export function decryptTradeInfo(hex: string, key: string, iv: string): string {
  if (!/^(?:[0-9a-f]{32})+$/i.test(hex)) throw new Error('TradeInfo is not AES blocks in hex');
  const decipher = createDecipheriv('aes-256-cbc', Buffer.from(key, 'utf8'), Buffer.from(iv, 'utf8'));
  return decipher.update(hex, 'hex', 'utf8') + decipher.final('utf8');
}

export function tradeSha(tradeInfo: string, key: string, iv: string): string {
  return createHash('sha256').update(`HashKey=${key}&${tradeInfo}&HashIV=${iv}`).digest('hex').toUpperCase();
}

/** The MPG form fields for [params], sealed with the store's keys. */
export function mpgFields(config: NewebpayConfig, params: Record<string, string>) {
  const tradeInfo = encryptTradeInfo(new URLSearchParams(params).toString(), config.hashKey, config.hashIv);
  return {
    MerchantID: config.merchantId,
    TradeInfo: tradeInfo,
    TradeSha: tradeSha(tradeInfo, config.hashKey, config.hashIv),
    Version: MPG_VERSION,
  };
}

/** What an HTTP handler answers; index.ts sends it. */
export interface HttpAnswer {
  status: number;
  body: unknown;
}

/** A whole NT$ amount within SUPPORT_AMOUNT, or null. */
export function supportAmount(value: unknown): number | null {
  const n = typeof value === 'string' && /^\d{1,6}$/.test(value.trim()) ? Number(value) : value;
  if (typeof n !== 'number' || !Number.isInteger(n)) return null;
  return n >= SUPPORT_AMOUNT.min && n <= SUPPORT_AMOUNT.max ? n : null;
}

/** Unique within the store, [A-Za-z0-9_] and at most 30 characters (§4.2.1): 20 here. */
const newOrderNo = (now: Date) => dateKeyUtc8(now).replaceAll('-', '') + randomBytes(6).toString('hex');

/**
 * Starts a one-off payment of { amount } NT$: keeps a pending order and
 * answers with where to post and the fields to post there. Errors are
 * { error: 'amount' | 'busy' | 'unavailable' }.
 */
export async function newebpayStart(deps: Deps, config: NewebpayConfig | null, body: unknown): Promise<HttpAnswer> {
  if (!config) return { status: 503, body: { error: 'unavailable' } };
  const amount = supportAmount((body as { amount?: unknown } | null)?.amount);
  if (amount === null) return { status: 400, body: { error: 'amount' } };

  const { db } = deps;
  const now = deps.now();
  const hour = now.toISOString().slice(0, 13);
  const orderNo = newOrderNo(now);
  const started = await db.runTransaction(async (tx) => {
    const rateRef = db.doc('platform/newebpayRate');
    const rate = await tx.get(rateRef);
    const count = rate.get('hour') === hour ? ((rate.get('count') as number | undefined) ?? 0) : 0;
    if (count >= ORDERS_PER_HOUR) return false;
    tx.set(rateRef, { hour, count: count + 1 });
    tx.create(db.doc(`newebpayOrders/${orderNo}`), {
      amount,
      status: 'pending',
      createdAt: now,
      expiresAt: new Date(now.getTime() + ORDER_DAYS * DAY_MS),
    });
    return true;
  });
  if (!started) {
    logger.warn('NewebPay orders over the hourly limit', { limit: ORDERS_PER_HOUR });
    return { status: 429, body: { error: 'busy' } };
  }

  const fields = mpgFields(config, {
    MerchantID: config.merchantId,
    RespondType: 'JSON',
    TimeStamp: String(Math.floor(now.getTime() / 1000)),
    Version: MPG_VERSION,
    MerchantOrderNo: orderNo,
    Amt: String(amount),
    ItemDesc: ITEM_DESC,
    TradeLimit: String(TRADE_LIMIT),
    ReturnURL: config.returnUrl,
    NotifyURL: config.notifyUrl,
    ClientBackURL: config.backUrl,
    // NewebPay asks for the payer's email on its own page, for its receipt.
    EmailModify: '1',
    CREDIT: '1',
    APPLEPAY: '1',
    ANDROIDPAY: '1',
    // TODO(LINE Pay): LINEPAY: '1' once the store has LINE Pay (separate application).
  });
  return { status: 200, body: { gateway: GATEWAYS[config.gateway], fields } };
}

/**
 * The decrypted TradeInfo: JSON { Status, Message, Result } when asked for
 * JSON (we do), or flat form fields (RespondType=String, the spec's sample).
 */
export function parseTradeInfo(plain: string): { status: string; result: Record<string, string> } {
  if (plain.trimStart().startsWith('{')) {
    const json = JSON.parse(plain) as { Status?: unknown; Result?: unknown };
    let result = json.Result;
    if (typeof result === 'string') result = result ? JSON.parse(result) : {};
    const flat: Record<string, string> = {};
    for (const [k, v] of Object.entries((result ?? {}) as Record<string, unknown>)) {
      if (v !== null && typeof v !== 'object') flat[k] = String(v);
    }
    return { status: String(json.Status ?? ''), result: flat };
  }
  const fields = Object.fromEntries(new URLSearchParams(plain));
  return { status: fields.Status ?? '', result: fields };
}

/** PayTime is "YYYY-MM-DD HH:MM:SS" in Taipei. */
function payTime(value: string | undefined): Date | null {
  const m = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})$/.exec(value ?? '');
  if (!m) return null;
  const d = new Date(`${m[1]}T${m[2]}+08:00`);
  return Number.isNaN(d.getTime()) ? null : d;
}

const sameText = (a: string, b: string) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

/** What NewebPay pays us out of [amount] NT$. */
export const newebpayNet = (amount: number) => round2(amount * (1 - NEWEBPAY_FEE));

/**
 * Handles one NotifyURL POST (Status, MerchantID, Version, TradeInfo,
 * TradeSha). The status code is the answer: NewebPay only takes HTTP 200
 * and tries three more times otherwise (NDNF-1.2.6 常見問題, Notify A3).
 *
 * Counted once per MerchantOrderNo, only when it says SUCCESS and the
 * TradeSha checks out. Sealed with our keys, the notice is NewebPay's word:
 * a payment whose pending order is gone (dropped after [ORDER_DAYS]) still
 * counts, at the amount NewebPay says. One whose order holds a different
 * amount does not; that is a bug on our side to look into.
 */
export async function newebpayNotify(deps: Deps, config: NewebpayConfig | null, body: unknown): Promise<number> {
  if (!config) {
    logger.error('NewebPay notice while NewebPay is not configured');
    return 503;
  }
  const b = (body ?? {}) as Record<string, unknown>;
  const info = b.TradeInfo;
  const sha = b.TradeSha;
  if (typeof info !== 'string' || typeof sha !== 'string' || b.MerchantID !== config.merchantId) return 400;
  if (!sameText(sha.toUpperCase(), tradeSha(info, config.hashKey, config.hashIv))) {
    logger.warn('NewebPay notice failed its TradeSha check');
    return 400;
  }
  let parsed: ReturnType<typeof parseTradeInfo>;
  try {
    parsed = parseTradeInfo(decryptTradeInfo(info, config.hashKey, config.hashIv));
  } catch (e) {
    logger.warn('NewebPay notice did not decrypt', { error: String(e) });
    return 400;
  }
  const { status, result } = parsed;
  const orderNo = result.MerchantOrderNo ?? '';
  if (result.MerchantID !== config.merchantId || !/^[A-Za-z0-9_]{1,30}$/.test(orderNo)) return 400;
  if (status !== 'SUCCESS') {
    // A declined card and the like: nothing was paid.
    logger.info('NewebPay payment not completed', { orderNo, status });
    return 200;
  }

  const ref = deps.db.doc(`newebpayOrders/${orderNo}`);
  const order = await ref.get();
  const amount = Number(result.Amt);
  if (!Number.isInteger(amount) || amount <= 0) {
    logger.error('NewebPay payment without an amount; not counted', { orderNo, amt: result.Amt ?? null });
    return 200;
  }
  if (!order.exists) {
    logger.warn('NewebPay payment for an order we no longer have; counted at its own amount', {
      orderNo,
      tradeNo: result.TradeNo ?? null,
      amount,
    });
  } else if (amount !== order.get('amount')) {
    logger.error('NewebPay amount differs from the order; not counted', { orderNo, amount, ordered: order.get('amount') });
    return 200;
  }
  const at = payTime(result.PayTime) ?? deps.now();
  await recordPayment(deps, {
    id: `newebpay_${orderNo}`,
    store: 'newebpay',
    productId: WEB_PRODUCT,
    amount: newebpayNet(amount),
    currency: 'TWD',
    at,
  });
  if (!order.exists) return 200;
  await ref.update({
    status: 'paid',
    tradeNo: result.TradeNo ?? '',
    paymentType: result.PaymentType ?? '',
    paidAt: at,
    expiresAt: FieldValue.delete(),
  });
  return 200;
}

/**
 * Where the payer's browser goes back to (ReturnURL is a form POST from
 * NewebPay's page): the support page, saying whether it went through.
 * NewebPay's own word on that comes by NotifyURL; this only picks a message.
 */
export function returnLocation(appUrl: string, body: unknown): string {
  const status = (body as { Status?: unknown } | null)?.Status;
  if (typeof status !== 'string') return `${appUrl}/support`;
  return `${appUrl}/support?paid=${status === 'SUCCESS' ? 1 : 0}`;
}

/** Drops pending orders nobody paid. Runs with fundingDaily. */
export async function dropExpiredOrders(deps: Deps) {
  const { db } = deps;
  for (;;) {
    const expired = await db.collection('newebpayOrders').where('expiresAt', '<', deps.now()).limit(400).get();
    if (expired.empty) return;
    const batch = db.batch();
    for (const d of expired.docs) batch.delete(d.ref);
    await batch.commit();
    if (expired.size < 400) return;
  }
}
