import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Environment } from '@apple/app-store-server-library';

import { appStoreNotification, appleNet, appleVerifier, type AppleVerifier } from '../src/fundingApple.js';
import { funding, withRates } from './fundingFixtures.js';
import { clearFirestore, db, deps, setNow } from './support.js';

/** Fake Apple: payloads are plain JSON instead of signed JWS. */
const apple: AppleVerifier = {
  notification: async (s) => {
    if (s === 'forged') throw new Error('bad signature');
    return JSON.parse(s);
  },
  transaction: async (s) => JSON.parse(s),
};
const notice = (type: string, tx: Record<string, unknown>) => ({
  signedPayload: JSON.stringify({ notificationType: type, signedTransactionInfo: JSON.stringify(tx) }),
});
const tip = {
  transactionId: '2000001',
  productId: 'tip_small',
  price: 105_000,
  currency: 'TWD',
  storefront: 'TWN',
  purchaseDate: Date.parse('2026-10-06T08:00:00+08:00'),
  inAppOwnershipType: 'PURCHASED',
};
const received = async () => (await funding())?.received;

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-06T09:00:00+08:00'));
});

describe('Apple\'s share', () => {
  test('sales tax, then the 15% commission, come off the price', () => {
    assert.equal(appleNet(105_000, 'TWN'), 85); // NT$105 with 5% tax
    assert.equal(appleNet(10_000, 'HKG'), 8.5); // no sales tax in Hong Kong
    assert.equal(appleNet(10_800, 'MYS'), 8.5); // 8% service tax
  });

  test('a storefront we have no tax for is taken as 10%, to err low', () => {
    assert.equal(appleNet(11_000, 'BRA'), 8.5);
  });
});

describe('Apple tells us about a payment', () => {
  test('a tip is added to this month, once even when Apple sends it again', async () => {
    const d = withRates();
    assert.equal(await appStoreNotification(d, apple, notice('ONE_TIME_CHARGE', tip)), 200);
    assert.equal(await appStoreNotification(d, apple, notice('ONE_TIME_CHARGE', tip)), 200);
    assert.equal(await received(), 85);
  });

  test('foreign money is changed into NT dollars at the day\'s rate', async () => {
    const hk = { ...tip, transactionId: '2000002', price: 10_000, currency: 'HKD', storefront: 'HKG' };
    await appStoreNotification(withRates(), apple, notice('ONE_TIME_CHARGE', hk));
    assert.equal(await received(), 34); // HK$8.5 × 4
  });

  test('subscribing and each renewal count', async () => {
    const d = withRates();
    const sub = { ...tip, productId: 'supporter_monthly' };
    await appStoreNotification(d, apple, notice('SUBSCRIBED', { ...sub, transactionId: '3000001' }));
    await appStoreNotification(d, apple, notice('DID_RENEW', { ...sub, transactionId: '3000002' }));
    assert.equal(await received(), 170);
  });

  test('a family member\'s shared access is not a payment', async () => {
    const shared = { ...tip, productId: 'supporter_monthly', inAppOwnershipType: 'FAMILY_SHARED' };
    await appStoreNotification(withRates(), apple, notice('SUBSCRIBED', shared));
    assert.equal(await funding(), undefined);
  });

  test('a refund comes off the month it was paid in, once; a reversed refund puts it back', async () => {
    const d = withRates();
    await appStoreNotification(d, apple, notice('ONE_TIME_CHARGE', tip));
    await appStoreNotification(d, apple, notice('REFUND', tip));
    await appStoreNotification(d, apple, notice('REFUND', tip));
    assert.equal(await received(), 0);
    await appStoreNotification(d, apple, notice('REFUND_REVERSED', tip));
    assert.equal(await received(), 85);
  });

  test('a refund that arrives before its payment still keeps the payment out', async () => {
    const d = withRates();
    await appStoreNotification(d, apple, notice('REFUND', tip));
    await appStoreNotification(d, apple, notice('ONE_TIME_CHARGE', tip));
    assert.equal(await received(), 0);
  });

  test('other notices change nothing; a forged one is refused', async () => {
    const d = withRates();
    assert.equal(await appStoreNotification(d, apple, notice('DID_CHANGE_RENEWAL_STATUS', tip)), 200);
    assert.equal(await appStoreNotification(d, apple, { signedPayload: 'forged' }), 400);
    assert.equal(await appStoreNotification(d, apple, {}), 400);
    assert.equal(await funding(), undefined);
  });

  test('the real check refuses a notice Apple did not sign, and prod without the app\'s Apple ID', async () => {
    const payload = Buffer.from(JSON.stringify({ notificationType: 'ONE_TIME_CHARGE', data: { environment: 'Sandbox' } })).toString('base64url');
    const forged = { signedPayload: `eyJhbGciOiJFUzI1NiJ9.${payload}.c2ln` };
    assert.equal(await appStoreNotification(deps, appleVerifier(Environment.SANDBOX), forged), 400);
    assert.equal(await appStoreNotification(deps, appleVerifier(Environment.PRODUCTION), forged), 400);
  });

  test('no record of who paid: only the amount, product and time', async () => {
    await appStoreNotification(withRates(), apple, notice('ONE_TIME_CHARGE', { ...tip, appAccountToken: 'someone' }));
    const [payment] = (await db.collection('fundingPayments').get()).docs;
    assert.deepEqual(Object.keys(payment.data()).sort(), [
      'amount',
      'amountTwd',
      'at',
      'currency',
      'month',
      'productId',
      'refundedTwd',
      'store',
    ]);
  });
});
