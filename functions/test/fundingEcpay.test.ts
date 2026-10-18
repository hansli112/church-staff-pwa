import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { beforeEach, describe, test } from 'node:test';

import {
  GATEWAYS,
  adminRefundOnlineSupport,
  ORDERS_PER_HOUR,
  checkMacValue,
  dropExpiredOrders,
  ecpayConfig,
  ecpayNotify,
  ecpayStart,
  returnLocation,
  type EcpayConfig,
} from '../src/fundingEcpay.js';
import { recordPayment } from '../src/funding.js';
import { funding, op, withRates } from './fundingFixtures.js';
import { caller, clearFirestore, db, deps, rejectsWith, setNow } from './support.js';

// The worked example on ECPay's 檢查碼機制 page (developers.ecpay.com.tw/?p=2902),
// with the public test store's keys (?p=2856).
const SPEC = {
  key: 'pwFHCqoQZGmho4w6',
  iv: 'EkRm7iFT261dpevs',
  params: {
    TradeDesc: '促銷方案',
    PaymentType: 'aio',
    MerchantTradeDate: '2023/03/12 15:30:23',
    MerchantTradeNo: 'ecpay20230312153023',
    MerchantID: '3002607',
    ReturnURL: 'https://www.ecpay.com.tw/receive.php',
    ItemName: 'Apple iphone 15',
    TotalAmount: '30000',
    ChoosePayment: 'ALL',
    EncryptType: '1',
  },
  mac: '6C51C9E6888DE861FD62FB1DD17029FC742634498FD813DC43D4243B5685B840',
};

/** Fake keys of the right lengths; never a real store's. */
const config: EcpayConfig = ecpayConfig({
  merchantId: '3000001',
  gateway: 'test',
  hashKey: 'abcdefghijklmnop',
  hashIv: 'ABCDEFGHIJKLMNOP',
  project: 'demo-martha',
  appUrl: 'https://demo-martha.web.app',
})!;

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-06T09:00:00+08:00'));
});

describe('CheckMacValue (檢查碼機制)', () => {
  test("ECPay's example comes out as ECPay's check value", () => {
    assert.equal(checkMacValue(SPEC.params, SPEC.key, SPEC.iv), SPEC.mac);
  });

  test('the order of the fields does not matter, CheckMacValue itself is left out, and every value counts', () => {
    const reversed = Object.fromEntries(Object.entries(SPEC.params).reverse());
    assert.equal(checkMacValue({ ...reversed, CheckMacValue: 'x' }, SPEC.key, SPEC.iv), SPEC.mac);
    assert.notEqual(checkMacValue({ ...SPEC.params, TotalAmount: '30001' }, SPEC.key, SPEC.iv), SPEC.mac);
    assert.notEqual(checkMacValue(SPEC.params, 'z'.repeat(16), SPEC.iv), SPEC.mac);
  });

  test("encoded the way ECPay's .NET does: spaces as +, and - _ . ! * ( ) as they are", () => {
    // Encoded by hand from 檢查碼機制's steps and its URL Encode table, then lowercased.
    const encoded = "hashkey%3dk%26a%3da+b-_.!*()%27%7e%26hashiv%3dv";
    const expected = createHash('sha256').update(encoded).digest('hex').toUpperCase();
    assert.equal(checkMacValue({ A: "a b-_.!*()'~" }, 'k', 'v'), expected);
  });
});

describe('ECPay config', () => {
  const base = { merchantId: '3123456', gateway: 'production', hashKey: 'k'.repeat(16), hashIv: 'v'.repeat(16), project: 'marthasit', appUrl: 'https://marthasit.web.app' };

  test("notices and the way back are this project's functions; 返回商店 is the website", () => {
    assert.deepEqual(ecpayConfig(base), {
      merchantId: '3123456',
      hashKey: base.hashKey,
      hashIv: base.hashIv,
      gateway: 'production',
      notifyUrl: 'https://asia-east1-marthasit.cloudfunctions.net/ecpayNotify',
      returnUrl: 'https://asia-east1-marthasit.cloudfunctions.net/ecpayReturn',
      siteUrl: 'https://marthasit.web.app',
    });
  });

  test('off until it is all set: no merchant, placeholder keys, no environment', () => {
    assert.equal(ecpayConfig({ ...base, merchantId: undefined }), null);
    assert.equal(ecpayConfig({ ...base, hashKey: 'placeholder' }), null);
    assert.equal(ecpayConfig({ ...base, hashIv: 'placeholder' }), null);
    assert.equal(ecpayConfig({ ...base, gateway: undefined }), null);
  });

  test('prod takes only the production gateway; dev may test', () => {
    assert.equal(ecpayConfig({ ...base, gateway: 'test' }), null);
    assert.equal(ecpayConfig({ ...base, gateway: 'test', project: 'marthasit-dev' })?.gateway, 'test');
  });
});

/** Starts an order and reads back what the page would post. */
async function start(amount: unknown, language?: string) {
  const r = await ecpayStart(deps, config, { amount, language });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body as { gateway: string; fields: Record<string, string> };
}

describe('starting a 線上支持 payment', () => {
  test("a signed AIO form for ECPay's test gateway, and a pending order without personal data", async () => {
    const { gateway, fields } = await start(300);
    assert.equal(gateway, GATEWAYS.test);
    assert.equal(fields.CheckMacValue, checkMacValue(fields, config.hashKey, config.hashIv));
    assert.match(fields.MerchantTradeNo, /^[A-Za-z0-9]{20}$/);
    assert.deepEqual({ ...fields, MerchantTradeNo: '', CheckMacValue: '' }, {
      MerchantID: config.merchantId,
      MerchantTradeNo: '',
      MerchantTradeDate: '2026/10/06 09:00:00',
      PaymentType: 'aio',
      TotalAmount: '300',
      TradeDesc: '支持馬大別忙的雲端費用',
      ItemName: '支持馬大別忙的雲端費用',
      ReturnURL: config.notifyUrl,
      OrderResultURL: config.returnUrl,
      ClientBackURL: `${config.siteUrl}/support`,
      ChoosePayment: 'ALL',
      IgnorePayment: 'WebATM#ATM#CVS#BARCODE#TWQR#BNPL#WeiXin#DigitalPayment',
      EncryptType: '1',
      CheckMacValue: '',
    });
    const order = (await db.doc(`ecpayOrders/${fields.MerchantTradeNo}`).get()).data();
    assert.deepEqual(Object.keys(order ?? {}).sort(), ['amount', 'createdAt', 'expiresAt', 'status']);
    assert.equal(order?.amount, 300);
    assert.equal(order?.status, 'pending');
  });

  test("in the support page's language: ECPay's page, what it is for, and the way back", async () => {
    const english = await start(300, 'en');
    assert.deepEqual(
      [english.fields.Language, english.fields.ItemName, english.fields.OrderResultURL, english.fields.ClientBackURL],
      ['ENG', 'Support for the server costs of Martha, sit', `${config.returnUrl}/en`, `${config.siteUrl}/en/support`],
    );
    const simplified = await start(300, 'zh-Hans');
    assert.deepEqual(
      [simplified.fields.Language, simplified.fields.ItemName, simplified.fields.OrderResultURL],
      ['CHI', '支持马大别忙的云端费用', `${config.returnUrl}/zh-Hans`],
    );
    assert.deepEqual([(await start(300, 'ja')).fields.Language, (await start(300, 'ko')).fields.Language], ['JPN', 'KOR']);
    assert.equal((await start(300, 'xx')).fields.Language, 'ENG', 'a page in a language not known here');
    assert.equal((await start(300)).fields.Language, undefined, "Traditional is ECPay's own");
  });

  test('every order number is new', async () => {
    const a = await start(100);
    const b = await start(100);
    assert.notEqual(a.fields.MerchantTradeNo, b.fields.MerchantTradeNo);
  });

  test('a whole number of NT dollars from 30 to 1,000, or nothing starts', async () => {
    for (const bad of [29, 1_001, 100.5, -100, '1e3', '', null, undefined]) {
      const r = await ecpayStart(deps, config, { amount: bad });
      assert.deepEqual(r, { status: 400, body: { error: 'amount' } }, `amount ${String(bad)}`);
    }
    assert.equal((await ecpayStart(deps, config, null)).status, 400);
    assert.equal((await ecpayStart(deps, config, { amount: '30' })).status, 200);
    assert.equal((await ecpayStart(deps, config, { amount: ' 300 ' })).status, 200);
    assert.equal((await ecpayStart(deps, config, { amount: 1_000 })).status, 200);
  });

  test('not set up yet: nothing starts', async () => {
    assert.deepEqual(await ecpayStart(deps, null, { amount: 300 }), { status: 503, body: { error: 'unavailable' } });
    assert.equal((await db.collection('ecpayOrders').get()).size, 0);
  });

  test('no more than the hourly limit, all callers together; the next hour starts over', async () => {
    await db.doc('platform/ecpayRate').set({ hour: '2026-10-06T01', count: ORDERS_PER_HOUR - 1 });
    assert.equal((await ecpayStart(deps, config, { amount: 100 })).status, 200);
    assert.deepEqual(await ecpayStart(deps, config, { amount: 100 }), { status: 429, body: { error: 'busy' } });
    assert.equal((await db.collection('ecpayOrders').get()).size, 1);
    setNow(new Date('2026-10-06T10:00:00+08:00'));
    assert.equal((await ecpayStart(deps, config, { amount: 100 })).status, 200);
  });
});

/** ECPay's 付款結果通知 for [orderNo], signed with [keys] (?p=2878). */
function notice(
  orderNo: string,
  {
    rtnCode = '1',
    amt = 300,
    fee = '8',
    simulated = '0',
    keys = config,
  }: { rtnCode?: string; amt?: number; fee?: string | null; simulated?: string; keys?: Pick<EcpayConfig, 'hashKey' | 'hashIv' | 'merchantId'> } = {},
) {
  const fields: Record<string, string> = {
    MerchantID: keys.merchantId,
    MerchantTradeNo: orderNo,
    StoreID: '',
    RtnCode: rtnCode,
    RtnMsg: rtnCode === '1' ? '交易成功' : '交易失敗',
    TradeNo: '2610060800001234',
    TradeAmt: String(amt),
    PaymentDate: '2026/10/06 08:00:00',
    PaymentType: 'Credit_CreditCard',
    TradeDate: '2026/10/06 07:59:00',
    SimulatePaid: simulated,
    CustomField1: '',
    CustomField2: '',
    CustomField3: '',
    CustomField4: '',
  };
  if (fee !== null) fields.PaymentTypeChargeFee = fee;
  return { ...fields, CheckMacValue: checkMacValue(fields, keys.hashKey, keys.hashIv) };
}

const received = async () => (await funding())?.received;

describe('ECPay tells us about a payment', () => {
  test("a paid order counts toward this month, less ECPay's fee, once even when sent again", async () => {
    const d = withRates();
    const { fields } = await start(300);
    const n = notice(fields.MerchantTradeNo);
    assert.equal(await ecpayNotify(d, config, n), 200);
    assert.equal(await ecpayNotify(d, config, n), 200);
    assert.equal(await received(), 292); // NT$300 less the NT$8 fee the notice says
    assert.equal((await db.doc('fundingMonths/2026-10').get()).get('received'), 292);

    const payment = (await db.doc(`fundingPayments/ecpay_${fields.MerchantTradeNo}`).get()).data();
    assert.deepEqual({ ...payment, at: payment?.at.toDate() }, {
      store: 'ecpay',
      productId: 'web_once',
      amount: 292,
      currency: 'TWD',
      amountTwd: 292,
      refundedTwd: 0,
      month: '2026-10',
      at: new Date('2026-10-06T08:00:00+08:00'),
    });
    const order = (await db.doc(`ecpayOrders/${fields.MerchantTradeNo}`).get()).data();
    assert.equal(order?.status, 'paid');
    assert.equal(order?.tradeNo, '2610060800001234');
    assert.equal(order?.paymentType, 'Credit_CreditCard');
    assert.equal(order?.expiresAt, undefined);
  });

  test('a notice without its fee counts the whole amount', async () => {
    const { fields } = await start(300);
    assert.equal(await ecpayNotify(withRates(), config, notice(fields.MerchantTradeNo, { fee: null })), 200);
    assert.equal(await received(), 300);
  });

  test('a CheckMacValue that does not check out is refused, and nothing counts', async () => {
    const { fields } = await start(300);
    const forged = { ...notice(fields.MerchantTradeNo), CheckMacValue: '0'.repeat(64) };
    assert.equal(await ecpayNotify(withRates(), config, forged), 400);
    const raised = { ...notice(fields.MerchantTradeNo), TradeAmt: '3000' };
    assert.equal(await ecpayNotify(withRates(), config, raised), 400);
    const otherKeys = notice(fields.MerchantTradeNo, { keys: { ...config, hashKey: 'z'.repeat(16) } });
    assert.equal(await ecpayNotify(withRates(), config, otherKeys), 400);
    assert.equal(await ecpayNotify(withRates(), config, { RtnCode: '1' }), 400);
    assert.equal(await ecpayNotify(withRates(), config, null), 400);
    assert.equal(await funding(), undefined);
  });

  test("a lowercase check value is ECPay's too", async () => {
    const { fields } = await start(300);
    const n = notice(fields.MerchantTradeNo);
    assert.equal(await ecpayNotify(withRates(), config, { ...n, CheckMacValue: n.CheckMacValue.toLowerCase() }), 200);
    assert.equal(await received(), 292);
  });

  test("another store's notice is refused", async () => {
    const { fields } = await start(300);
    const other = notice(fields.MerchantTradeNo, { keys: { ...config, merchantId: '3999999' } });
    assert.equal(await ecpayNotify(withRates(), config, other), 400);
    assert.equal(await funding(), undefined);
  });

  test("an amount other than the order's is not counted", async () => {
    const { fields } = await start(300);
    assert.equal(await ecpayNotify(withRates(), config, notice(fields.MerchantTradeNo, { amt: 30 })), 200);
    assert.equal(await funding(), undefined);
    assert.equal((await db.doc(`ecpayOrders/${fields.MerchantTradeNo}`).get()).get('status'), 'pending');
  });

  test('a payment whose order was already dropped still counts, at the amount ECPay says, once', async () => {
    const n = notice('20261006deadbeef0000', { amt: 500, fee: '14' });
    assert.equal(await ecpayNotify(withRates(), config, n), 200);
    assert.equal(await ecpayNotify(withRates(), config, n), 200);
    assert.equal(await received(), 486);
    assert.equal((await db.doc('ecpayOrders/20261006deadbeef0000').get()).exists, false);
  });

  test('a failed payment is not counted', async () => {
    const { fields } = await start(300);
    assert.equal(await ecpayNotify(withRates(), config, notice(fields.MerchantTradeNo, { rtnCode: '10100248' })), 200);
    assert.equal(await funding(), undefined);
    assert.equal((await db.doc(`ecpayOrders/${fields.MerchantTradeNo}`).get()).get('status'), 'pending');
  });

  test("模擬付款 from ECPay's back office is not counted", async () => {
    const { fields } = await start(300);
    assert.equal(await ecpayNotify(withRates(), config, notice(fields.MerchantTradeNo, { simulated: '1' })), 200);
    assert.equal(await funding(), undefined);
  });

  test('without the keys set up, ECPay is asked to send it again later', async () => {
    assert.equal(await ecpayNotify(withRates(), null, notice('20261006deadbeef0000')), 503);
  });
});

describe('after paying', () => {
  test('the payer lands back on the support page, with no payment details in the address', () => {
    const app = 'https://marthasit.web.app';
    assert.equal(returnLocation(app, { RtnCode: '1', TradeNo: 'x', CheckMacValue: 'y' }), `${app}/support?paid=1`);
    assert.equal(returnLocation(app, { RtnCode: '10100248' }), `${app}/support?paid=0`);
    assert.equal(returnLocation(app, null), `${app}/support`);
    assert.equal(returnLocation(app, { RtnCode: '1' }, '/en'), `${app}/en/support?paid=1`, "back to the page's language");
    assert.equal(returnLocation(app, { RtnCode: '1' }, '/'), `${app}/support?paid=1`);
  });

  test('orders nobody paid are dropped after three days; paid ones stay', async () => {
    const d = withRates();
    const paid = await start(100);
    await ecpayNotify(d, config, notice(paid.fields.MerchantTradeNo, { amt: 100, fee: '3' }));
    const unpaid = await start(100);
    setNow(new Date('2026-10-09T08:59:00+08:00'));
    await dropExpiredOrders(deps);
    assert.equal((await db.collection('ecpayOrders').get()).size, 2);
    setNow(new Date('2026-10-09T09:01:00+08:00'));
    await dropExpiredOrders(deps);
    const left = (await db.collection('ecpayOrders').get()).docs.map((d) => d.id);
    assert.deepEqual(left, [paid.fields.MerchantTradeNo]);
    assert.notEqual(unpaid.fields.MerchantTradeNo, paid.fields.MerchantTradeNo);
  });
});

describe('a 線上支持 payment refunded in ECPay\'s back office', () => {
  const paid = () =>
    recordPayment(withRates(), {
      id: 'ecpay_M20261006A',
      store: 'ecpay',
      productId: 'web_once',
      amount: 97,
      currency: 'TWD',
      at: new Date('2026-09-28T10:00:00+08:00'),
    });
  const september = async () => (await db.doc('fundingMonths/2026-09').get()).get('received');

  test('comes off the month it was paid in, by its order number; undoing puts it back', async () => {
    await paid();
    const d = withRates();
    const r = await adminRefundOnlineSupport(d, op, { orderNo: ' M20261006A ', refunded: true });
    assert.deepEqual(r, { amountTwd: 97, month: '2026-09' });
    assert.equal(await september(), 0);
    await adminRefundOnlineSupport(d, op, { orderNo: 'M20261006A', refunded: true });
    assert.equal(await september(), 0, 'once');
    await adminRefundOnlineSupport(d, op, { orderNo: 'M20261006A', refunded: false });
    assert.equal(await september(), 97);
  });

  test('only the platform operator, only a payment that came in', async () => {
    await paid();
    await rejectsWith(adminRefundOnlineSupport(withRates(), caller('alice'), { orderNo: 'M20261006A', refunded: true }), 'permissionDenied');
    await rejectsWith(adminRefundOnlineSupport(withRates(), op, { orderNo: 'NOSUCHORDER', refunded: true }), 'notFound');
    await rejectsWith(adminRefundOnlineSupport(withRates(), op, { orderNo: 'M-1', refunded: true }), 'unknown');
    assert.equal(await september(), 97);
    assert.equal(await db.doc('fundingPayments/ecpay_NOSUCHORDER').get().then((d) => d.exists), false);
  });
});
