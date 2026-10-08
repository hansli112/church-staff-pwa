import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { adminFunding, adminSetFundingCosts, monthlyTarget, publishFunding, recordPayment, setRefund, summarize, type Payment } from '../src/funding.js';
import { appStoreNotification, type AppleVerifier } from '../src/fundingApple.js';
import { RATES, funding, op, withRates } from './fundingFixtures.js';
import { caller, clearFirestore, db, deps, fakeFetch, rejectsWith, setNow } from './support.js';

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-06T09:00:00+08:00'));
});

describe('this month\'s target', () => {
  test('monthly items count in full, yearly ones a twelfth, US dollars in NT dollars', () => {
    const target = monthlyTarget(
      [
        { name: '雲端', amount: 300, currency: 'TWD', per: 'month' },
        { name: 'Apple 開發者', amount: 99, currency: 'USD', per: 'year' },
        { name: '網域', amount: 600, currency: 'TWD', per: 'year' },
      ],
      RATES.rates,
    );
    // 300 + 99 × 32 ÷ 12 + 600 ÷ 12 = 300 + 264 + 50
    assert.equal(target, 614);
  });

  test('a currency without a rate gives no target, rather than a wrong one', () => {
    assert.equal(monthlyTarget([{ name: 'x', amount: 1, currency: 'USD', per: 'month' }], {}), null);
  });
});

describe('carrying a surplus into later months', () => {
  const m = (month: string, received: number, target: number) => ({ month, received, target });

  test('what is over the target carries on; a shortfall does not', () => {
    const s = summarize([m('2026-08', 900, 500), m('2026-09', 100, 500), m('2026-10', 300, 500)], '2026-10');
    // August leaves 400; September uses it up and is 0 short, not -: 400 + 100 - 500 = 0.
    assert.deepEqual(s, { target: 500, received: 300, carried: 0, monthsLeft: 0 });
  });

  test('more than this month needs: how many more months it keeps the lights on', () => {
    const s = summarize([m('2026-08', 1600, 500), m('2026-10', 700, 500)], '2026-10');
    // August leaves 1100 (no doc for September: nothing came in, nothing counted).
    assert.deepEqual(s, { target: 500, received: 700, carried: 1100, monthsLeft: 2 });
  });

  test('nothing to pay yet: no months to count', () => {
    assert.deepEqual(summarize([m('2026-10', 50, 0)], '2026-10'), { target: 0, received: 50, carried: 0, monthsLeft: 0 });
  });
});

describe('the operator sets the costs', () => {
  const costs = [
    { name: '雲端', amount: 300, currency: 'TWD', per: 'month' },
    { name: 'Apple 開發者', amount: 99, currency: 'USD', per: 'year' },
  ];

  test('only the operator', async () => {
    await rejectsWith(adminSetFundingCosts(deps, caller('alice'), { items: costs }), 'permissionDenied');
    await rejectsWith(adminFunding(deps, caller('alice'), {}), 'permissionDenied');
  });

  test('saving the costs sets this month\'s target for everyone to see', async () => {
    const d = withRates();
    await adminSetFundingCosts(d, op, { items: costs });
    assert.deepEqual(
      { ...(await funding()), updatedAt: null },
      { month: '2026-10', target: 564, received: 0, carried: 0, monthsLeft: 0, updatedAt: null },
    );
    const back = await adminFunding(d, op, {});
    assert.deepEqual(back.costs, costs);
    assert.deepEqual(back.months, [{ month: '2026-10', received: 0, target: 564 }]);
  });

  test('bad items are refused', async () => {
    for (const bad of [
      { name: '', amount: 1, currency: 'TWD', per: 'month' },
      { name: 'x', amount: 0, currency: 'TWD', per: 'month' },
      { name: 'x', amount: 1, currency: 'JPY', per: 'month' },
      { name: 'x', amount: 1, currency: 'TWD', per: 'week' },
    ]) {
      await rejectsWith(adminSetFundingCosts(deps, op, { items: [bad] }), 'unknown');
    }
  });

  test('a past month keeps the target it had, when the costs change later', async () => {
    const d = withRates();
    setNow(new Date('2026-09-20T09:00:00+08:00'));
    await adminSetFundingCosts(d, op, { items: [{ name: '雲端', amount: 200, currency: 'TWD', per: 'month' }] });
    setNow(new Date('2026-10-06T09:00:00+08:00'));
    await adminSetFundingCosts(d, op, { items: [{ name: '雲端', amount: 400, currency: 'TWD', per: 'month' }] });
    const back = await adminFunding(d, op, {});
    assert.deepEqual(back.months, [
      { month: '2026-10', received: 0, target: 400 },
      { month: '2026-09', received: 0, target: 200 },
    ]);
  });
});

const apple: AppleVerifier = { notification: async (s) => JSON.parse(s), transaction: async (s) => JSON.parse(s) };
const charge = (tx: Record<string, unknown>) => ({
  signedPayload: JSON.stringify({ notificationType: 'ONE_TIME_CHARGE', signedTransactionInfo: JSON.stringify(tx) }),
});

describe('the daily refresh', () => {
  test('a new month starts from the surplus, with the same costs', async () => {
    const d = withRates();
    await adminSetFundingCosts(d, op, { items: [{ name: '雲端', amount: 100, currency: 'TWD', per: 'month' }] });
    await appStoreNotification(d, apple, charge({ transactionId: '1', price: 350_000, currency: 'TWD', storefront: 'TWN', purchaseDate: Date.parse('2026-10-06T08:00:00+08:00') })); // NT$283 net
    setNow(new Date('2026-11-01T00:05:00+08:00'));
    await publishFunding(d);
    const f = await funding();
    assert.deepEqual({ month: f?.month, target: f?.target, received: f?.received, carried: f?.carried, monthsLeft: f?.monthsLeft }, { month: '2026-11', target: 100, received: 0, carried: 183, monthsLeft: 0 });
  });

  test('without a fresh rate, yesterday\'s is used', async () => {
    const d = withRates();
    await adminSetFundingCosts(d, op, { items: [{ name: 'x', amount: 10, currency: 'USD', per: 'month' }] });
    setNow(new Date('2026-10-09T09:00:00+08:00'));
    await publishFunding({ ...deps, fetch: fakeFetch().fetch });
    assert.equal((await funding())?.target, 320);
  });
});

describe('the ledger: every payment, whoever it came through', () => {
  const payment = (over: Partial<Payment> = {}): Payment => ({
    id: 'newebpay_M1',
    store: 'newebpay',
    productId: 'web_once',
    amount: 500,
    currency: 'TWD',
    at: new Date('2026-10-06T08:00:00+08:00'),
    ...over,
  });
  const month = async (m = '2026-10') => (await db.doc(`fundingMonths/${m}`).get()).get('received');

  test('a payment sent twice counts once', async () => {
    const d = withRates();
    await recordPayment(d, payment());
    await recordPayment(d, payment());
    assert.equal(await month(), 500);
    assert.equal((await funding())?.received, 500);
  });

  test('foreign money counts in NT$ at the day\'s rate, rounded to the dollar', async () => {
    await recordPayment(withRates(), payment({ id: 'apple_1', store: 'apple', amount: 9.99, currency: 'USD' }));
    assert.equal(await month(), 320); // 9.99 ÷ 0.03125 = 319.68
    const kept = (await db.doc('fundingPayments/apple_1').get()).data();
    assert.deepEqual({ ...kept, at: undefined }, {
      store: 'apple', productId: 'web_once', amount: 9.99, currency: 'USD', amountTwd: 320, refundedTwd: 0, month: '2026-10', at: undefined,
    });
  });

  test('a currency without a rate is refused, so the store sends it again', async () => {
    await assert.rejects(recordPayment(withRates(), payment({ currency: 'JPY' })), /No exchange rate for JPY/);
    assert.equal(await month(), undefined);
  });

  test('counted in the month it was paid (UTC+8), not the month it arrived', async () => {
    await recordPayment(withRates(), payment({ at: new Date('2026-09-30T23:30:00+08:00') }));
    assert.equal(await month('2026-09'), 500);
    assert.equal(await month('2026-10'), undefined);
  });

  test('refunded after the payment: taken off its month, once', async () => {
    const d = withRates();
    await recordPayment(d, payment());
    await setRefund(d, 'newebpay_M1', 'newebpay', 1);
    await setRefund(d, 'newebpay_M1', 'newebpay', 1);
    assert.equal(await month(), 0);
    await setRefund(d, 'newebpay_M1', 'newebpay', 0);
    assert.equal(await month(), 500, 'a reversed refund puts it back');
  });

  test('a partial refund takes off its share', async () => {
    const d = withRates();
    await recordPayment(d, payment());
    await setRefund(d, 'newebpay_M1', 'newebpay', 0.4);
    assert.equal(await month(), 300);
  });

  test('refunded before the payment arrives: the payment never counts', async () => {
    const d = withRates();
    await setRefund(d, 'newebpay_M1', 'newebpay', 1);
    assert.equal(await month(), undefined);
    await recordPayment(d, payment());
    assert.equal(await month(), 0);
    assert.equal((await db.doc('fundingPayments/newebpay_M1').get()).get('refundedTwd'), 500);
  });
});
