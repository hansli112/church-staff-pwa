/**
 * 服事表異動, before any document is read: where a roster write came from
 * (`via`) and whom that tells, and what waits for 通知同工 (#90). The app
 * keeps the same in app/lib/domain/roster_news.dart; both run
 * testdata/roster_changes.json.
 */

/**
 * Whom a write tells, by where it came from: `now` pushes and goes to the
 * webhook; `planned` (安排服事) goes to the webhook and waits for 通知同工
 * to push; `webhook` (an import, or its undo) only goes to the webhook;
 * `nobody` (an event's roster the backend moved without news, see
 * eventRosters.ts) tells no one.
 */
const VIAS = {
  app: 'now',
  plan: 'planned',
  import: 'webhook',
  calendar: 'now',
  restore: 'nobody',
  relink: 'nobody',
  timeZone: 'nobody',
} as const;

export type Via = keyof typeof VIAS;
export type Tells = (typeof VIAS)[Via];

/** What the app writes, and so all firestore.rules and editLedDuties take from it. */
export const APP_VIAS: readonly Via[] = ['app', 'plan', 'import'];

/** A roster document's `via`: the app's when it has none (or one this does not know). */
export const viaOf = (v: unknown): Via => (typeof v === 'string' && Object.hasOwn(VIAS, v) ? (v as Via) : 'app');

export const tellsOf = (via: Via): Tells => VIAS[via];

/**
 * What waits for 通知同工 for one person on one day once a change puts them
 * from [before] to [after]: the duties they had before the first change
 * that waits, or null for nothing. [waiting] is what waited until now.
 * [told] when this change reaches them some other way (made outside
 * 安排服事, or by them): then it is taken as having always been so. Once
 * they have what they had before, nothing is left to tell.
 */
export function plannedAfter(waiting: string[] | null, before: string[], after: string[], told: boolean): string[] | null {
  if (waiting === null) return told || sameSet(before, after) ? null : before;
  const roles = told
    ? [...waiting.filter((r) => after.includes(r) || !before.includes(r)), ...after.filter((r) => !before.includes(r) && !waiting.includes(r))]
    : waiting;
  return sameSet(roles, after) ? null : roles;
}

const sameSet = (a: string[], b: string[]) => new Set(a).size === new Set(b).size && a.every((r) => b.includes(r));
