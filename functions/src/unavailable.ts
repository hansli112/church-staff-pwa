import { FieldValue } from 'firebase-admin/firestore';

import { churchAccess } from './access.js';
import { fail, record, type Caller, type Deps } from './common.js';
import { LIMITS, TEXT_LIMITS, withinTextLimit } from './limits.js';
import { ledDuties, ministriesOf, type Ministry } from './ministries.js';
import { powersOf, type MemberFields } from './powers.js';
import { notifyMembers, type PushDeps } from './push.js';

/** A member doc as askedToFill reads it: who, and the duties of each 牧區. */
interface Listed {
  uid: string;
  zones?: { serviceType?: unknown; duties?: unknown }[];
}

/**
 * Whom 請同工填 (#91) tells when [caller] asks for [serviceId]: everyone but
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
 * 請同工填不能服事的日子 (#91), by anyone who arranges service
 * `data.serviceId`: one push each to [askedToFill], asking for the months
 * `data.from` to `data.to` (`YYYY-MM`). Remembers when, for the next to
 * see. Returns how many people.
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
  await notifyMembers(deps, cid, asked, 'swap', (w) => ({
    title: church.get('name') as string,
    body: w.askUnavailable(from, to),
    link: '/me/unavailable',
  }));
  await deps.db.doc(`churches/${cid}/unavailableAsks/${serviceId}`).set({
    at: FieldValue.serverTimestamp(),
    by: member.id,
    from,
    to,
  });
  return { people: asked.length };
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
  await deps.db.doc(`churches/${cid}/unavailable/${c.uid}`).set({
    spans: kept.sort((a, b) => a.from.localeCompare(b.from)),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {};
}
