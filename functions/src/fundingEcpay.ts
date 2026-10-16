import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

import { FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

import { DAY_MS, PROD_PROJECT, REGION, dateKeyUtc8, round2, type Deps } from './common.js';
import { recordPayment } from './funding.js';
import { languageOf, sitePath, words, type Language } from './languages.js';
import { SUPPORT_AMOUNT } from './limits.js';

/**
 * 線上支持: one-off payments on the website's support page, through
 * ECPay (綠界科技) 全方位金流 AIO, for 雲端費用進度. No sign-in: the page
 * asks [ecpayStart] for a signed form and posts it to ECPay; ECPay tells
 * [ecpayNotify] when it is paid, and that is what counts.
 *
 * Built to ECPay's developer site (developers.ecpay.com.tw): 產生訂單
 * (?p=2862), 檢查碼機制 (?p=2902), 付款結果通知 (?p=2878), 測試介接資訊
 * (?p=2856).
 *
 * - `ecpayOrders/{MerchantTradeNo}`: { amount, status, createdAt,
 *   expiresAt } while pending; { tradeNo, paymentType, paidAt } once paid.
 *   No payer data: ECPay keeps the card and email. Pending ones are
 *   dropped after [ORDER_DAYS] (fundingDaily).
 * - `platform/ecpayRate`: { hour, count }, orders started this hour.
 */

/** The AIO checkout, by environment. */
export const GATEWAYS = {
  test: 'https://payment-stage.ecpay.com.tw/Cashier/AioCheckOut/V5',
  production: 'https://payment.ecpay.com.tw/Cashier/AioCheckOut/V5',
} as const;
export type Gateway = keyof typeof GATEWAYS;

/**
 * ECPay's page in the support page's language (Language: ENG, KOR, JPN,
 * CHI); Traditional is its own, so left out.
 */
const ECPAY_LANGUAGE: Record<Language, string | null> = { 'zh-Hant': null, 'zh-Hans': 'CHI', en: 'ENG', ja: 'JPN', ko: 'KOR' };

/** ChoosePayment's other values (產生訂單), left off ECPay's page. */
const IGNORED_PAYMENTS = 'WebATM#ATM#CVS#BARCODE#TWQR#BNPL#WeiXin#DigitalPayment';

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

export interface EcpayConfig {
  merchantId: string;
  /** 16 characters, from 廠商後台 → 系統開發管理 → 系統介接設定. */
  hashKey: string;
  /** 16 characters. */
  hashIv: string;
  gateway: Gateway;
  notifyUrl: string;
  returnUrl: string;
  /** The website, for ECPay's 返回商店 button: its support page. */
  siteUrl: string;
}

/**
 * The config from the deployed values, or null while ECPay is not set up
 * (no merchant ID, placeholder keys): then nothing starts. prod only takes
 * the production gateway, so test payments never count there.
 */
export function ecpayConfig(v: {
  merchantId?: string;
  gateway?: string;
  hashKey: string;
  hashIv: string;
  project: string;
  appUrl: string;
}): EcpayConfig | null {
  const merchantId = v.merchantId?.trim() ?? '';
  if (!/^\d{1,10}$/.test(merchantId)) return null;
  if (v.hashKey.length !== 16 || v.hashIv.length !== 16) return null;
  if (v.gateway !== 'test' && v.gateway !== 'production') return null;
  if (v.project === PROD_PROJECT && v.gateway !== 'production') return null;
  const functions = `https://${REGION}-${v.project}.cloudfunctions.net`;
  return {
    merchantId,
    hashKey: v.hashKey,
    hashIv: v.hashIv,
    gateway: v.gateway,
    notifyUrl: `${functions}/ecpayNotify`,
    returnUrl: `${functions}/ecpayReturn`,
    siteUrl: v.appUrl,
  };
}

/**
 * URL encoding as ECPay's .NET does it (檢查碼機制's URL Encode table):
 * spaces as +, - _ . ! * ( ) left as they are, ' and ~ encoded.
 */
const dotNetEncode = (s: string) =>
  encodeURIComponent(s)
    .replaceAll('%20', '+')
    .replaceAll("'", '%27')
    .replaceAll('~', '%7E');

/**
 * 檢查碼機制: every field but CheckMacValue, sorted by name ignoring case,
 * as k=v&…, between HashKey=… and HashIV=…, URL-encoded, lowercased,
 * SHA-256, in capitals.
 */
export function checkMacValue(fields: Record<string, string>, key: string, iv: string): string {
  const pairs = Object.keys(fields)
    .filter((k) => k !== 'CheckMacValue')
    .sort((a, b) => {
      const x = a.toLowerCase();
      const y = b.toLowerCase();
      return x < y ? -1 : x > y ? 1 : 0;
    })
    .map((k) => `${k}=${fields[k]}`);
  const raw = `HashKey=${key}&${pairs.join('&')}&HashIV=${iv}`;
  return createHash('sha256').update(dotNetEncode(raw).toLowerCase()).digest('hex').toUpperCase();
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

/** Unique, letters and digits, at most 20 (MerchantTradeNo): 20 here. */
const newOrderNo = (now: Date) => dateKeyUtc8(now).replaceAll('-', '') + randomBytes(6).toString('hex');

/** "yyyy/MM/dd HH:mm:ss" in Taipei, as MerchantTradeDate wants it. */
function taipeiTime(d: Date): string {
  const t = new Date(d.getTime() + 8 * 3600_000).toISOString();
  return `${t.slice(0, 10).replaceAll('-', '/')} ${t.slice(11, 19)}`;
}

/**
 * Starts a one-off payment of { amount } NT$ from the support page in
 * { language } (its <html lang>): keeps a pending order and answers with
 * where to post and the fields to post there. Errors are
 * { error: 'amount' | 'busy' | 'unavailable' }.
 */
export async function ecpayStart(deps: Deps, config: EcpayConfig | null, body: unknown): Promise<HttpAnswer> {
  if (!config) return { status: 503, body: { error: 'unavailable' } };
  const amount = supportAmount((body as { amount?: unknown } | null)?.amount);
  const language = languageOf((body as { language?: unknown } | null)?.language);
  if (amount === null) return { status: 400, body: { error: 'amount' } };

  const { db } = deps;
  const now = deps.now();
  const hour = now.toISOString().slice(0, 13);
  const orderNo = newOrderNo(now);
  const started = await db.runTransaction(async (tx) => {
    const rateRef = db.doc('platform/ecpayRate');
    const rate = await tx.get(rateRef);
    const count = rate.get('hour') === hour ? ((rate.get('count') as number | undefined) ?? 0) : 0;
    if (count >= ORDERS_PER_HOUR) return false;
    tx.set(rateRef, { hour, count: count + 1 });
    tx.create(db.doc(`ecpayOrders/${orderNo}`), {
      amount,
      status: 'pending',
      createdAt: now,
      expiresAt: new Date(now.getTime() + ORDER_DAYS * DAY_MS),
    });
    return true;
  });
  if (!started) {
    logger.warn('ECPay orders over the hourly limit', { limit: ORDERS_PER_HOUR });
    return { status: 429, body: { error: 'busy' } };
  }

  const item = words(language).supportItem;
  const lang = ECPAY_LANGUAGE[language];
  const fields: Record<string, string> = {
    MerchantID: config.merchantId,
    MerchantTradeNo: orderNo,
    MerchantTradeDate: taipeiTime(now),
    PaymentType: 'aio',
    TotalAmount: String(amount),
    TradeDesc: item,
    ItemName: item,
    // ECPay's ReturnURL is its notice to us; the payer comes back by OrderResultURL.
    ReturnURL: config.notifyUrl,
    OrderResultURL: config.returnUrl + sitePath(language, ''),
    ClientBackURL: config.siteUrl + sitePath(language, '/support'),
    // Cards and Apple Pay, of what the store has: not ATM or 超商 codes,
    // paid later, nor the rest (design.md, 金流).
    ChoosePayment: 'ALL',
    IgnorePayment: IGNORED_PAYMENTS,
    EncryptType: '1',
    ...(lang ? { Language: lang } : {}),
  };
  fields.CheckMacValue = checkMacValue(fields, config.hashKey, config.hashIv);
  return { status: 200, body: { gateway: GATEWAYS[config.gateway], fields } };
}

/** PaymentDate is "yyyy/MM/dd HH:mm:ss" in Taipei. */
function paymentDate(value: string | undefined): Date | null {
  const m = /^(\d{4})\/(\d{2})\/(\d{2}) (\d{2}:\d{2}:\d{2})$/.exec(value ?? '');
  if (!m) return null;
  const d = new Date(`${m[1]}-${m[2]}-${m[3]}T${m[4]}+08:00`);
  return Number.isNaN(d.getTime()) ? null : d;
}

const sameText = (a: string, b: string) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

/**
 * What ECPay pays us out of [amount] NT$: less PaymentTypeChargeFee, its
 * fee on this payment. A notice without a fee that makes sense counts the
 * whole amount, and says so.
 */
export function ecpayNet(amount: number, fee: string | undefined, orderNo: string): number {
  const f = Number(fee);
  if (!fee || !Number.isFinite(f) || f < 0 || f >= amount) {
    logger.warn('ECPay notice without a usable fee; counted in full', { orderNo, fee: fee ?? null });
    return amount;
  }
  return round2(amount - f);
}

/**
 * Handles one 付款結果通知 to ReturnURL. Answers the HTTP status; index.ts
 * replies 1|OK with a 200, and ECPay tries again (up to four times that
 * day) on anything else.
 *
 * Counted once per MerchantTradeNo, only when the CheckMacValue checks out,
 * RtnCode is 1 and it is not a 模擬付款 from ECPay's back office. Signed
 * with our keys, the notice is ECPay's word: a payment whose pending order
 * is gone (dropped after [ORDER_DAYS]) still counts, at the amount ECPay
 * says. One whose order holds a different amount does not; that is a bug
 * on our side to look into.
 */
export async function ecpayNotify(deps: Deps, config: EcpayConfig | null, body: unknown): Promise<number> {
  if (!config) {
    logger.error('ECPay notice while ECPay is not configured');
    return 503;
  }
  const fields: Record<string, string> = {};
  for (const [k, v] of Object.entries((body ?? {}) as Record<string, unknown>)) {
    if (typeof v === 'string') fields[k] = v;
  }
  const mac = fields.CheckMacValue;
  if (!mac || fields.MerchantID !== config.merchantId) return 400;
  if (!sameText(mac.toUpperCase(), checkMacValue(fields, config.hashKey, config.hashIv))) {
    logger.warn('ECPay notice failed its CheckMacValue');
    return 400;
  }
  const orderNo = fields.MerchantTradeNo ?? '';
  if (!/^[A-Za-z0-9]{1,20}$/.test(orderNo)) return 400;
  if (fields.RtnCode !== '1') {
    // A declined card and the like: nothing was paid.
    logger.info('ECPay payment not completed', { orderNo, rtnCode: fields.RtnCode ?? null });
    return 200;
  }
  if (fields.SimulatePaid === '1') {
    logger.info('ECPay 模擬付款, not counted', { orderNo });
    return 200;
  }

  const ref = deps.db.doc(`ecpayOrders/${orderNo}`);
  const order = await ref.get();
  const amount = Number(fields.TradeAmt);
  if (!Number.isInteger(amount) || amount <= 0) {
    logger.error('ECPay payment without an amount; not counted', { orderNo, tradeAmt: fields.TradeAmt ?? null });
    return 200;
  }
  if (!order.exists) {
    logger.warn('ECPay payment for an order we no longer have; counted at its own amount', {
      orderNo,
      tradeNo: fields.TradeNo ?? null,
      amount,
    });
  } else if (amount !== order.get('amount')) {
    logger.error('ECPay amount differs from the order; not counted', { orderNo, amount, ordered: order.get('amount') });
    return 200;
  }
  const at = paymentDate(fields.PaymentDate) ?? deps.now();
  await recordPayment(deps, {
    id: `ecpay_${orderNo}`,
    store: 'ecpay',
    productId: WEB_PRODUCT,
    amount: ecpayNet(amount, fields.PaymentTypeChargeFee, orderNo),
    currency: 'TWD',
    at,
  });
  if (!order.exists) return 200;
  await ref.update({
    status: 'paid',
    tradeNo: fields.TradeNo ?? '',
    paymentType: fields.PaymentType ?? '',
    paidAt: at,
    expiresAt: FieldValue.delete(),
  });
  return 200;
}

/**
 * Where the payer's browser goes back to (OrderResultURL is a form POST
 * from ECPay's page): the support page, saying whether it went through.
 * ECPay's own word on that comes by ReturnURL; this only picks a message.
 * [path] is the OrderResultURL's past the function, /en for the English page.
 */
export function returnLocation(appUrl: string, body: unknown, path = ''): string {
  const page = appUrl + sitePath(languageOf(path.replace(/^\//, '')), '/support');
  const code = (body as { RtnCode?: unknown } | null)?.RtnCode;
  if (typeof code !== 'string') return page;
  return `${page}?paid=${code === '1' ? 1 : 0}`;
}

/** Drops pending orders nobody paid. Runs with fundingDaily. */
export async function dropExpiredOrders(deps: Deps) {
  const { db } = deps;
  for (;;) {
    const expired = await db.collection('ecpayOrders').where('expiresAt', '<', deps.now()).limit(400).get();
    if (expired.empty) return;
    const batch = db.batch();
    for (const d of expired.docs) batch.delete(d.ref);
    await batch.commit();
    if (expired.size < 400) return;
  }
}
