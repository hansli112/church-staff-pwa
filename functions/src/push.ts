import type { Messaging } from 'firebase-admin/messaging';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';

import { languageOf, words, type Language, type Words } from './languages.js';

/** Matches NotificationKind in app/lib/domain/models.dart. */
export type NotificationKind = 'reminder' | 'rosterChange' | 'memberLeft';

export interface PushMessage {
  title: string;
  body: string;
  /** App route to open, e.g. `/rosters`. */
  link?: string;
}

export interface PushDeps {
  db: Firestore;
  messaging: Pick<Messaging, 'sendEachForMulticast'>;
  /** The hosted web app, for the link a web notification opens. */
  appUrl: string;
}

/** One device of one member. */
interface Target {
  uid: string;
  device: string;
  token: string;
}

const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

// FCM answers a garbled token with invalid-argument, but also a bad
// message, which every token gets. So it means a dead device only when
// another token in the same send went through.
const INVALID_ARGUMENT = 'messaging/invalid-argument';

/**
 * Sends [message] to every device of [uids] in church [cid], skipping
 * members who muted [kind] there, written with [Words] in each one's
 * language (users/{uid}.appLocale). Tokens FCM reports as dead are removed
 * from users/{uid}.fcm. Returns how many devices it was sent to.
 */
export async function notifyMembers(
  deps: PushDeps,
  cid: string,
  uids: string[],
  kind: NotificationKind,
  message: (w: Words) => PushMessage,
): Promise<number> {
  const { db } = deps;
  const unique = [...new Set(uids)];
  if (unique.length === 0) return 0;
  const memberDocs = await db.getAll(
    ...unique.map((uid) => db.doc(`churches/${cid}/members/${uid}`)),
  );
  const wanted = memberDocs
    .filter((m) => m.exists)
    .filter((m) => {
      const muted = (m.get('notificationPrefs.muted') as string[] | undefined) ?? [];
      return !muted.includes(kind);
    })
    .map((m) => m.id);
  if (wanted.length === 0) return 0;

  const users = await db.getAll(...wanted.map((uid) => db.doc(`users/${uid}`)));
  const byLanguage = new Map<Language, Target[]>();
  for (const u of users) {
    const fcm = (u.get('fcm') as Record<string, string> | undefined) ?? {};
    const language = languageOf(u.get('appLocale'));
    for (const [device, token] of Object.entries(fcm)) {
      if (typeof token !== 'string' || !token) continue;
      byLanguage.set(language, [...(byLanguage.get(language) ?? []), { uid: u.id, device, token }]);
    }
  }
  let sent = 0;
  for (const [language, targets] of byLanguage) {
    sent += await send(deps, cid, kind, message(words(language)), targets);
  }
  return sent;
}

/** Sends [message] to [targets], 500 at a time, dropping the tokens FCM says are dead. */
async function send(
  deps: PushDeps,
  cid: string,
  kind: NotificationKind,
  message: PushMessage,
  targets: Target[],
) {
  const { db } = deps;
  // Through the church URL, which switches to this church first: someone in
  // two churches lands on the right one.
  const link = `/c/${cid}?to=${encodeURIComponent(message.link ?? '/home')}`;
  let sent = 0;
  for (let i = 0; i < targets.length; i += 500) {
    const batch = targets.slice(i, i + 500);
    const result = await deps.messaging.sendEachForMulticast({
      tokens: batch.map((t) => t.token),
      notification: { title: message.title, body: message.body },
      data: { cid, kind, link },
      apns: { payload: { aps: { sound: 'default' } } },
      // FCM documents this link as HTTPS only, so not a bare route.
      webpush: { fcmOptions: { link: `${deps.appUrl}${link}` } },
    });
    const anySent = result.responses.some((r) => r.success);
    const dead: typeof batch = [];
    result.responses.forEach((r, j) => {
      const code = r.error?.code ?? '';
      if (r.success) sent++;
      else if (DEAD_TOKEN_CODES.has(code) || (anySent && code === INVALID_ARGUMENT)) dead.push(batch[j]);
    });
    await Promise.all(
      dead.map((t) =>
        db.doc(`users/${t.uid}`).update({ [`fcm.${t.device}`]: FieldValue.delete() }),
      ),
    );
  }
  return sent;
}

/** uids of the church's admins. */
export async function adminUids(db: Firestore, cid: string): Promise<string[]> {
  const admins = await db.collection(`churches/${cid}/members`).where('role', '==', 'admin').get();
  return admins.docs.map((d) => d.id);
}
