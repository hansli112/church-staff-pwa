import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { playNotification } from '../src/fundingPlay.js';
import { funding, ratesRoute } from './fundingFixtures.js';
import { clearFirestore, deps, fakeFetch, setNow, type FakeResponse } from './support.js';

const META =
  'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token?scopes=https://www.googleapis.com/auth/androidpublisher';
const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/app.marthasit';
const NOW = new Date('2026-10-06T09:00:00+08:00');

const order = (id: string, units: string, nanos: number, currency = 'TWD', extra = {}): FakeResponse => ({
  body: {
    orderId: id,
    state: 'PROCESSED',
    createTime: '2026-10-06T00:00:00Z',
    lineItems: [{ productId: 'tip_small' }],
    total: { currencyCode: currency, units: '30', nanos: 0 },
    developerRevenueInBuyerCurrency: { currencyCode: currency, units, nanos },
    ...extra,
  },
});
const google = (extra: Record<string, FakeResponse> = {}) =>
  fakeFetch({
    ...ratesRoute,
    [META]: { body: { access_token: 'tok', expires_in: 3600 } },
    [`${API}/purchases/products/tip_small/tokens/t1`]: { body: { orderId: 'GPA.1', purchaseState: 0 } },
    [`${API}/orders/GPA.1`]: order('GPA.1', '25', 500_000_000),
    ...extra,
  });
const withGoogle = (extra: Record<string, FakeResponse> = {}) => ({ ...deps, fetch: google(extra).fetch });
const oneTime = () => ({
  packageName: 'app.marthasit',
  oneTimeProductNotification: { notificationType: 1, purchaseToken: 't1', sku: 'tip_small' },
});
const voided = (refundType = 1) => ({
  packageName: 'app.marthasit',
  voidedPurchaseNotification: { purchaseToken: 't1', orderId: 'GPA.1', productType: 2, refundType },
});
const received = async () => (await funding())?.received;

beforeEach(async () => {
  await clearFirestore();
  setNow(NOW);
});

describe('Google tells us about a payment', () => {
  test('a tip counts what Google pays us, once', async () => {
    const f = google();
    const d = { ...deps, fetch: f.fetch };
    await playNotification(d, oneTime(), NOW);
    await playNotification(d, oneTime(), NOW);
    assert.equal(await received(), 26); // NT$25.5, rounded
    assert.ok(f.requests.filter((r) => r.url.startsWith(API)).every((r) => r.headers.authorization === 'Bearer tok'));
  });

  test('a subscription counts each order: the first one and every renewal', async () => {
    const d = withGoogle({
      [`${API}/purchases/subscriptionsv2/tokens/s1`]: {
        body: { lineItems: [{ productId: 'supporter_monthly', latestSuccessfulOrderId: 'GPA.2' }] },
      },
      [`${API}/orders/GPA.2`]: order('GPA.2', '3', 0, 'USD'),
    });
    const sub = { notificationType: 4, purchaseToken: 's1', subscriptionId: 'supporter_monthly' };
    await playNotification(d, { packageName: 'app.marthasit', subscriptionNotification: sub }, NOW);
    assert.equal(await received(), 96); // US$3 × 32
  });

  test('test purchases are left out', async () => {
    const d = withGoogle({
      [`${API}/purchases/products/tip_small/tokens/t1`]: { body: { orderId: 'GPA.1', purchaseState: 0, purchaseType: 0 } },
    });
    await playNotification(d, oneTime(), NOW);
    assert.equal(await funding(), undefined);
  });

  test('a voided purchase comes off again, even when the void comes first', async () => {
    const d = withGoogle();
    await playNotification(d, oneTime(), NOW);
    await playNotification(d, voided(), NOW);
    assert.equal(await received(), 0);

    await clearFirestore();
    await playNotification(d, voided(), NOW);
    await playNotification(d, oneTime(), NOW);
    assert.equal(await received(), 0);
  });

  test('a partial refund takes off only its share', async () => {
    const d = withGoogle();
    await playNotification(d, oneTime(), NOW);
    const partly = order('GPA.1', '25', 500_000_000, 'TWD', {
      orderHistory: { partialRefundEvents: [{ state: 'PROCESSED', refundDetails: { total: { currencyCode: 'TWD', units: '15' } } }] },
    });
    await playNotification({ ...deps, fetch: google({ [`${API}/orders/GPA.1`]: partly }).fetch }, voided(2), NOW);
    assert.equal(await received(), 13); // half of NT$26
  });

  test('an order not settled yet is tried again; after three days it is given up', async () => {
    const unsettled = withGoogle({ [`${API}/orders/GPA.1`]: { body: { orderId: 'GPA.1', state: 'PENDING' } } });
    await assert.rejects(playNotification(unsettled, oneTime(), NOW));
    await playNotification(unsettled, oneTime(), new Date('2026-10-02T09:00:00+08:00'));
    assert.equal(await funding(), undefined);
  });

  test('another app\'s notices and test notices are ignored', async () => {
    const d = withGoogle();
    await playNotification(d, { ...oneTime(), packageName: 'com.other' }, NOW);
    await playNotification(d, { packageName: 'app.marthasit', testNotification: { version: '1.0' } }, NOW);
    assert.equal(await funding(), undefined);
  });
});
