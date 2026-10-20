/**
 * Whose a calendar event is (#84): the whole church's, or one group's, a
 * service's or a 事工's. Kept in Google with the event (a private extended
 * property), so it survives being edited in Google Calendar; an event
 * made there is the church's. `''` is the church's, `service:<id>` and
 * `ministry:<id>` a group's.
 */

const GROUP = /^(service|ministry):[A-Za-z0-9_-]{1,64}$/;

/** [value] as an event's group: '' (the church's) or a group of either kind. */
export const isEventGroup = (value: unknown): value is string =>
  typeof value === 'string' && (value === '' || GROUP.test(value));

const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

/** The member fields who may write what reads. */
interface Fields {
  role?: unknown;
  groups?: unknown;
  leadTypes?: unknown;
  leadMinistries?: unknown;
}

/** Whether [m] leads [group]. The church's ('') nobody leads. */
export function leadsEventGroup(m: Fields, group: string) {
  const [kind, id] = group.split(':');
  if (kind === 'service') return strings(m.leadTypes).includes(id);
  if (kind === 'ministry') return strings(m.leadMinistries).includes(id);
  return false;
}

/**
 * Whether [m] may change an event of group [before] (null: none yet) to
 * group [after] (null: deleted) (testdata/church_rules.json,
 * eventWriting): admins and calendar-editors (行政) any; a group's 負責人
 * only that group's events, never the church's.
 */
export function mayWriteEvent(m: Fields, before: string | null, after: string | null) {
  if (m.role === 'admin' || strings(m.groups).includes('calendar-editors')) return true;
  return [before, after].every((g) => g === null || leadsEventGroup(m, g)) && (before !== null || after !== null);
}
