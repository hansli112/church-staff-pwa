import { isDeepStrictEqual } from 'node:util';

import type { Deps } from './common.js';

/**
 * The church settings every member's app reads on opening. settings/shared
 * holds a copy of them all, so the app listens to one doc instead of five:
 * each listen is read again when the app comes back after half an hour.
 * Not the webhook settings, which only admins read.
 */
export const SHARED_SETTINGS = ['services', 'ministries', 'calendar', 'link', 'linkContent'] as const;

export const isSharedSetting = (doc: string) => (SHARED_SETTINGS as readonly string[]).includes(doc);

/**
 * Copies church [cid]'s [SHARED_SETTINGS] to settings/shared, each as its
 * doc's data or null when there is none; whatever wrote a doc, the copy
 * follows. The app reads a doc on its own while its key is missing.
 * Returns whether it wrote. A deleted church is left alone, so the copy
 * does not outlive it.
 *
 * Not a transaction: its reads would lock the settings, and an admin's
 * save of them would be turned away meanwhile. The copy is written only
 * if it is still the one read before the settings were; otherwise it is
 * done again, so of two copies at once the later settings win.
 */
export async function copySharedSettings(deps: Deps, cid: string) {
  const church = deps.db.doc(`churches/${cid}`);
  const settings = church.collection('settings');
  const sharedRef = settings.doc('shared');
  for (let attempt = 1; ; attempt++) {
    const was = await sharedRef.get();
    const [root, ...docs] = await deps.db.getAll(church, ...SHARED_SETTINGS.map((d) => settings.doc(d)));
    if (!root.exists || root.get('status') === 'deleted') return false;
    const next = Object.fromEntries(SHARED_SETTINGS.map((d, i) => [d, docs[i].data() ?? null]));
    if (isDeepStrictEqual(was.data(), next)) return false;
    try {
      await (was.exists ? sharedRef.update(next, { lastUpdateTime: was.updateTime! }) : sharedRef.create(next));
      return true;
    } catch (e) {
      // FAILED_PRECONDITION, ALREADY_EXISTS: another copy came first.
      const code = (e as { code?: number }).code;
      if ((code !== 9 && code !== 6) || attempt >= 5) throw e;
    }
  }
}
