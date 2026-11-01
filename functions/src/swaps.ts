/**
 * 找人代 and 交換服事 a member asks for themselves (#92), on a day of a
 * service: churches/{cid}/swapRequests/{id}. 請人代 goes to everyone on the
 * duty's list who is free that day, and the first to say 我來 takes it; 交換
 * goes to one person on another day, who says 接受 or 不方便. Until then
 * who asked stays on the roster. Taken, the rosters change here (`via:
 * 'swap'`: the webhook hears, the two are told by these pushes), and the
 * service's leads hear who has it now. app/lib/domain/swap.dart keeps the
 * same rules; both run testdata/swaps.json.
 */
import { FieldValue, Timestamp, type DocumentSnapshot, type Transaction } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { DAY_MS, fail, record, strings, type Caller, type Deps } from './common.js';
import { ledDuties, ministriesOf, type Ministry } from './ministries.js';
import { powersOf } from './powers.js';
import { notifyMembers, type PushDeps } from './push.js';
import { quietUntil } from './rosterChange.js';
import { duties as dutiesOf, names, serviceNames } from './rosters.js';
import { dateKeyIn, earliestDay, timeZoneOf, timeZonesAt } from './timeZones.js';
import type { Words } from './languages.js';

export type SwapKind = 'cover' | 'swap';
export type SwapStatus = 'open' | 'taken' | 'declined' | 'withdrawn' | 'voided';

/** How long after taking it 復原 still gives it back. */
export const UNDO_MS = 10 * 60e3;

/** The evening, on each church's clock, the leads hear of a cover nobody took. */
export const NUDGE_HOUR = 19;

/** How many days before the day a cover nobody took is told to the leads. */
export const NUDGE_DAYS = 3;

const ID = /^[A-Za-z0-9_-]{1,64}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;

/** Whether [uid] is on [duty] in [list]: bound by uid, and the name still there. */
export function onDuty(list: unknown, duty: string, uid: string) {
  const d = dutiesOf(list).find((x) => x.role === duty);
  return !!d && Object.entries(d.uids ?? {}).some(([name, u]) => u === uid && names(d.people).includes(name));
}

/** [list] with [uid] named [name] on [duty] where [replaced] was. */
export function replacedOnDuty(list: unknown, duty: string, replaced: string, uid: string, name: string) {
  return dutiesOf(list).map((d) => {
    if (d.role !== duty) return d;
    const old = Object.entries(d.uids ?? {}).find(([n, u]) => u === replaced && names(d.people).includes(n))?.[0];
    if (old === undefined) return d;
    const uids = Object.fromEntries(Object.entries(d.uids ?? {}).filter(([n]) => n !== old));
    return { ...d, people: names(d.people).map((p) => (p === old ? name : p)), uids: { ...uids, [name]: uid } };
  });
}

interface Listed {
  uid: string;
  zones?: { serviceType?: unknown; duties?: unknown }[];
}

/** Spans of 不能服事的日子 (#91), as unavailable/{uid} keeps them. */
type Spans = { from: string; to: string }[];

/**
 * Whom 請人代 asks for [from]'s [duty] on [dateKey] of [serviceId]
 * (testdata/swaps.json, coverAsked): everyone else on the duty's list who is
 * free that day, not on the duty already and not away, in [members]' order.
 */
export function coverAsked(members: Listed[], serviceId: string, dateKey: string, list: unknown, duty: string, from: string, away: Record<string, Spans> = {}) {
  return members
    .filter(
      (m) =>
        m.uid !== from &&
        (m.zones ?? []).some((z) => z.serviceType === serviceId && strings(z.duties).includes(duty)) &&
        !onDuty(list, duty, m.uid) &&
        !(away[m.uid] ?? []).some((s) => s.from <= dateKey && dateKey <= s.to),
    )
    .map((m) => m.uid);
}

/**
 * Whether a request can still be taken (testdata/swaps.json, stillHolds):
 * who asked is on the duty on their day, and for 交換 the one asked is on it
 * on theirs, with neither on the other's day already.
 */
export function stillHolds(kind: SwapKind, duty: string, from: string, to: string | null, list: unknown, other: unknown) {
  if (!onDuty(list, duty, from)) return false;
  if (kind === 'cover') return true;
  return !!to && onDuty(other, duty, to) && !onDuty(list, duty, to) && !onDuty(other, duty, from);
}

/**
 * Who hears a request taken, or a cover nobody took: the service's 負責人
 * and 牧者 (`leadTypes`), and the 負責人 of a 事工 that links the duty;
 * with none, 行政 and the admins.
 */
export function leadsOf(members: DocumentSnapshot[], ministries: Ministry[], serviceId: string, duty: string) {
  const leads = members.filter((m) => {
    const p = powersOf(m.data() ?? {});
    return strings(m.get('leadTypes')).includes(serviceId) || ledDuties(ministries, p.ministries, serviceId).has(duty);
  });
  const who = leads.length > 0 ? leads : members.filter((m) => powersOf(m.data() ?? {}).inGroup('roster-editors'));
  return who.map((m) => m.id);
}

const rosterRef = (deps: Pick<Deps, 'db'>, cid: string, serviceId: string, dateKey: string) =>
  deps.db.doc(`churches/${cid}/rosters/${dateKey}_${serviceId}`);

const requests = (deps: Pick<Deps, 'db'>, cid: string) => deps.db.collection(`churches/${cid}/swapRequests`);

/** The input every ask names: the service, the day, the duty. */
function dayOf(input: Record<string, unknown>) {
  const { serviceId, dateKey, duty } = input;
  if (typeof serviceId !== 'string' || !ID.test(serviceId) || typeof dateKey !== 'string' || !DAY.test(dateKey)
      || typeof duty !== 'string' || duty.length === 0 || duty.length > 200) fail('invalid-argument', 'unknown');
  return { serviceId, dateKey, duty };
}

/** A line of the request for a push: the service's name and the duty. */
async function lineOf(deps: Pick<Deps, 'db'>, cid: string, serviceId: string) {
  return (await serviceNames(deps, cid))(serviceId);
}

/** Fails unless no request of [uid]'s for this duty on this day is still open. */
async function noOpenRequest(deps: Pick<Deps, 'db'>, cid: string, uid: string, rosterId: string, duty: string) {
  const open = await requests(deps, cid).where('from', '==', uid).where('status', '==', 'open').get();
  if (open.docs.some((d) => d.get('rosterId') === rosterId && d.get('duty') === duty)) fail('already-exists', 'unknown');
}

/** Pushes a new request now, or at 7:00 when it is night at the church. */
async function sendOrHold(deps: Deps & PushDeps, church: DocumentSnapshot, ref: FirebaseFirestore.DocumentReference) {
  const until = quietUntil(timeZoneOf(church), deps.now());
  if (until) {
    await ref.update({ sendAt: Timestamp.fromDate(until) });
    return 0;
  }
  return sendRequest(deps, church, await ref.get());
}

/** The push asking for [request]: to everyone asked still on the list, or the one person. */
async function sendRequest(deps: PushDeps, church: DocumentSnapshot, request: DocumentSnapshot) {
  const r = request.data()!;
  const cid = church.id;
  const line = await lineOf(deps, cid, r.serviceId);
  const link = `/rosters/request/${request.id}`;
  if (r.kind === 'cover') {
    return notifyMembers(deps, cid, strings(r.asked), 'swap', (w) => ({
      title: church.get('name') as string,
      body: w.coverAsked(r.fromName, w.dateWithWeekday(r.dateKey), w.dutyLine(line, [r.duty])),
      link,
    }));
  }
  return notifyMembers(deps, cid, [r.to], 'swap', (w) => ({
    title: church.get('name') as string,
    body: w.swapAsked(r.fromName, w.dateWithWeekday(r.dateKey), w.dateWithWeekday(r.toDateKey), w.dutyLine(line, [r.duty])),
    link,
  }));
}

/** Who asks, their roster that day, and whether the day is still to come. */
async function asker(deps: Deps, caller: Caller | null, data: unknown) {
  const input = record(data);
  const day = dayOf(input);
  const a = await churchAccess(deps, caller, data, 'member');
  const today = dateKeyIn(timeZoneOf(a.church), deps.now());
  if (day.dateKey < today) fail('failed-precondition', 'unknown');
  const roster = await rosterRef(deps, a.cid, day.serviceId, day.dateKey).get();
  if (!onDuty(roster.get('duties'), day.duty, a.caller.uid)) fail('failed-precondition', 'unknown');
  await noOpenRequest(deps, a.cid, a.caller.uid, roster.id, day.duty);
  const name = Object.entries(dutiesOf(roster.get('duties')).find((d) => d.role === day.duty)!.uids ?? {}).find(([, u]) => u === a.caller.uid)![0];
  return { ...a, ...day, input, roster, name, today };
}

/**
 * 請人代 (#92): `data` names the service, the day and the duty of the
 * caller's. Asks everyone on the duty's list free that day ([coverAsked]),
 * at once or at 7:00 after a night. Returns how many; none asked fails
 * (detail `nobodyToAsk`), and nothing is kept.
 */
export async function askCover(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const a = await asker(deps, caller, data);
  if (Object.keys(a.input).some((k) => !['churchId', 'serviceId', 'dateKey', 'duty'].includes(k))) fail('invalid-argument', 'unknown');
  const [members, away] = await Promise.all([
    deps.db.collection(`churches/${a.cid}/members`).get(),
    deps.db.collection(`churches/${a.cid}/unavailable`).get(),
  ]);
  const asked = coverAsked(
    members.docs.map((m) => ({ ...(m.data() as Listed), uid: m.id })),
    a.serviceId,
    a.dateKey,
    a.roster.get('duties'),
    a.duty,
    a.caller.uid,
    Object.fromEntries(away.docs.map((d) => [d.id, (d.get('spans') as Spans | undefined) ?? []])),
  );
  if (asked.length === 0) fail('failed-precondition', 'unknown', 'nobodyToAsk');
  const ref = requests(deps, a.cid).doc();
  await ref.set({
    kind: 'cover',
    serviceId: a.serviceId,
    dateKey: a.dateKey,
    rosterId: a.roster.id,
    duty: a.duty,
    from: a.caller.uid,
    fromName: a.name,
    asked,
    passed: [],
    status: 'open',
    sendAt: null,
    nudged: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  await sendOrHold(deps, a.church, ref);
  return { id: ref.id, asked: asked.length };
}

/**
 * 和別週交換 (#92): the caller's duty on `data`'s day, for `data.with`'s
 * on `data.withDateKey` of the same service, from tomorrow on. Asks that
 * one person, at once or at 7:00 after a night.
 */
export async function askSwap(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const a = await asker(deps, caller, data);
  const { with: to, withDateKey } = a.input;
  if (typeof to !== 'string' || !ID.test(to) || typeof withDateKey !== 'string' || !DAY.test(withDateKey)
      || withDateKey === a.dateKey || withDateKey <= a.today
      || Object.keys(a.input).some((k) => !['churchId', 'serviceId', 'dateKey', 'duty', 'with', 'withDateKey'].includes(k))) {
    fail('invalid-argument', 'unknown');
  }
  const other = await rosterRef(deps, a.cid, a.serviceId, withDateKey).get();
  if (!stillHolds('swap', a.duty, a.caller.uid, to, a.roster.get('duties'), other.get('duties'))) fail('failed-precondition', 'unknown');
  const toName = Object.entries(dutiesOf(other.get('duties')).find((d) => d.role === a.duty)!.uids ?? {}).find(([, u]) => u === to)![0];
  const ref = requests(deps, a.cid).doc();
  await ref.set({
    kind: 'swap',
    serviceId: a.serviceId,
    dateKey: a.dateKey,
    rosterId: a.roster.id,
    duty: a.duty,
    from: a.caller.uid,
    fromName: a.name,
    to,
    toName,
    toDateKey: withDateKey,
    toRosterId: other.id,
    status: 'open',
    sendAt: null,
    createdAt: FieldValue.serverTimestamp(),
  });
  await sendOrHold(deps, a.church, ref);
  return { id: ref.id };
}

/** Request `data.id` of the church `data.churchId`, read in [tx]; fails when there is none. */
async function requestIn(tx: Transaction, deps: Deps, cid: string, data: Record<string, unknown>) {
  if (typeof data.id !== 'string' || !ID.test(data.id)) fail('invalid-argument', 'unknown');
  const r = await tx.get(requests(deps, cid).doc(data.id));
  if (!r.exists) fail('not-found', 'notFound');
  return r;
}

/** Tells who asked and the leads what became of [request], [taker] having taken or given it back. */
async function tellTaken(deps: PushDeps, church: DocumentSnapshot, r: FirebaseFirestore.DocumentData, taker: string, takerName: string, back: boolean) {
  const cid = church.id;
  const title = church.get('name') as string;
  const line = await lineOf(deps, cid, r.serviceId);
  const [members, ministries] = await Promise.all([
    deps.db.collection(`churches/${cid}/members`).get(),
    deps.db.doc(`churches/${cid}/settings/ministries`).get(),
  ]);
  const leads = leadsOf(members.docs, ministriesOf(ministries), r.serviceId, r.duty).filter((u) => u !== r.from && u !== taker);
  const say = (w: Words) => w.dutyLine(line, [r.duty]);
  await notifyMembers(deps, cid, [r.from], 'swap', (w) => ({
    title,
    body: back
      ? w.takenBack(takerName, w.dateWithWeekday(r.dateKey), say(w))
      : r.kind === 'cover'
        ? w.coverTaken(takerName, w.dateWithWeekday(r.dateKey), say(w))
        : w.swapTaken(takerName, w.dateWithWeekday(r.toDateKey), say(w)),
    link: `/rosters/${r.serviceId}/${r.kind === 'swap' ? r.toDateKey : r.dateKey}`,
  }));
  await notifyMembers(deps, cid, leads, 'swap', (w) => ({
    title,
    body: back
      ? w.takenBack(takerName, w.dateWithWeekday(r.dateKey), say(w))
      : r.kind === 'cover'
        ? w.covered(w.dateWithWeekday(r.dateKey), say(w), r.fromName, takerName)
        : w.swapped(say(w), r.fromName, w.dateWithWeekday(r.dateKey), takerName, w.dateWithWeekday(r.toDateKey)),
    link: `/rosters/${r.serviceId}/${r.dateKey}`,
  }));
}

/**
 * Answers request `data.id`: `data.yes` takes it (我來, 接受), changing the
 * rosters, and tells who asked and the leads; otherwise 不方便, which for
 * 交換 tells who asked and closes it, and for 請人代 only leaves it to the
 * others. Fails when it is no longer open or no longer holds (the roster
 * changed: it is void), or the caller was not asked.
 */
export async function answerSwap(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (typeof input.yes !== 'boolean' || Object.keys(input).some((k) => !['churchId', 'id', 'yes'].includes(k))) fail('invalid-argument', 'unknown');
  const a = await churchAccess(deps, caller, data, 'member');
  const me = a.caller.uid;
  const myName = (a.member.get('name') as string | undefined) ?? '';
  const today = dateKeyIn(timeZoneOf(a.church), deps.now());
  const done = await deps.db.runTransaction(async (tx) => {
    const r = await requestIn(tx, deps, a.cid, input);
    const req = r.data()!;
    const asked = req.kind === 'cover' ? strings(req.asked).includes(me) : req.to === me;
    if (!asked) fail('permission-denied', 'permissionDenied');
    if (req.status !== 'open') fail('failed-precondition', 'unknown', 'swapClosed');
    if (!input.yes) {
      tx.update(r.ref, req.kind === 'cover' ? { passed: FieldValue.arrayUnion(me) } : { status: 'declined', answeredAt: Timestamp.fromDate(deps.now()) });
      return { req, took: false };
    }
    const roster = await tx.get(deps.db.doc(`churches/${a.cid}/rosters/${req.rosterId}`));
    const other = req.kind === 'swap' ? await tx.get(deps.db.doc(`churches/${a.cid}/rosters/${req.toRosterId}`)) : null;
    const late = req.dateKey < today || (req.kind === 'swap' && req.toDateKey < today);
    if (late || !stillHolds(req.kind, req.duty, req.from, req.kind === 'swap' ? req.to : null, roster.get('duties'), other?.get('duties'))) {
      tx.update(r.ref, { status: 'voided' });
      return null;
    }
    if (req.kind === 'cover' && onDuty(roster.get('duties'), req.duty, me)) fail('failed-precondition', 'unknown');
    const taker = req.kind === 'cover' ? myName : req.toName;
    tx.update(roster.ref, {
      duties: replacedOnDuty(roster.get('duties'), req.duty, req.from, me, taker),
      via: 'swap',
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (other) {
      tx.update(other.ref, {
        duties: replacedOnDuty(other.get('duties'), req.duty, me, req.from, req.fromName),
        via: 'swap',
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.update(r.ref, { status: 'taken', taker: me, takerName: taker, answeredAt: Timestamp.fromDate(deps.now()) });
    return { req, took: true, takerName: taker };
  });
  if (!done) fail('failed-precondition', 'unknown', 'swapClosed');
  if (done.took) {
    await tellTaken(deps, a.church, done.req, me, done.takerName!, false);
  } else if (done.req.kind === 'swap') {
    const line = await lineOf(deps, a.cid, done.req.serviceId);
    await notifyMembers(deps, a.cid, [done.req.from], 'swap', (w) => ({
      title: a.church.get('name') as string,
      body: w.swapDeclined(done.req.toName, w.dateWithWeekday(done.req.dateKey), w.dutyLine(line, [done.req.duty])),
      link: `/rosters/${done.req.serviceId}/${done.req.dateKey}`,
    }));
  }
  return {};
}

/**
 * 復原 of taking request `data.id`, by whoever took it, within [UNDO_MS]
 * and while the rosters are still as it left them: they go back, the
 * request is open again, and who asked and the leads hear so.
 */
export async function undoSwap(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'id'].includes(k))) fail('invalid-argument', 'unknown');
  const a = await churchAccess(deps, caller, data, 'member');
  const me = a.caller.uid;
  const req = await deps.db.runTransaction(async (tx) => {
    const r = await requestIn(tx, deps, a.cid, input);
    const req = r.data()!;
    if (req.taker !== me) fail('permission-denied', 'permissionDenied');
    const at = (req.answeredAt as Timestamp | undefined)?.toMillis() ?? 0;
    if (req.status !== 'taken' || deps.now().getTime() - at > UNDO_MS) fail('failed-precondition', 'unknown', 'swapClosed');
    const roster = await tx.get(deps.db.doc(`churches/${a.cid}/rosters/${req.rosterId}`));
    const other = req.kind === 'swap' ? await tx.get(deps.db.doc(`churches/${a.cid}/rosters/${req.toRosterId}`)) : null;
    // As taking left them: the taker where who asked was, and for 交換 who
    // asked on the other day.
    const asLeft = req.kind === 'cover'
      ? onDuty(roster.get('duties'), req.duty, me) && !onDuty(roster.get('duties'), req.duty, req.from)
      : stillHolds('swap', req.duty, me, req.from, roster.get('duties'), other?.get('duties'));
    if (!asLeft) fail('failed-precondition', 'conflict');
    tx.update(roster.ref, {
      duties: replacedOnDuty(roster.get('duties'), req.duty, me, req.from, req.fromName),
      via: 'swap',
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (other) {
      tx.update(other.ref, {
        duties: replacedOnDuty(other.get('duties'), req.duty, req.from, me, req.toName),
        via: 'swap',
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.update(r.ref, { status: 'open', taker: FieldValue.delete(), takerName: FieldValue.delete(), answeredAt: FieldValue.delete() });
    return req;
  });
  await tellTaken(deps, a.church, req, me, req.takerName, true);
  return {};
}

/** 收回: who asked takes back their open request `data.id`. */
export async function withdrawSwap(deps: Deps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'id'].includes(k))) fail('invalid-argument', 'unknown');
  const a = await churchAccess(deps, caller, data, 'member');
  await deps.db.runTransaction(async (tx) => {
    const r = await requestIn(tx, deps, a.cid, input);
    if (r.get('from') !== a.caller.uid) fail('permission-denied', 'permissionDenied');
    if (r.get('status') !== 'open') fail('failed-precondition', 'unknown', 'swapClosed');
    tx.update(r.ref, { status: 'withdrawn' });
  });
  return {};
}

/**
 * A roster of church [cid] written: its open requests that no longer hold
 * (who asked is off it, or the one asked off theirs) are void. Returns how
 * many.
 */
export async function voidStaleSwaps(deps: Pick<Deps, 'db'>, cid: string, rosterId: string) {
  const col = requests(deps, cid);
  const [mine, theirs] = await Promise.all([
    col.where('rosterId', '==', rosterId).where('status', '==', 'open').get(),
    col.where('toRosterId', '==', rosterId).where('status', '==', 'open').get(),
  ]);
  let voided = 0;
  for (const r of [...mine.docs, ...theirs.docs]) {
    const req = r.data();
    const [roster, other] = await Promise.all([
      deps.db.doc(`churches/${cid}/rosters/${req.rosterId}`).get(),
      req.toRosterId ? deps.db.doc(`churches/${cid}/rosters/${req.toRosterId}`).get() : Promise.resolve(null),
    ]);
    if (stillHolds(req.kind, req.duty, req.from, req.to ?? null, roster.get('duties'), other?.get('duties'))) continue;
    await r.ref.update({ status: 'voided' });
    voided++;
  }
  return voided;
}

/**
 * Every hour: requests asked in the night go out once morning comes; open
 * ones whose day has gone by everywhere are void; and at [NUDGE_HOUR] on a
 * church's clock, a 請人代 nobody took [NUDGE_DAYS] days before its day is
 * told to the leads, once.
 */
export async function sendSwapPushes(deps: PushDeps & Pick<Deps, 'now'>) {
  const now = deps.now();
  const churches = new Map<string, DocumentSnapshot>();
  const churchOf = async (d: DocumentSnapshot) => {
    const cid = d.ref.parent.parent!.id;
    if (!churches.has(cid)) churches.set(cid, await deps.db.doc(`churches/${cid}`).get());
    return churches.get(cid)!;
  };
  let told = 0;
  const due = await deps.db.collectionGroup('swapRequests').where('sendAt', '<=', Timestamp.fromDate(now)).get();
  for (const r of due.docs) {
    await r.ref.update({ sendAt: null });
    if (r.get('status') === 'open') told += await sendRequest(deps, await churchOf(r), r);
  }
  const past = await deps.db.collectionGroup('swapRequests').where('status', '==', 'open').where('dateKey', '<', earliestDay(now)).get();
  for (const r of past.docs) await r.ref.update({ status: 'voided' });

  const zones = timeZonesAt([NUDGE_HOUR], now);
  if (zones.size === 0) return told;
  const days = new Set([...zones].map((z) => dateKeyIn(z, new Date(now.getTime() + NUDGE_DAYS * DAY_MS))));
  for (const day of days) {
    const open = await deps.db.collectionGroup('swapRequests').where('status', '==', 'open').where('dateKey', '==', day).get();
    for (const r of open.docs) {
      const req = r.data();
      if (req.kind !== 'cover' || req.nudged) continue;
      const church = await churchOf(r);
      if (!zones.has(timeZoneOf(church)) || dateKeyIn(timeZoneOf(church), new Date(now.getTime() + NUDGE_DAYS * DAY_MS)) !== day) continue;
      await r.ref.update({ nudged: true });
      const [members, ministries] = await Promise.all([
        deps.db.collection(`churches/${church.id}/members`).get(),
        deps.db.doc(`churches/${church.id}/settings/ministries`).get(),
      ]);
      const line = await lineOf(deps, church.id, req.serviceId);
      told += await notifyMembers(deps, church.id, leadsOf(members.docs, ministriesOf(ministries), req.serviceId, req.duty).filter((u) => u !== req.from), 'swap', (w) => ({
        title: church.get('name') as string,
        body: w.uncovered(w.dateWithWeekday(req.dateKey), w.dutyLine(line, [req.duty])),
        link: `/rosters/${req.serviceId}/${req.dateKey}`,
      }));
    }
  }
  return told;
}

