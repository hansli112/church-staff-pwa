import { FieldValue, Timestamp, type DocumentReference } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { fail, record, type Caller, type Deps } from './common.js';
import { LIMITS, TEXT_LIMITS, withinTextLimit } from './limits.js';
import { ledDuties, ministriesOf, type Ministry } from './ministries.js';
import { powersOf, type MemberFields } from './powers.js';
import { notifyMembers, type PushDeps } from './push.js';
import { dateKeyIn, timeZoneOf } from './timeZones.js';

/** A member doc as askedToFill reads it: who, and the duties of each 牧區. */
interface Listed {
  uid: string;
  zones?: { serviceType?: unknown; duties?: unknown }[];
}

/**
 * Whom 通知同工填 (#91) tells when [caller] asks for [serviceId]: everyone but
 * them on the list of a duty there they arrange
 * (testdata/church_rules.json, askedToFill).
 */
export function askedToFill(caller: MemberFields & { uid: string }, ministries: Ministry[], serviceId: string, members: Listed[]) {
  const powers = powersOf(caller);
  const led = ledDuties(ministries, powers.ministries, serviceId);
  const arranges = (duty: string) => powers.editsRosters(serviceId) || led.has(duty);
  return members
    .filter(
      (m) =>
        m.uid !== caller.uid &&
        (m.zones ?? []).some(
          (z) => z.serviceType === serviceId && Array.isArray(z.duties) && z.duties.some((d) => typeof d === 'string' && arranges(d)),
        ),
    )
    .map((m) => m.uid);
}

const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;

/**
 * 通知同工填不能服事的日子 (#91), by anyone who arranges service
 * `data.serviceId`: one push each to [askedToFill], asking for the months
 * `data.from` to `data.to` (`YYYY-MM`). Remembers when and whom, for the
 * next to see who has sent theirs; and tells each, in their own
 * unavailable/{uid} as `asked: {at, from, to}`, the months stretched over
 * any they were asked before and have not sent, from this month on. Writes
 * first, then pushes. Returns how many people.
 */
export async function askUnavailable(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  const { serviceId, from, to } = input;
  if (typeof serviceId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(serviceId)
      || typeof from !== 'string' || !MONTH.test(from) || typeof to !== 'string' || !MONTH.test(to) || to < from
      || Object.keys(input).some((k) => !['churchId', 'serviceId', 'from', 'to'].includes(k))) fail('invalid-argument', 'unknown');
  const { cid, church, member } = await churchAccess(deps, caller, data, { arranges: serviceId });
  const [ministries, members] = await Promise.all([
    deps.db.doc(`churches/${cid}/settings/ministries`).get(),
    deps.db.collection(`churches/${cid}/members`).get(),
  ]);
  const asked = askedToFill(
    { ...(member.data() as MemberFields), uid: member.id },
    ministriesOf(ministries),
    serviceId,
    members.docs.map((m) => ({ ...(m.data() as Listed), uid: m.id })),
  );
  const theirs = asked.length ? await deps.db.getAll(...asked.map((uid) => deps.db.doc(`churches/${cid}/unavailable/${uid}`))) : [];
  const thisMonth = dateKeyIn(timeZoneOf(church), deps.now()).slice(0, 7);
  const at = FieldValue.serverTimestamp();
  const writes: [DocumentReference, Record<string, unknown>][] = [
    [deps.db.doc(`churches/${cid}/unavailableAsks/${serviceId}`), { at, by: member.id, from, to, told: asked }],
  ];
  for (const doc of theirs) {
    const before = doc.get('asked') as { from?: unknown; to?: unknown } | undefined;
    const open = typeof before?.from === 'string' && typeof before.to === 'string' && before.to >= thisMonth
      && !sentSince(doc.get('sentAt'), doc.get('asked.at'));
    const months = open
      ? { from: [later(before.from as string, thisMonth), from].sort()[0], to: later(before.to as string, to) }
      : { from, to };
    writes.push([doc.ref, { asked: { at, ...months } }]);
  }
  // A batch takes 500 writes at most.
  for (let i = 0; i < writes.length; i += 400) {
    const batch = deps.db.batch();
    for (const [ref, value] of writes.slice(i, i + 400)) batch.set(ref, value, { merge: true });
    await batch.commit();
  }
  await notifyMembers(deps, cid, asked, 'swap', (w) => ({
    title: church.get('name') as string,
    body: w.askUnavailable(from, to),
    link: '/me/unavailable',
  }));
  return { people: asked.length };
}

/** The later of two `YYYY-MM` months. */
function later(a: string, b: string) {
  return a > b ? a : b;
}

/** Whether [at] (when sent, or when the days changed) is since [askedAt]. */
function sentSince(at: unknown, askedAt: unknown) {
  return at instanceof Timestamp && askedAt instanceof Timestamp
    && (at.seconds > askedAt.seconds || (at.seconds === askedAt.seconds && at.nanoseconds >= askedAt.nanoseconds));
}

/**
 * Whether [theirs] answered an ask made at [askedAt], as whoever asked sees
 * it: sent (送出, 都可以服事) or their days changed since, as Planning
 * Center counts its Last Set Blockouts (app: answeredAt).
 */
function answered(theirs: { get(field: string): unknown }, askedAt: unknown) {
  return sentSince(theirs.get('sentAt'), askedAt) || sentSince(theirs.get('updatedAt'), askedAt);
}

/**
 * 再通知 (#91): by anyone who arranges service `data.serviceId`, one push
 * again to each its last 通知同工填 told who is still in the church and has
 * not [answered] since. Returns how many people.
 */
export async function remindUnavailable(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  const { serviceId } = input;
  if (typeof serviceId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(serviceId)
      || Object.keys(input).some((k) => !['churchId', 'serviceId'].includes(k))) fail('invalid-argument', 'unknown');
  const { cid, church } = await churchAccess(deps, caller, data, { arranges: serviceId });
  const ask = await deps.db.doc(`churches/${cid}/unavailableAsks/${serviceId}`).get();
  const told = ask.get('told');
  if (!ask.exists || !Array.isArray(told)) fail('not-found', 'unknown');
  const uids = (told as unknown[]).filter((u): u is string => typeof u === 'string');
  const [members, theirs] = uids.length
    ? await Promise.all([
        deps.db.getAll(...uids.map((uid) => deps.db.doc(`churches/${cid}/members/${uid}`))),
        deps.db.getAll(...uids.map((uid) => deps.db.doc(`churches/${cid}/unavailable/${uid}`))),
      ])
    : [[], []];
  const waiting = uids.filter((_, i) => members[i].exists && !answered(theirs[i], ask.get('at')));
  const [from, to] = [ask.get('from') as string, ask.get('to') as string];
  await notifyMembers(deps, cid, waiting, 'swap', (w) => ({
    title: church.get('name') as string,
    body: w.askUnavailable(from, to),
    link: '/me/unavailable',
  }));
  return { people: waiting.length };
}

/**
 * 送出 or 都可以服事 (#91): the caller says their 不能服事的日子 are as they
 * are, answering what they were asked so far.
 */
export async function sendUnavailableDays(deps: Deps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => k !== 'churchId')) fail('invalid-argument', 'unknown');
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'member');
  await deps.db.doc(`churches/${cid}/unavailable/${c.uid}`).set({ sentAt: FieldValue.serverTimestamp() }, { merge: true });
  return {};
}

const DAY = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

/**
 * Keeps `data.spans` as the caller's 不能服事的日子 (#91): at most
 * LIMITS.unavailableSpans stretches, each `{from, to, note}` with `from`
 * no later than `to` and a note of at most TEXT_LIMITS.unavailableNote
 * characters. Through here, not the rules, which cannot look inside a list:
 * everyone who arranges reads them all.
 */
export async function saveUnavailableDays(deps: Deps, caller: Caller | null, data: unknown) {
  const input = record(data);
  const spans = input.spans;
  if (!Array.isArray(spans) || spans.length > LIMITS.unavailableSpans
      || Object.keys(input).some((k) => !['churchId', 'spans'].includes(k))) fail('invalid-argument', 'unknown');
  const kept = spans.map((s) => {
    const { from, to, note = '' } = record(s);
    if (typeof from !== 'string' || !DAY.test(from) || typeof to !== 'string' || !DAY.test(to) || to < from
        || typeof note !== 'string' || !withinTextLimit(note, TEXT_LIMITS.unavailableNote)
        || Object.keys(record(s)).some((k) => !['from', 'to', 'note'].includes(k))) fail('invalid-argument', 'unknown');
    return { from, to, note: note.trim() };
  });
  const { cid, caller: c } = await churchAccess(deps, caller, data, 'member');
  // Merged: what they were asked, and when they sent, stay.
  await deps.db.doc(`churches/${cid}/unavailable/${c.uid}`).set({
    spans: kept.sort((a, b) => a.from.localeCompare(b.from)),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return {};
}
