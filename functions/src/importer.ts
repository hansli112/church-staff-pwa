// Mapping self-host (church-staff-pwa) documents to one hosted church.
// Pure functions over plain objects, so they are tested without either
// database; scripts/import-selfhost.ts does the reading and writing.
//
// Self-host shapes (from its code, 2026-10):
//   users/{uid}               {name, email, username, role, groups[], zones[{serviceType, smallGroups[], ministries[]}]}
//   settings/services         {services[{id, label, name, weekday, enabled}], ids[]}
//   settings/roster_templates {[type]: [duty names]}
//   settings/event_options    {[type]: [{name, color: ARGB int}]}
//   rosters/{id}              {date: Timestamp, dateKey?, type, duties[{role, people[], personIdsByName{}}], specialEvents[], customEventColors{}}
//   staff_orders/{type}       {roles: {[duty]: [names]}}
//   settings/small_group_templates, devotional, …: not imported (v1 drops them)

export interface Report {
  members: number;
  rosters: number;
  services: number;
  skipped: string[];
}

const PLACEHOLDER = '待定';

/** Self-host ARGB colour → the hosted palette index (red, orange, yellow, green, blue, purple). */
export function paletteIndex(argb: unknown): number {
  if (typeof argb !== 'number') return 4;
  const r = ((argb >> 16) & 0xff) / 255;
  const g = ((argb >> 8) & 0xff) / 255;
  const b = (argb & 0xff) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  if (max - min < 0.08) return 4;
  let h: number;
  if (max === r) h = ((g - b) / (max - min)) % 6;
  else if (max === g) h = (b - r) / (max - min) + 2;
  else h = (r - g) / (max - min) + 4;
  const deg = (h * 60 + 360) % 360;
  if (deg < 15 || deg >= 330) return 0; // red, pink
  if (deg < 30) return 1; // orange
  if (deg < 70) return 2; // yellow, amber
  if (deg < 170) return 3; // green, teal
  if (deg < 250) return 4; // sky, blue, indigo
  return 5; // violet, purple
}

type Doc = Record<string, unknown>;

const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

export function mapMember(uid: string, u: Doc, joinedAt: unknown) {
  const zones = (Array.isArray(u.zones) ? u.zones : [])
    .filter((z): z is Doc => !!z && typeof z === 'object' && typeof (z as Doc).serviceType === 'string')
    .map((z) => ({ serviceType: z.serviceType as string, duties: strings(z.ministries) }));
  const role = ['admin', 'leader', 'staff', 'member'].includes(u.role as string) ? (u.role as string) : 'member';
  return {
    uid,
    name: typeof u.name === 'string' ? u.name.trim() : '',
    email: typeof u.email === 'string' ? u.email : '',
    role,
    groups: strings(u.groups).filter((g) => g === 'roster-editors' || g === 'calendar-editors'),
    zones,
    zoneTypes: [...new Set(zones.map((z) => z.serviceType))],
    joinedAt,
  };
}

export function mapServices(services: Doc | undefined, templates: Doc | undefined, eventOptions: Doc | undefined) {
  const list = (Array.isArray(services?.services) ? services!.services : []) as Doc[];
  const mapped = list
    .filter((s) => typeof s.id === 'string')
    .map((s) => {
      const id = s.id as string;
      return {
        id,
        name: typeof s.name === 'string' && s.name ? s.name : (s.label as string) ?? id,
        weekday: typeof s.weekday === 'number' ? s.weekday : 7,
        enabled: s.enabled !== false,
        duties: strings(templates?.[id]),
        events: (Array.isArray(eventOptions?.[id]) ? (eventOptions![id] as Doc[]) : [])
          .filter((e) => typeof e.name === 'string' && (e.name as string).trim())
          .map((e) => ({ name: (e.name as string).trim(), color: paletteIndex(e.color) })),
      };
    });
  const ids = [...new Set([...strings(services?.ids), ...mapped.map((s) => s.id)])];
  return { services: mapped, ids };
}

/** `YYYY-MM-DD` of a self-host roster: its dateKey, else its ID, else the date in UTC+8. */
export function rosterDateKey(id: string, r: Doc): string | null {
  if (typeof r.dateKey === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(r.dateKey)) return r.dateKey;
  const fromId = /^(\d{4})(\d{2})(\d{2})_/.exec(id);
  if (fromId) return `${fromId[1]}-${fromId[2]}-${fromId[3]}`;
  const date = r.date as { toDate?: () => Date } | undefined;
  if (date?.toDate) return new Date(date.toDate().getTime() + 8 * 3600e3).toISOString().slice(0, 10);
  return null;
}

export function mapRoster(id: string, r: Doc, eventColors: Map<string, number>) {
  const dateKey = rosterDateKey(id, r);
  const type = r.type;
  if (!dateKey || typeof type !== 'string' || !type) return null;
  const duties = (Array.isArray(r.duties) ? (r.duties as Doc[]) : [])
    .filter((d) => typeof d.role === 'string')
    .map((d) => {
      const people = strings(d.people).map((p) => p.trim()).filter((p) => p && p !== PLACEHOLDER);
      const ids = (d.personIdsByName ?? {}) as Record<string, unknown>;
      return {
        role: d.role as string,
        people,
        uids: Object.fromEntries(
          people.filter((p) => typeof ids[p] === 'string').map((p) => [p, ids[p] as string]),
        ),
      };
    });
  const custom = (r.customEventColors ?? {}) as Record<string, unknown>;
  const events = strings(r.specialEvents).map((name) => ({
    name,
    color: name in custom ? paletteIndex(custom[name]) : (eventColors.get(`${type}/${name}`) ?? 4),
  }));
  return { id: `${dateKey}_${type}`, data: { type, dateKey, duties, events } };
}

/** Names of self-host settings documents the hosted app has no place for. */
export const DROPPED_SETTINGS = ['small_group_templates', 'devotional', 'import_prompts'];

/**
 * Self-host deployments that never edited 聚會設定 have no
 * settings/services: the list was in the build config. Rebuild it from
 * what the data shows: every type with a template or a roster, named after
 * its rosters' serviceName, on the weekday most of its rosters fall on.
 */
export function inferServices(
  templates: Doc | undefined,
  eventOptions: Doc | undefined,
  rosters: { id: string; data: Doc }[],
) {
  const types = new Map<string, { names: Map<string, number>; weekdays: number[] }>();
  const add = (type: string) => types.get(type) ?? types.set(type, { names: new Map(), weekdays: [] }).get(type)!;
  for (const key of Object.keys(templates ?? {})) add(key);
  for (const r of rosters) {
    const type = r.data.type;
    if (typeof type !== 'string' || !type) continue;
    const t = add(type);
    const name = r.data.serviceName;
    if (typeof name === 'string' && name) t.names.set(name, (t.names.get(name) ?? 0) + 1);
    const key = rosterDateKey(r.id, r.data);
    if (key) t.weekdays.push(((new Date(`${key}T00:00:00Z`).getUTCDay() + 6) % 7) + 1);
  }
  const mostCommon = <T>(xs: T[]) => {
    const counts = new Map<T, number>();
    for (const x of xs) counts.set(x, (counts.get(x) ?? 0) + 1);
    return [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  };
  const list = [...types.entries()].map(([id, t]) => ({
    id,
    name: [...t.names.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? id,
    weekday: mostCommon(t.weekdays) ?? 7,
    enabled: true,
  }));
  return mapServices({ services: list, ids: list.map((s) => s.id) }, templates, eventOptions);
}
