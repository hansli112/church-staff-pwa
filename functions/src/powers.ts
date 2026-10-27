/**
 * What a member may do in their church (#82–#85), from the fields of their
 * member doc the security rules read (`role`, `groups`, `leadTypes`,
 * `leadMinistries`, `leadSmallGroups`, and the 身分 stored). The app's
 * Member answers the same questions: testdata/church_rules.json holds
 * both to every row. A callable asks [powersOf] its caller, never the
 * fields themselves.
 */

/** The member fields what they may do is worked out from. */
export interface MemberFields {
  role?: unknown;
  groups?: unknown;
  identities?: unknown;
  leadTypes?: unknown;
  leadMinistries?: unknown;
  leadSmallGroups?: unknown;
}

/**
 * A group of the church: a service, a 事工, or a 小組 (#85) with the
 * service it is in (null: none known, a 小組 gone).
 */
export type ChurchGroup =
  | { kind: 'service'; id: string }
  | { kind: 'ministry'; id: string }
  | { kind: 'small'; id: string; service: string | null };

const KEY = /^(service|ministry|small):([A-Za-z0-9_-]{1,64})$/;

/**
 * The group key [key] names, `service:<id>`, `ministry:<id>` or
 * `small:<id>` (an event's group, a 人數's), a 小組's in
 * [smallGroupService]; null for anything else, the church's ('') too.
 */
export function groupOf(key: unknown, smallGroupService: string | null = null): ChurchGroup | null {
  const m = typeof key === 'string' ? KEY.exec(key) : null;
  if (!m) return null;
  const [, kind, id] = m;
  return kind === 'small' ? { kind, id, service: smallGroupService } : { kind: kind as 'service' | 'ministry', id };
}

/** [value] as an event's group (#84): '' (the church's) or a group's key. */
export const isEventGroup = (value: unknown): value is string => value === '' || groupOf(value) !== null;

const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

export type Powers = ReturnType<typeof powersOf>;

export function powersOf(m: MemberFields) {
  const admin = m.role === 'admin';
  const groups = strings(m.groups);
  const services = strings(m.leadTypes);
  const ministries = strings(m.leadMinistries);
  const smallGroups = strings(m.leadSmallGroups);
  const stored = Array.isArray(m.identities) ? (m.identities as Record<string, unknown>[]) : [];
  /** Admin, or in permission group [g] (行政 is both). */
  const inGroup = (g: 'roster-editors' | 'calendar-editors') => admin || groups.includes(g);

  /** Whether they lead [g] itself: its 負責人 or 牧者, or a 小組's 小組長. */
  const leads = (g: ChurchGroup) =>
    g.kind === 'service' ? services.includes(g.id) : g.kind === 'ministry' ? ministries.includes(g.id) : smallGroups.includes(g.id);

  /** Whether they lead [g] or, for a 小組, the service it is in. */
  const manages = (g: ChurchGroup) => leads(g) || (g.kind === 'small' && g.service !== null && services.includes(g.service));

  /** Whether they write every event, whoever's: admins and calendar-editors (行政). */
  const writesAnyEvent = inGroup('calendar-editors');

  const self = {
    admin,
    inGroup,
    leads,
    manages,
    writesAnyEvent,
    /** The 事工 they lead. */
    ministries,

    /** A plain 同工: no admin, no permission group, no 身分 stored. */
    plain: !admin && groups.length === 0 && stored.length === 0,

    /** Whether they lead any group, and so may write that group's events. */
    leadsAnyGroup: services.length > 0 || ministries.length > 0 || smallGroups.length > 0,

    /** Whether they edit the rosters of service [type]: admins, 行政, and its 負責人 and 牧者. */
    editsRosters: (type: string) => inGroup('roster-editors') || services.includes(type),

    /**
     * Whether they may change an event of group [before] (null: none yet)
     * to group [after] (null: deleted) (eventWriting): admins and 行政 any;
     * a group's 負責人 only that group's events, never the church's.
     */
    mayWriteEvent(before: string | null, after: string | null) {
      if (writesAnyEvent) return true;
      const own = (key: string | null) => {
        const g = key === null ? null : groupOf(key);
        return key === null || (g !== null && leads(g));
      };
      return own(before) && own(after) && (before !== null || after !== null);
    },

    /**
     * Whether they may change a 小組 of service [before] (null: none yet)
     * to service [after] (null: closed) (smallGroupEditing): admins any; a
     * service's 負責人 and 牧者 those in it.
     */
    mayEditSmallGroup(before: string | null, after: string | null) {
      if (admin) return true;
      return (before !== null || after !== null) && [before, after].every((s) => s === null || services.includes(s));
    },

    /**
     * Whether they may add [target] to [group] or take them out
     * (groupMembership): an admin anyone; the group's 負責人 (a 小組's, its
     * service's too) only a plain 同工, since giving or taking a 身分 is the
     * admin's.
     */
    mayMove: (target: MemberFields, group: ChurchGroup) => admin || (manages(group) && powersOf(target).plain),

    /**
     * Whether they fill in the 人數 of [group] (attendanceAccess): admins
     * any; a service's 負責人 and 牧者 its own and its 小組'; a 小組長 their
     * 小組's.
     */
    writesAttendance: (group: ChurchGroup) => admin || (group.kind !== 'ministry' && manages(group)),

    /** Whether they see the 人數 of [group]: who fills them in, and 行政 a service's. */
    readsAttendance: (group: ChurchGroup) =>
      self.writesAttendance(group) || (group.kind === 'service' && groups.includes('roster-editors')),

    /**
     * Whether they are reminded of the 人數 of [group] (attendanceReminded):
     * a service's 負責人, by a `lead` 身分 of it (by `leadTypes` on a member
     * doc from before 身分), not its 牧者; a 小組's 小組長.
     */
    remindedOfAttendance(group: ChurchGroup) {
      if (group.kind === 'small') return smallGroups.includes(group.id);
      if (group.kind !== 'service') return false;
      if (stored.length === 0) return services.includes(group.id);
      return stored.some((i) => i?.kind === 'lead' && i?.service === group.id);
    },
  };
  return self;
}
