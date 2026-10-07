import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import {
  GATEWAYS,
  ORDERS_PER_HOUR,
  decryptTradeInfo,
  dropExpiredOrders,
  encryptTradeInfo,
  mpgFields,
  newebpayConfig,
  newebpayNotify,
  newebpayStart,
  parseTradeInfo,
  returnLocation,
  tradeSha,
  type NewebpayConfig,
} from '../src/fundingNewebpay.js';
import { funding, withRates } from './fundingFixtures.js';
import { clearFirestore, db, deps, setNow } from './support.js';

// The official sample in 線上交易─幕前支付技術串接手冊 NDNF-1.2.6, §4.1.1–4.1.4.
const SPEC = {
  key: 'Fs5cX1TGqYM2PpdbE14a9H83YQSQF5jn',
  iv: 'C6AcmfqJILwgnhIP',
  request:
    'MerchantID=MS127874575&RespondType=String&TimeStamp=1695795410&Version=2.0&MerchantOrderNo=Vanespl_ec_1695795410&Amt=30&ItemDesc=test&NotifyURL=https%3A%2F%2Fwebhook.site%2Fd4db5ad1-2278-466a-9d66-78585c0dbadb',
  requestInfo:
    'f79eac33c4f3245d58f17b544c5d38b09457a6d77e77bae6f10fcc7236fe153ccef1a80001c0746afc063a7570f80ad970d8a32c72332c9ec5547410188007876bdca2bafa52d07d31b6b183f2204d6e4feee6d245e286ab198cf95422ad5843c7696fc943cbb65979ad207607d4b5d97dac4a90ccd5e7a37adb7d7062e838be09d94e8c5dfa145c048e17feabe58c2e310792f0f50f5af32961ffb07ff6649ae1021ad558242551de5f09316e3182e198775e5d1ad5b66a70be290004de750fa85d86b0c2f087b40005d89e048be2ab6fd83f1c522494c093426a10a1f73fe4',
  requestSha: '84E4D9F96537E029F8450BE1E759080F9AF6995921B7F6F9AAFDDD2C36E7B287',
  noticeInfo:
    'ee11d1501e6dc8433c75988258f2343d11f4d0a423be672e8e02aaf373c53c2363aeffdb4992579693277359b3e449ebe644d2075fdfbc10150b1c40e7d24cb215febefdb85b16a5cde449f6b06c58a5510d31e8d34c95284d459ae4b52afc1509c2800976a5c0b99ef24cfd28a2dfc8004215a0c98a1d3c77707773c2f2132f9a9a4ce3475cb888c2ad372485971876f8e2fec0589927544c3463d30c785c2d3bd947c06c8c33cf43e131f57939e1f7e3b3d8c3f08a84f34ef1a67a08efe177f1e663ecc6bedc7f82640a1ced807b548633cfa72d060864271ec79854ee2f5a170aa902000e7c61d1269165de330fce7d10663d1668c711571776365bfdcd7ddc915dcb90d31a9f27af9b79a443ca8302e508b0dbaac817d44cfc44247ae613075dde4ac960f1bdff4173b915e4344bc4567bd32e86be7d796e6d9b9cf20476e4996e98ccc315f1ed03a34139f936797d971f2a3f90bc18f8a155a290bcbcf04f4277171c305bf554f5cba243154b30082748a81f2e5aa432ef9950cc9668cd4330ef7c37537a6dcb5e6ef01b4eca9705e4b097cf6913ee96e81d0389e5f775',
  noticeSha: 'C80876AEBAC0036268C0E240E5BFF69C0470DE9606EEE083C5C8DD64FDB3347A',
};

/** Fake keys of the right lengths; never a real store's. */
const config: NewebpayConfig = newebpayConfig({
  merchantId: 'MS000000001',
  gateway: 'test',
  hashKey: 'abcdefghijklmnopqrstuvwxyz012345',
  hashIv: 'ABCDEFGHIJKLMNOP',
  project: 'demo-martha',
  appUrl: 'https://demo-martha.web.app',
})!;

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-06T09:00:00+08:00'));
});

describe('NewebPay encryption (NDNF-1.2.6 §4.1)', () => {
  test('the spec\'s request encrypts to the spec\'s TradeInfo and TradeSha', () => {
    assert.equal(encryptTradeInfo(SPEC.request, SPEC.key, SPEC.iv), SPEC.requestInfo);
    assert.equal(tradeSha(SPEC.requestInfo, SPEC.key, SPEC.iv), SPEC.requestSha);
  });

  test('the spec\'s notice checks out and decrypts to its payment', () => {
    assert.equal(tradeSha(SPEC.noticeInfo, SPEC.key, SPEC.iv), SPEC.noticeSha);
    const { status, result } = parseTradeInfo(decryptTradeInfo(SPEC.noticeInfo, SPEC.key, SPEC.iv));
    assert.equal(status, 'SUCCESS');
    assert.equal(result.Message, '授權成功');
    assert.equal(result.MerchantOrderNo, 'Vanespl_ec_1695795668');
    assert.equal(result.Amt, '30');
    assert.equal(result.TradeNo, '23092714215835071');
    assert.equal(result.PayTime, '2023-09-27 14:21:59');
  });

  test('round trip, Chinese included; wrong keys or junk do not decrypt', () => {
    const plain = new URLSearchParams({ ItemDesc: '馬大別忙 雲端費用', Amt: '300' }).toString();
    const sealed = encryptTradeInfo(plain, config.hashKey, config.hashIv);
    assert.equal(decryptTradeInfo(sealed, config.hashKey, config.hashIv), plain);
    assert.throws(() => decryptTradeInfo(sealed, SPEC.key, SPEC.iv));
    assert.throws(() => decryptTradeInfo('not hex', config.hashKey, config.hashIv));
  });

  test('JSON notices: Result as an object or as a JSON string', () => {
    const r = { MerchantID: 'MS1', Amt: 300, MerchantOrderNo: 'a1' };
    for (const Result of [r, JSON.stringify(r)]) {
      const parsed = parseTradeInfo(JSON.stringify({ Status: 'SUCCESS', Message: 'ok', Result }));
      assert.deepEqual(parsed, { status: 'SUCCESS', result: { MerchantID: 'MS1', Amt: '300', MerchantOrderNo: 'a1' } });
    }
  });
});

describe('NewebPay config', () => {
  const base = { merchantId: 'MS123456789', gateway: 'production', hashKey: 'k'.repeat(32), hashIv: 'v'.repeat(16), project: 'marthasit', appUrl: 'https://marthasit.web.app' };

  test('notices and the way back are this project\'s functions; 返回商店 is the support page', () => {
    assert.deepEqual(newebpayConfig(base), {
      merchantId: 'MS123456789',
      hashKey: base.hashKey,
      hashIv: base.hashIv,
      gateway: 'production',
      notifyUrl: 'https://asia-east1-marthasit.cloudfunctions.net/newebpayNotify',
      returnUrl: 'https://asia-east1-marthasit.cloudfunctions.net/newebpayReturn',
      backUrl: 'https://marthasit.web.app/support',
    });
  });

  test('off until it is all set: no merchant, placeholder keys, no environment', () => {
    assert.equal(newebpayConfig({ ...base, merchantId: undefined }), null);
    assert.equal(newebpayConfig({ ...base, hashKey: 'placeholder' }), null);
    assert.equal(newebpayConfig({ ...base, hashIv: 'placeholder' }), null);
    assert.equal(newebpayConfig({ ...base, gateway: undefined }), null);
  });

  test('prod takes only the production gateway; dev may test', () => {
    assert.equal(newebpayConfig({ ...base, gateway: 'test' }), null);
    assert.equal(newebpayConfig({ ...base, gateway: 'test', project: 'marthasit-dev' })?.gateway, 'test');
  });
});

/** Starts an order and reads back what the page would post. */
async function start(amount: unknown) {
  const r = await newebpayStart(deps, config, { amount });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const { gateway, fields } = r.body as { gateway: string; fields: Record<string, string> };
  const params = Object.fromEntries(new URLSearchParams(decryptTradeInfo(fields.TradeInfo, config.hashKey, config.hashIv)));
  return { gateway, fields, params };
}

describe('starting a 線上支持 payment', () => {
  test('a signed MPG form for NewebPay\'s test gateway, and a pending order without personal data', async () => {
    const { gateway, fields, params } = await start(300);
    assert.equal(gateway, GATEWAYS.test);
    assert.equal(fields.MerchantID, config.merchantId);
    assert.equal(fields.Version, '2.3');
    assert.equal(fields.TradeSha, tradeSha(fields.TradeInfo, config.hashKey, config.hashIv));
    assert.match(params.MerchantOrderNo, /^[A-Za-z0-9_]{1,30}$/);
    assert.deepEqual({ ...params, MerchantOrderNo: '' }, {
      MerchantID: config.merchantId,
      RespondType: 'JSON',
      TimeStamp: String(Date.parse('2026-10-06T09:00:00+08:00') / 1000),
      Version: '2.3',
      MerchantOrderNo: '',
      Amt: '300',
      ItemDesc: '馬大別忙 雲端費用 線上支持',
      TradeLimit: '900',
      ReturnURL: config.returnUrl,
      NotifyURL: config.notifyUrl,
      ClientBackURL: config.backUrl,
      EmailModify: '1',
      CREDIT: '1',
      APPLEPAY: '1',
      ANDROIDPAY: '1',
    });
    const order = (await db.doc(`newebpayOrders/${params.MerchantOrderNo}`).get()).data();
    assert.deepEqual(Object.keys(order ?? {}).sort(), ['amount', 'createdAt', 'expiresAt', 'status']);
    assert.equal(order?.amount, 300);
    assert.equal(order?.status, 'pending');
  });

  test('every order number is new', async () => {
    const a = await start(100);
    const b = await start(100);
    assert.notEqual(a.params.MerchantOrderNo, b.params.MerchantOrderNo);
  });

  test('a whole number of NT dollars from 30 to 10,000, or nothing starts', async () => {
    for (const bad of [29, 10_001, 100.5, -100, '1e3', '', null, undefined]) {
      const r = await newebpayStart(deps, config, { amount: bad });
      assert.deepEqual(r, { status: 400, body: { error: 'amount' } }, `amount ${String(bad)}`);
    }
    assert.equal((await newebpayStart(deps, config, null)).status, 400);
    assert.equal((await newebpayStart(deps, config, { amount: '30' })).status, 200);
    assert.equal((await newebpayStart(deps, config, { amount: ' 300 ' })).status, 200);
    assert.equal((await newebpayStart(deps, config, { amount: 10_000 })).status, 200);
  });

  test('not set up yet: nothing starts', async () => {
    assert.deepEqual(await newebpayStart(deps, null, { amount: 300 }), { status: 503, body: { error: 'unavailable' } });
    assert.equal((await db.collection('newebpayOrders').get()).size, 0);
  });

  test('no more than the hourly limit, all callers together; the next hour starts over', async () => {
    await db.doc('platform/newebpayRate').set({ hour: '2026-10-06T01', count: ORDERS_PER_HOUR - 1 });
    assert.equal((await newebpayStart(deps, config, { amount: 100 })).status, 200);
    assert.deepEqual(await newebpayStart(deps, config, { amount: 100 }), { status: 429, body: { error: 'busy' } });
    assert.equal((await db.collection('newebpayOrders').get()).size, 1);
    setNow(new Date('2026-10-06T10:00:00+08:00'));
    assert.equal((await newebpayStart(deps, config, { amount: 100 })).status, 200);
  });
});

/** NewebPay's notice for [orderNo], sealed with [keys]. */
function notice(
  orderNo: string,
  { status = 'SUCCESS', amt = 300, keys = config }: { status?: string; amt?: number; keys?: Pick<NewebpayConfig, 'hashKey' | 'hashIv' | 'merchantId'> } = {},
) {
  const info = encryptTradeInfo(
    JSON.stringify({
      Status: status,
      Message: status === 'SUCCESS' ? '授權成功' : '授權失敗',
      Result: {
        MerchantID: keys.merchantId,
        Amt: amt,
        TradeNo: '26100608000012345',
        MerchantOrderNo: orderNo,
        PaymentType: 'CREDIT',
        RespondType: 'JSON',
        PayTime: '2026-10-06 08:00:00',
        IP: '203.0.113.9',
        Card6No: '400022',
        Card4No: '1111',
      },
    }),
    keys.hashKey,
    keys.hashIv,
  );
  return {
    Status: status,
    MerchantID: keys.merchantId,
    Version: '2.3',
    TradeInfo: info,
    TradeSha: tradeSha(info, keys.hashKey, keys.hashIv),
  };
}

const received = async () => (await funding())?.received;

describe('NewebPay tells us about a payment', () => {
  test('a paid order counts toward this month, after NewebPay\'s fee, once even when sent again', async () => {
    const d = withRates();
    const { params } = await start(300);
    const n = notice(params.MerchantOrderNo);
    assert.equal(await newebpayNotify(d, config, n), 200);
    assert.equal(await newebpayNotify(d, config, n), 200);
    assert.equal(await received(), 292); // NT$300 less 2.8%, to the nearest dollar
    assert.equal((await db.doc('fundingMonths/2026-10').get()).get('received'), 292);

    const payment = (await db.doc(`fundingPayments/newebpay_${params.MerchantOrderNo}`).get()).data();
    assert.deepEqual({ ...payment, at: payment?.at.toDate() }, {
      store: 'newebpay',
      productId: 'web_once',
      amount: 291.6,
      currency: 'TWD',
      amountTwd: 292,
      refundedTwd: 0,
      month: '2026-10',
      at: new Date('2026-10-06T08:00:00+08:00'),
    });
    const order = (await db.doc(`newebpayOrders/${params.MerchantOrderNo}`).get()).data();
    assert.equal(order?.status, 'paid');
    assert.equal(order?.tradeNo, '26100608000012345');
    assert.equal(order?.paymentType, 'CREDIT');
    assert.equal(order?.expiresAt, undefined);
    // Nothing about the payer: no IP, no card digits, anywhere.
    assert.doesNotMatch(JSON.stringify({ payment, order }), /203\.0\.113|400022|1111/);
  });

  test('a TradeSha that does not check out is refused, and nothing counts', async () => {
    const { params } = await start(300);
    const forged = { ...notice(params.MerchantOrderNo), TradeSha: '0'.repeat(64) };
    assert.equal(await newebpayNotify(withRates(), config, forged), 400);
    const otherKeys = notice(params.MerchantOrderNo, { keys: { ...config, hashKey: 'z'.repeat(32) } });
    assert.equal(await newebpayNotify(withRates(), config, otherKeys), 400);
    assert.equal(await newebpayNotify(withRates(), config, { Status: 'SUCCESS' }), 400);
    assert.equal(await funding(), undefined);
  });

  test('another store\'s notice is refused', async () => {
    const { params } = await start(300);
    const other = notice(params.MerchantOrderNo, { keys: { ...config, merchantId: 'MS999' } });
    assert.equal(await newebpayNotify(withRates(), config, other), 400);
    assert.equal(await funding(), undefined);
  });

  test('an amount other than the order\'s is not counted', async () => {
    const { params } = await start(300);
    assert.equal(await newebpayNotify(withRates(), config, notice(params.MerchantOrderNo, { amt: 30 })), 200);
    assert.equal(await funding(), undefined);
    assert.equal((await db.doc(`newebpayOrders/${params.MerchantOrderNo}`).get()).get('status'), 'pending');
  });

  test('a payment whose order was already dropped still counts, at the amount NewebPay says, once', async () => {
    const n = notice('20261006deadbeef0000', { amt: 500 });
    assert.equal(await newebpayNotify(withRates(), config, n), 200);
    assert.equal(await newebpayNotify(withRates(), config, n), 200);
    assert.equal(await received(), 486); // NT$500 less 2.8%
    assert.equal((await db.doc('newebpayOrders/20261006deadbeef0000').get()).exists, false);
  });

  test('a failed payment is not counted', async () => {
    const { params } = await start(300);
    assert.equal(await newebpayNotify(withRates(), config, notice(params.MerchantOrderNo, { status: 'MPG03009' })), 200);
    assert.equal(await funding(), undefined);
    assert.equal((await db.doc(`newebpayOrders/${params.MerchantOrderNo}`).get()).get('status'), 'pending');
  });

  test('without the keys set up, NewebPay is asked to send it again later', async () => {
    assert.equal(await newebpayNotify(withRates(), null, notice('20261006deadbeef0000')), 503);
  });
});

describe('after paying', () => {
  test('the payer lands back on the support page, with no payment details in the address', () => {
    const app = 'https://marthasit.web.app';
    assert.equal(returnLocation(app, { Status: 'SUCCESS', TradeInfo: 'x', TradeSha: 'y' }), `${app}/support?paid=1`);
    assert.equal(returnLocation(app, { Status: 'MPG03009' }), `${app}/support?paid=0`);
    assert.equal(returnLocation(app, null), `${app}/support`);
  });

  test('orders nobody paid are dropped after three days; paid ones stay', async () => {
    const d = withRates();
    const paid = await start(100);
    await newebpayNotify(d, config, notice(paid.params.MerchantOrderNo, { amt: 100 }));
    const unpaid = await start(100);
    setNow(new Date('2026-10-09T08:59:00+08:00'));
    await dropExpiredOrders(deps);
    assert.equal((await db.collection('newebpayOrders').get()).size, 2);
    setNow(new Date('2026-10-09T09:01:00+08:00'));
    await dropExpiredOrders(deps);
    const left = (await db.collection('newebpayOrders').get()).docs.map((d) => d.id);
    assert.deepEqual(left, [paid.params.MerchantOrderNo]);
    assert.notEqual(unpaid.params.MerchantOrderNo, paid.params.MerchantOrderNo);
  });
});

test('mpgFields seals exactly the given parameters', () => {
  const f = mpgFields(config, { Amt: '1' });
  assert.equal(decryptTradeInfo(f.TradeInfo, config.hashKey, config.hashIv), 'Amt=1');
});
