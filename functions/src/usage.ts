/**
 * How the app is used, in the logs (2026-11-26): who arranges rosters and
 * makes events, and as what, to see whether a duty's 負責人 or a 事工's
 * 負責人 use what they were given. Only IDs, never names; Cloud Logging
 * keeps them 30 days. Query: `jsonPayload.message="usage"`.
 */

import { logger } from 'firebase-functions/v2';

import { groupOf, type Powers } from './powers.js';

/** What someone acted as: the broadest of their 身分 that lets them. */
export type ActingAs = 'admin' | 'office' | 'serviceLead' | 'ministryLead' | 'smallGroupLead' | 'dutyLead';

/** As what [powers] write an event of [group] ('' the church's). */
export function eventActingAs(powers: Powers, group: string): ActingAs {
  if (powers.admin) return 'admin';
  if (powers.writesAnyEvent) return 'office';
  const g = groupOf(group);
  return g?.kind === 'ministry' ? 'ministryLead' : g?.kind === 'small' ? 'smallGroupLead' : 'serviceLead';
}

/** A roster's duties arranged, by [uid]: written by the app (not as a duty's 負責人), or through editLedDuties. */
export function logRosterEdit(cid: string, rosterId: string, uid: string, as: ActingAs | 'app') {
  logger.info('usage', { what: 'rosterEdit', cid, rosterId, uid, as });
}

/** An event made, changed or deleted by [uid] as [as], of [group] ('' the church's). */
export function logEventWrite(cid: string, uid: string, op: 'created' | 'updated' | 'deleted', group: string, as: ActingAs) {
  logger.info('usage', { what: 'eventWrite', cid, uid, op, group: groupOf(group)?.kind ?? 'church', as });
}
