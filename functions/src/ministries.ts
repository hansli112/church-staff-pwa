import type { DocumentSnapshot } from 'firebase-admin/firestore';

/**
 * 事工 (#82): settings/ministries. A team with its 負責人 and its own
 * events on the calendar (`ministry:<id>`), at no fixed time; it links no
 * duties (2026-11-26: a 服事項目's 負責人 is held on the duty itself,
 * `leadDuties`). Ministries saved before then may still carry `duties`;
 * nothing reads them.
 */
export interface Ministry {
  id: string;
  name: string;
}

/** The 事工 in settings/ministries as it is now (deleted ones are gone; their IDs stay in `ids`). */
export function ministriesOf(settings: DocumentSnapshot): Ministry[] {
  const list = settings.get('ministries');
  return (Array.isArray(list) ? list : []).filter(
    (m): m is Ministry => typeof m?.id === 'string' && typeof m?.name === 'string',
  );
}
