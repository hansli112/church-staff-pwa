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

import { words, type Language } from './languages.js';
import { personName } from './limits.js';

/**
 * A duty nobody has yet, written in its people: self-host's 待定 (it spoke
 * only Chinese), whatever the language of whoever moves it, and their own
 * language's word for it.
 */
export const placeholders = (language: Language) =>
  new Set([words('zh-Hant').placeholder, words(language).placeholder]);

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
    .map((z) => ({ serviceType: z.serviceType as string, duties: strings(z.ministries), smallGroups: strings(z.smallGroups) }));
  const prefs = u.notificationPrefs as { weeklyRosterReminder?: unknown; muted?: unknown } | undefined;
  const muted = [...new Set([...strings(prefs?.muted), ...(prefs?.weeklyRosterReminder === false ? ['reminder'] : [])])];
  const role = ['admin', 'leader', 'staff', 'member'].includes(u.role as string) ? (u.role as string) : 'member';
  return {
    uid,
    name: personName(u.name),
    email: typeof u.email === 'string' ? u.email : '',
    role,
    groups: strings(u.groups).filter((g) => g === 'roster-editors' || g === 'calendar-editors'),
    zones,
    zoneTypes: [...new Set(zones.map((z) => z.serviceType))],
    notificationPrefs: { muted },
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

/** Migration boundary only: full source names, with duplicates excluded, never normalized or truncated. */
export function exactUidIndex(people: readonly { uid: string; name: unknown }[]) {
  const unique = new Map<string, string>();
  const ambiguous = new Set<string>();
  for (const person of people) {
    const name = person.name;
    if (typeof name !== 'string' || !name.trim() || !person.uid || person.uid.includes('/') || ambiguous.has(name)) continue;
    if (unique.has(name)) {
      unique.delete(name);
      ambiguous.add(name);
    } else unique.set(name, person.uid);
  }
  return { unique, ambiguous };
}

export function mapRoster(
  id: string,
  r: Doc,
  eventColors: Map<string, number>,
  exactUids: ReadonlyMap<string, string> = new Map(),
  nobody: ReadonlySet<string> = placeholders('zh-Hant'),
) {
  const dateKey = rosterDateKey(id, r);
  const type = r.type;
  if (!dateKey || typeof type !== 'string' || !type) return null;
  const duties = (Array.isArray(r.duties) ? (r.duties as Doc[]) : [])
    .filter((d) => typeof d.role === 'string')
    .map((d) => {
      const listed = strings(d.people).map((raw) => ({ raw, name: raw.trim() })).filter((p) => p.name && !nobody.has(p.name));
      const supplied = Object.hasOwn(d, 'personIdsByName');
      const ids = d.personIdsByName && typeof d.personIdsByName === 'object' && !Array.isArray(d.personIdsByName)
        ? d.personIdsByName as Record<string, unknown> : {};
      return {
        role: d.role as string,
        people: listed.map((p) => p.name),
        uids: Object.fromEntries(listed.flatMap((p) => {
          // Even an explicitly empty or partial map is authoritative. Only
          // missing legacy maps may infer a unique exact original full name.
          const uid = supplied ? ids[Object.hasOwn(ids, p.raw) ? p.raw : p.name] : exactUids.get(p.raw);
          return typeof uid === 'string' && uid && !uid.includes('/') ? [[p.name, uid]] : [];
        })),
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
 * In the build config's own order (主日, 青崇, 兒主), then the rest as found:
 * the database lists them alphabetically.
 */
const SELF_HOST_SERVICES = ['sundayService', 'youth', 'children'];

export function inferServices(
  templates: Doc | undefined,
  eventOptions: Doc | undefined,
  rosters: { id: string; data: Doc }[],
) {
  const types = new Map<string, { names: Map<string, number>; weekdays: number[] }>();
  const known = new Set([...Object.keys(templates ?? {}), ...rosters.map((r) => r.data.type)]);
  for (const id of SELF_HOST_SERVICES) if (known.has(id)) types.set(id, { names: new Map(), weekdays: [] });
  const add =(type: string) => types.get(type) ?? types.set(type, { names: new Map(), weekdays: [] }).get(type)!;
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

/** One document of the self-host project, as read. */
export interface SourceDoc {
  id: string;
  data: Doc;
}

/** Everything read from a self-host project. */
export interface SelfHostSnapshot {
  users: SourceDoc[];
  settings: SourceDoc[];
  rosters: SourceDoc[];
  staffOrders: SourceDoc[];
}

/** What an import leaves out or could not read, for the operator or the uploader. */
export interface ImportReport {
  members: number;
  admins: number;
  services: string[];
  rosters: number;
  /** Self-host roster IDs with no readable date or type. */
  skippedRosters: string[];
  staffOrders: number;
  /** settings/* documents the hosted app has no place for. */
  droppedSettings: string[];
  /** People whose per-zone small-group data is preserved. */
  smallGroupPeople: number;
  unnamedMembers: number;
}

/**
 * The hosted church's documents built from a self-host snapshot: members,
 * services, rosters and staff orders, plus a report. Shared by the
 * operator's import script and self-serve moving. [language] is the
 * mover's, for the word they write for nobody yet.
 */
export function buildImport(snapshot: SelfHostSnapshot, joinedAt: unknown, language: Language = 'zh-Hant') {
  const nobody = placeholders(language);
  const settingsById = new Map(snapshot.settings.map((d) => [d.id, d.data]));
  const services = settingsById.has('services')
    ? mapServices(settingsById.get('services'), settingsById.get('roster_templates'), settingsById.get('event_options'))
    : inferServices(settingsById.get('roster_templates'), settingsById.get('event_options'), snapshot.rosters);
  const eventColors = new Map<string, number>();
  for (const s of services.services) for (const e of s.events) eventColors.set(`${s.id}/${e.name}`, e.color);

  const members = snapshot.users.map((u) => mapMember(u.id, u.data, joinedAt));
  const { unique: exactUids } = exactUidIndex(snapshot.users.map((u) => ({ uid: u.id, name: u.data.name })));
  const rosters: NonNullable<ReturnType<typeof mapRoster>>[] = [];
  const skippedRosters: string[] = [];
  for (const r of snapshot.rosters) {
    const mapped = mapRoster(r.id, r.data, eventColors, exactUids, nobody);
    if (mapped) rosters.push(mapped);
    else skippedRosters.push(r.id);
  }
  const staffOrders = snapshot.staffOrders.map((o) => ({
    id: o.id,
    roles: (o.data.roles ?? {}) as Record<string, unknown>,
  }));
  const droppedSettings = [...settingsById.keys()].filter(
    (id) => DROPPED_SETTINGS.includes(id) || !['services', 'roster_templates', 'event_options'].includes(id),
  );
  const smallGroupPeople = snapshot.users.filter((u) =>
    ((u.data.zones as { smallGroups?: unknown[] }[] | undefined) ?? []).some(
      (z) => Array.isArray(z?.smallGroups) && z.smallGroups.length > 0,
    ),
  ).length;
  const report: ImportReport = {
    members: members.length,
    admins: members.filter((m) => m.role === 'admin').length,
    services: services.services.map((s) => s.id),
    rosters: rosters.length,
    skippedRosters,
    staffOrders: staffOrders.length,
    droppedSettings,
    smallGroupPeople,
    unnamedMembers: members.filter((m) => !m.name).length,
  };
  return { members, services, rosters, staffOrders, report };
}
