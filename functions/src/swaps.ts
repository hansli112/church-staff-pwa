/**
 * 找人代 and 交換服事 a member asks for themselves (#92), on a day of a
 * service: churches/{cid}/swapRequests/{id}. 請人代 goes to everyone on the
 * duty's list who is free that day, and the first to say 我來 takes it; 交換
 * goes to one person on another day, who says 接受 or 不方便. Until then
 * who asked stays on the roster. Taken, the rosters change here (`via:
 * 'swap'`: the webhook hears, the two are told by these pushes), and the
 * service's leads hear who has it now (at 7:00, when it is night at the
 * church). app/lib/domain/swap.dart keeps the
 * same rules; both run testdata/swaps.json.
 */
import { FieldValue, Timestamp, type DocumentSnapshot, type Transaction } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { DAY_MS, fail, record, strings, type Caller, type Deps } from './common.js';
import type { Words } from './languages.js';
import { ledDuties, ministriesOf, type Ministry } from './ministries.js';
import { powersOf } from './powers.js';
import { notifyMembers, type PushDeps } from './push.js';
import { quietUntil } from './rosterChange.js';
import { duties as dutiesOf, names, serviceNames } from './rosters.js';
import { dateKeyIn, earliestDay, timeZoneOf, timeZonesAt } from './timeZones.js';

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

/** [uid]'s name on [duty] in [list], or null when they are not on it. */
export function nameOn(list: unknown, duty: string, uid: string) {
  const d = dutiesOf(list).find((x) => x.role === duty);
  return Object.entries(d?.uids ?? {}).find(([n, u]) => u === uid && names(d!.people).includes(n))?.[0] ?? null;
}

/** Whether [name] is already written on [duty] in [list], bound or not. */
const nameOnDuty = (list: unknown, duty: string, name: string) =>
  names(dutiesOf(list).find((x) => x.role === duty)?.people).includes(name);

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

/** Whether [spans] say [dateKey] cannot be served. */
const away = (spans: Spans | undefined, dateKey: string) => (spans ?? []).some((s) => s.from <= dateKey && dateKey <= s.to);

/**
 * Whom 請人代 asks for [from]'s [duty] on [dateKey] of [serviceId]
 * (testdata/swaps.json, coverAsked): everyone else on the duty's list who is
 * free that day, not on the duty already and not away, in [members]' order.
 */
export function coverAsked(members: Listed[], serviceId: string, dateKey: string, list: unknown, duty: string, from: string, unavailable: Record<string, Spans> = {}) {
  return members
    .filter(
      (m) =>
        m.uid !== from &&
        (m.zones ?? []).some((z) => z.serviceType === serviceId && strings(z.duties).includes(duty)) &&
        !onDuty(list, duty, m.uid) &&
        !away(unavailable[m.uid], dateKey),
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

const requests = (deps: Pick<Deps, 'db'>, cid: string) => deps.db.collection(`churches/${cid}/swapRequests`);

const rosterOf = (deps: Pick<Deps, 'db'>, cid: string, rosterId: string) => deps.db.doc(`churches/${cid}/rosters/${rosterId}`);

/** The input every ask names: the service, the day, the duty. */
function dayOf(input: Record<string, unknown>) {
  const { serviceId, dateKey, duty } = input;
  if (typeof serviceId !== 'string' || !ID.test(serviceId) || typeof dateKey !== 'string' || !DAY.test(dateKey)
      || typeof duty !== 'string' || duty.length === 0 || duty.length > 200) fail('invalid-argument', 'unknown');
  return { serviceId, dateKey, duty };
}

/** A request as it reads in a push: its service and duty ([Words.dutyLine]), and its days. */
async function readable(deps: Pick<Deps, 'db'>, cid: string, r: FirebaseFirestore.DocumentData) {
  const service = (await serviceNames(deps, cid))(r.serviceId);
  return (w: Words) => ({
    line: w.dutyLine(service, [r.duty]),
    day: w.dateWithWeekday(r.dateKey),
    toDay: r.toDateKey ? w.dateWithWeekday(r.toDateKey) : '',
  });
}

/** The leads of [serviceId]'s [duty] in church [cid] now ([leadsOf]). */
async function leadsFor(deps: Pick<Deps, 'db'>, cid: string, serviceId: string, duty: string) {
  const [members, ministries] = await Promise.all([
    deps.db.collection(`churches/${cid}/members`).get(),
    deps.db.doc(`churches/${cid}/settings/ministries`).get(),
  ]);
  return leadsOf(members.docs, ministriesOf(ministries), serviceId, duty);
}

/**
 * In [tx], [roster]'s [duty] with [b] where [a] was, and for 交換 [other]'s
 * with [a] where [b] was.
 */
function trade(
  tx: Transaction,
  duty: string,
  roster: DocumentSnapshot,
  other: DocumentSnapshot | null,
  a: { uid: string; name: string },
  b: { uid: string; name: string },
) {
  const write = (d: DocumentSnapshot, from: typeof a, to: typeof a) =>
    tx.update(d.ref, {
      duties: replacedOnDuty(d.get('duties'), duty, from.uid, to.uid, to.name),
      via: 'swap',
      updatedAt: FieldValue.serverTimestamp(),
    });
  write(roster, a, b);
  if (other) write(other, b, a);
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

/**
 * The push asking for [request]: to everyone 請人代 asked who has not said
 * 不方便, or 交換's one person.
 */
async function sendRequest(deps: PushDeps, church: DocumentSnapshot, request: DocumentSnapshot) {
  const r = request.data()!;
  const say = await readable(deps, church.id, r);
  const link = `/rosters/request/${request.id}`;
  const title = church.get('name') as string;
  if (r.kind === 'cover') {
    const passed = strings(r.passed);
    return notifyMembers(deps, church.id, strings(r.asked).filter((u) => !passed.includes(u)), 'swap', (w) => ({
      title,
      body: w.coverAsked(r.fromName, say(w).day, say(w).line),
      link,
    }));
  }
  return notifyMembers(deps, church.id, [r.to], 'swap', (w) => ({
    title,
    body: w.swapAsked(r.fromName, say(w).day, say(w).toDay, say(w).line),
    link,
  }));
}

/**
 * Who asks, and their roster that day, still to come with them on it; and
 * [create] keeping the request, refused while one of theirs for the same
 * duty that day is open.
 */
async function asker(deps: Deps, caller: Caller | null, data: unknown) {
  const input = record(data);
  const day = dayOf(input);
  const a = await churchAccess(deps, caller, data, 'member');
  const today = dateKeyIn(timeZoneOf(a.church), deps.now());
  if (day.dateKey < today) fail('failed-precondition', 'unknown');
  const roster = await rosterOf(deps, a.cid, `${day.dateKey}_${day.serviceId}`).get();
  const name = nameOn(roster.get('duties'), day.duty, a.caller.uid);
  if (name === null) fail('failed-precondition', 'unknown');
  const create = async (fields: Record<string, unknown>) => {
    const ref = requests(deps, a.cid).doc();
    await deps.db.runTransaction(async (tx) => {
      const open = await tx.get(requests(deps, a.cid).where('from', '==', a.caller.uid).where('status', '==', 'open'));
      if (open.docs.some((d) => d.get('rosterId') === roster.id && d.get('duty') === day.duty)) fail('already-exists', 'unknown');
      tx.set(ref, {
        serviceId: day.serviceId,
        dateKey: day.dateKey,
        rosterId: roster.id,
        duty: day.duty,
        from: a.caller.uid,
        fromName: name,
        status: 'open',
        sendAt: null,
        createdAt: FieldValue.serverTimestamp(),
        ...fields,
      });
    });
    return ref;
  };
  return { ...a, ...day, input, roster, today, create };
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
  const [members, unavailable] = await Promise.all([
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
    Object.fromEntries(unavailable.docs.map((d) => [d.id, d.get('spans') as Spans | undefined ?? []])),
  );
  if (asked.length === 0) fail('failed-precondition', 'unknown', 'nobodyToAsk');
  const ref = await a.create({ kind: 'cover', asked, passed: [], nudged: false });
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
  const [other, them] = await Promise.all([
    rosterOf(deps, a.cid, `${withDateKey}_${a.serviceId}`).get(),
    deps.db.doc(`churches/${a.cid}/members/${to}`).get(),
  ]);
  if (!stillHolds('swap', a.duty, a.caller.uid, to, a.roster.get('duties'), other.get('duties'))) fail('failed-precondition', 'unknown');
  // One of the 同工 without an account could never answer.
  if (!them.exists) fail('not-found', 'notFound');
  const ref = await a.create({
    kind: 'swap',
    to,
    toName: nameOn(other.get('duties'), a.duty, to),
    toDateKey: withDateKey,
    toRosterId: other.id,
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

/** Tells the leads [request] was taken, its own [ref] remembering they were told. */
async function tellLeads(deps: PushDeps, church: DocumentSnapshot, ref: FirebaseFirestore.DocumentReference, r: FirebaseFirestore.DocumentData) {
  await ref.update({ leadsAt: null, leadsTold: true });
  const say = await readable(deps, church.id, r);
  const leads = (await leadsFor(deps, church.id, r.serviceId, r.duty)).filter((u) => u !== r.from && u !== r.taker);
  return notifyMembers(deps, church.id, leads, 'swap', (w) => ({
    title: church.get('name') as string,
    body: r.kind === 'cover'
      ? w.covered(say(w).day, say(w).line, r.fromName, r.takerName)
      : w.swapped(say(w).line, r.fromName, say(w).day, r.takerName, say(w).toDay),
    link: `/rosters/${r.serviceId}/${r.dateKey}`,
  }));
}

/**
 * Answers request `data.id`: `data.yes` takes it (我來, 接受), changing the
 * rosters, and tells who asked, and the leads (at 7:00 when it is night);
 * otherwise 不方便, which for 交換 tells who asked and closes it, and for
 * 請人代 only leaves it to the others. Fails when it is no longer open or no
 * longer holds (the roster changed: it is void), when the caller was not
 * asked, or for 請人代 is no longer on the duty's list, marked the day as one
 * they cannot serve, or is on it already.
 */
export async function answerSwap(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (typeof input.yes !== 'boolean' || Object.keys(input).some((k) => !['churchId', 'id', 'yes'].includes(k))) fail('invalid-argument', 'unknown');
  const a = await churchAccess(deps, caller, data, 'member');
  const me = a.caller.uid;
  const today = dateKeyIn(timeZoneOf(a.church), deps.now());
  const done = await deps.db.runTransaction(async (tx) => {
    const r = await requestIn(tx, deps, a.cid, input);
    const req = r.data()!;
    const asked = req.kind === 'cover' ? strings(req.asked).includes(me) : req.to === me;
    if (!asked) fail('permission-denied', 'permissionDenied');
    if (req.status !== 'open') fail('failed-precondition', 'unknown', 'swapClosed');
    if (!input.yes) {
      tx.update(r.ref, req.kind === 'cover' ? { passed: FieldValue.arrayUnion(me) } : { status: 'declined', answeredAt: Timestamp.fromDate(deps.now()) });
      return { req, took: false, leadsNow: false, ref: r.ref };
    }
    const roster = await tx.get(rosterOf(deps, a.cid, req.rosterId));
    const other = req.kind === 'swap' ? await tx.get(rosterOf(deps, a.cid, req.toRosterId)) : null;
    const [member, unavailable] = req.kind === 'cover'
      ? await Promise.all([tx.get(a.member.ref), tx.get(deps.db.doc(`churches/${a.cid}/unavailable/${me}`))])
      : [null, null];
    const late = req.dateKey < today || (req.kind === 'swap' && req.toDateKey < today);
    if (late || !stillHolds(req.kind, req.duty, req.from, req.kind === 'swap' ? req.to : null, roster.get('duties'), other?.get('duties'))) {
      tx.update(r.ref, { status: 'voided' });
      return null;
    }
    const takerName = req.kind === 'cover' ? ((member!.get('name') as string | undefined) ?? '') : req.toName;
    if (req.kind === 'cover') {
      const listed = ((member!.get('zones') as Listed['zones']) ?? []).some((z) => z.serviceType === req.serviceId && strings(z.duties).includes(req.duty));
      if (!listed || away(unavailable!.get('spans') as Spans | undefined, req.dateKey) || !takerName
          || onDuty(roster.get('duties'), req.duty, me) || nameOnDuty(roster.get('duties'), req.duty, takerName)) {
        fail('failed-precondition', 'unknown');
      }
    }
    trade(tx, req.duty, roster, other, { uid: req.from, name: req.fromName }, { uid: me, name: takerName });
    const until = quietUntil(timeZoneOf(a.church), deps.now());
    tx.update(r.ref, {
      status: 'taken',
      taker: me,
      takerName,
      answeredAt: Timestamp.fromDate(deps.now()),
      leadsAt: until ? Timestamp.fromDate(until) : null,
      leadsTold: false,
    });
    return { req: { ...req, taker: me, takerName } as FirebaseFirestore.DocumentData, took: true, leadsNow: !until, ref: r.ref };
  });
  if (!done) fail('failed-precondition', 'unknown', 'swapClosed');
  const req = done.req;
  const say = await readable(deps, a.cid, req);
  const title = a.church.get('name') as string;
  if (done.took) {
    await notifyMembers(deps, a.cid, [req.from], 'swap', (w) => ({
      title,
      body: req.kind === 'cover'
        ? w.coverTaken(req.takerName, say(w).day, say(w).line)
        : w.swapTaken(req.takerName, say(w).toDay, say(w).line),
      link: `/rosters/${req.serviceId}/${req.kind === 'swap' ? req.toDateKey : req.dateKey}`,
    }));
    if (done.leadsNow) await tellLeads(deps, a.church, done.ref!, req);
  } else if (req.kind === 'swap') {
    await notifyMembers(deps, a.cid, [req.from], 'swap', (w) => ({
      title,
      body: w.swapDeclined(req.toName, say(w).day, say(w).line),
      link: `/rosters/${req.serviceId}/${req.dateKey}`,
    }));
  }
  return {};
}

/**
 * 復原 of taking request `data.id`, by whoever took it, within [UNDO_MS]
 * and while the rosters are still as it left them: they go back. 請人代 is
 * open again and asks the others once more; 交換 ends as if they had said
 * 不方便. Who asked hears so, and the leads when they had heard it was
 * taken.
 */
export async function undoSwap(deps: Deps & PushDeps, caller: Caller | null, data: unknown) {
  const input = record(data);
  if (Object.keys(input).some((k) => !['churchId', 'id'].includes(k))) fail('invalid-argument', 'unknown');
  const a = await churchAccess(deps, caller, data, 'member');
  const me = a.caller.uid;
  const { req, ref } = await deps.db.runTransaction(async (tx) => {
    const r = await requestIn(tx, deps, a.cid, input);
    const req = r.data()!;
    if (req.taker !== me) fail('permission-denied', 'permissionDenied');
    const at = (req.answeredAt as Timestamp | undefined)?.toMillis() ?? 0;
    if (req.status !== 'taken' || deps.now().getTime() - at > UNDO_MS) fail('failed-precondition', 'unknown', 'swapClosed');
    const roster = await tx.get(rosterOf(deps, a.cid, req.rosterId));
    const other = req.kind === 'swap' ? await tx.get(rosterOf(deps, a.cid, req.toRosterId)) : null;
    // As taking left them: the taker where who asked was, and for 交換 who
    // asked on the other day.
    const asLeft = req.kind === 'cover'
      ? onDuty(roster.get('duties'), req.duty, me) && !onDuty(roster.get('duties'), req.duty, req.from)
      : stillHolds('swap', req.duty, me, req.from, roster.get('duties'), other?.get('duties'));
    if (!asLeft) fail('failed-precondition', 'conflict');
    trade(tx, req.duty, roster, other, { uid: me, name: req.takerName }, { uid: req.from, name: req.fromName });
    const gone = { taker: FieldValue.delete(), takerName: FieldValue.delete(), leadsAt: FieldValue.delete(), leadsTold: FieldValue.delete() };
    tx.update(r.ref, req.kind === 'cover'
      ? { ...gone, status: 'open', answeredAt: FieldValue.delete(), passed: FieldValue.arrayUnion(me) }
      : { ...gone, status: 'declined', answeredAt: Timestamp.fromDate(deps.now()) });
    return { req, ref: r.ref };
  });
  const say = await readable(deps, a.cid, req);
  const title = a.church.get('name') as string;
  const back = (w: Words) =>
    req.kind === 'cover' ? w.takenBack(req.takerName, say(w).day, say(w).line) : w.swapUndone(req.takerName, say(w).day, say(w).line);
  await notifyMembers(deps, a.cid, [req.from], 'swap', (w) => ({ title, body: back(w), link: `/rosters/${req.serviceId}/${req.dateKey}` }));
  if (req.leadsTold) {
    const leads = (await leadsFor(deps, a.cid, req.serviceId, req.duty)).filter((u) => u !== req.from && u !== me);
    await notifyMembers(deps, a.cid, leads, 'swap', (w) => ({ title, body: back(w), link: `/rosters/${req.serviceId}/${req.dateKey}` }));
  }
  if (req.kind === 'cover') await sendRequest(deps, a.church, await ref.get());
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
 * (who asked is off it, or the one asked off theirs) are void, each read
 * again with the rosters in a transaction, so one taken meanwhile stays
 * taken. Returns how many.
 */
export async function voidStaleSwaps(deps: Pick<Deps, 'db'>, cid: string, rosterId: string) {
  const col = requests(deps, cid);
  const [mine, theirs] = await Promise.all([
    col.where('rosterId', '==', rosterId).where('status', '==', 'open').get(),
    col.where('toRosterId', '==', rosterId).where('status', '==', 'open').get(),
  ]);
  let voided = 0;
  for (const found of [...mine.docs, ...theirs.docs]) {
    voided += await deps.db.runTransaction(async (tx) => {
      const r = await tx.get(found.ref);
      const req = r.data();
      if (req?.status !== 'open') return 0;
      const roster = await tx.get(rosterOf(deps, cid, req.rosterId));
      const other = req.toRosterId ? await tx.get(rosterOf(deps, cid, req.toRosterId)) : null;
      if (stillHolds(req.kind, req.duty, req.from, req.to ?? null, roster.get('duties'), other?.get('duties'))) return 0;
      tx.update(r.ref, { status: 'voided' });
      return 1;
    });
  }
  return voided;
}

/**
 * Every hour: requests asked in the night go out once morning comes, and
 * so do the leads' news of one taken in the night; open ones whose day has
 * gone by everywhere are void; and at [NUDGE_HOUR] on a church's clock, a
 * 請人代 nobody took [NUDGE_DAYS] days before its day is told to the leads,
 * once.
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
  const leads = await deps.db.collectionGroup('swapRequests').where('leadsAt', '<=', Timestamp.fromDate(now)).get();
  for (const r of leads.docs) {
    if (r.get('status') === 'taken') told += await tellLeads(deps, await churchOf(r), r.ref, r.data());
    else await r.ref.update({ leadsAt: null });
  }
  const past = await deps.db.collectionGroup('swapRequests').where('status', '==', 'open').where('dateKey', '<', earliestDay(now)).get();
  for (const r of past.docs) await r.ref.update({ status: 'voided' });

  const zones = timeZonesAt([NUDGE_HOUR], now);
  if (zones.size === 0) return told;
  const inThreeDays = (z: string) => dateKeyIn(z, new Date(now.getTime() + NUDGE_DAYS * DAY_MS));
  for (const day of new Set([...zones].map(inThreeDays))) {
    const open = await deps.db.collectionGroup('swapRequests').where('status', '==', 'open').where('dateKey', '==', day).get();
    for (const r of open.docs) {
      const req = r.data();
      if (req.kind !== 'cover' || req.nudged) continue;
      const church = await churchOf(r);
      const zone = timeZoneOf(church);
      if (!zones.has(zone) || inThreeDays(zone) !== day) continue;
      await r.ref.update({ nudged: true });
      const say = await readable(deps, church.id, req);
      told += await notifyMembers(deps, church.id, (await leadsFor(deps, church.id, req.serviceId, req.duty)).filter((u) => u !== req.from), 'swap', (w) => ({
        title: church.get('name') as string,
        body: w.uncovered(say(w).day, say(w).line),
        link: `/rosters/${req.serviceId}/${req.dateKey}`,
      }));
    }
  }
  return told;
}
