import type { DocumentSnapshot } from 'firebase-admin/firestore';

/**
 * 事工 (#82): settings/ministries. Each links duties of services, e.g.
 * 敬拜團 → 主日崇拜's 司琴; its 負責人 arrange those duties.
 */
export interface Ministry {
  id: string;
  name: string;
  duties: { service: string; duty: string }[];
}

/** The 事工 in settings/ministries as it is now (deleted ones are gone; their IDs stay in `ids`). */
export function ministriesOf(settings: DocumentSnapshot): Ministry[] {
  const list = settings.get('ministries');
  return (Array.isArray(list) ? list : []).filter(
    (m): m is Ministry => typeof m?.id === 'string' && Array.isArray(m.duties),
  );
}

/**
 * The duties the 事工 in [led] lead on a day of [serviceType]; for an
 * event's roster (in no service, null), every duty they link, by name.
 */
export function ledDuties(ministries: Ministry[], led: string[], serviceType: string | null) {
  return new Set(
    ministries
      .filter((m) => led.includes(m.id))
      .flatMap((m) => m.duties)
      .filter((d) => serviceType === null || d.service === serviceType)
      .map((d) => d.duty),
  );
}
