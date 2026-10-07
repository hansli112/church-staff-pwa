// Length limits. The app keeps the same numbers in
// app/lib/domain/limits.dart and firestore.rules guards some of them;
// test/limits.test.ts reads all three and fails when they disagree. Keep
// every value a plain number so it can.

import { characterCount } from './text.js';

/**
 * Text limits, in characters as a person counts them (grapheme clusters,
 * characterCount): "🙏" and "👨‍👩‍👧" are one each. Not every one is checked
 * here; the app's text fields hold all of them.
 */
export const TEXT_LIMITS = {
  churchName: 60,
  homeName: 8,
  linkTitle: 30,
  linkBody: 120,
  costName: 40,
  profileName: 40,
} as const;

/** URLs and secrets in UTF-16 code units, services as a count. */
export const LIMITS = {
  url: 500,
  webhookSecretMin: 16,
  webhookSecretMax: 200,
  services: 20,
} as const;

/**
 * firestore.rules counts UTF-16 code units, not characters, so for a text
 * limit it allows this many times as many: an abuse guard, not the limit.
 * The Functions apply the same guard before counting characters.
 */
export const RULES_SIZE_FACTOR = 4;

/** At most [max] characters and at most [max] × RULES_SIZE_FACTOR UTF-16 code units. */
export function withinTextLimit(text: string, max: number): boolean {
  return text.length <= max * RULES_SIZE_FACTOR && characterCount(text) <= max;
}
