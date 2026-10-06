// Shared by the 雲端費用進度 tests.
import { RATES_URL } from '../src/funding.js';
import { caller, db, deps, fakeFetch } from './support.js';

export const op = caller('hans', { operator: true });

/** er-api: how much of each currency one TWD buys. */
export const RATES = {
  result: 'success',
  time_last_update_unix: 1791244800,
  rates: { TWD: 1, USD: 0.03125, HKD: 0.25, MYR: 0.125 },
};
export const ratesRoute = { [RATES_URL]: { body: RATES } };

/** Deps whose only reachable endpoint is the exchange rate service. */
export const withRates = () => ({ ...deps, fetch: fakeFetch(ratesRoute).fetch });

export const funding = async () => (await db.doc('platform/funding').get()).data();
