import type { Messaging } from 'firebase-admin/messaging';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';

import { notificationsOf, unreadOf } from './notificationList.js';
import { languageOf, words, type Language, type Words } from './languages.js';

/** Matches NotificationKind in app/lib/domain/models.dart and firestore.rules (test/parity.test.ts). */
export const NOTIFICATION_KINDS = ['reminder', 'rosterChange', 'memberLeft', 'attendance', 'joinRequest', 'identity'] as const;
export type NotificationKind = (typeof NOTIFICATION_KINDS)[number];

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
 * Sends [message] to every device of [uids] in church [cid], written with
 * [Words] in each one's language (users/{uid}.appLocale), and keeps it in
 * their 通知列表 (#89). Members who muted [kind] there get it in the list
 * only. The app icon shows what is unread in all their churches. Tokens FCM
 * reports as dead are removed from users/{uid}.fcm. Returns how many devices
 * it was sent to.
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
  const members = memberDocs.filter((m) => m.exists);
  if (members.length === 0) return 0;
  const muted = new Set(
    members
      .filter((m) => ((m.get('notificationPrefs.muted') as string[] | undefined) ?? []).includes(kind))
      .map((m) => m.id),
  );
  const users = await db.getAll(...members.map((m) => db.doc(`users/${m.id}`)));
  const texts = new Map<Language, Required<PushMessage>>();
  const textIn = (language: Language) => {
    if (!texts.has(language)) {
      const m = message(words(language));
      texts.set(language, { ...m, link: m.link ?? '/home' });
    }
    return texts.get(language)!;
  };

  // In the lists first, so the app icon's number counts this one.
  for (let i = 0; i < users.length; i += 500) {
    const batch = db.batch();
    for (const u of users.slice(i, i + 500)) {
      const { title, body, link } = textIn(languageOf(u.get('appLocale')));
      batch.create(notificationsOf(db, u.id).doc(), {
        cid,
        kind,
        title,
        body,
        link,
        at: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // A send each for the people of one language and one number.
  const groups = new Map<string, { language: Language; badge: number; targets: Target[] }>();
  await Promise.all(
    users
      .filter((u) => !muted.has(u.id))
      .map(async (u) => {
        const fcm = (u.get('fcm') as Record<string, string> | undefined) ?? {};
        const targets = Object.entries(fcm)
          .filter(([, token]) => typeof token === 'string' && token)
          .map(([device, token]) => ({ uid: u.id, device, token }));
        if (targets.length === 0) return;
        const language = languageOf(u.get('appLocale'));
        const badge = await unreadOf(db, u.id, u.get('notificationsSeenAt'));
        const key = `${language} ${badge}`;
        const group = groups.get(key) ?? { language, badge, targets: [] };
        group.targets.push(...targets);
        groups.set(key, group);
      }),
  );
  let sent = 0;
  for (const { language, badge, targets } of groups.values()) {
    sent += await send(deps, cid, kind, textIn(language), badge, targets);
  }
  return sent;
}

/**
 * Sends [message] to [targets], 500 at a time, with [badge] on the app
 * icon, dropping the tokens FCM says are dead.
 */
async function send(
  deps: PushDeps,
  cid: string,
  kind: NotificationKind,
  message: Required<PushMessage>,
  badge: number,
  targets: Target[],
) {
  const { db } = deps;
  // Through the church URL, which switches to this church first: someone in
  // two churches lands on the right one.
  const link = `/c/${cid}?to=${encodeURIComponent(message.link)}`;
  let sent = 0;
  for (let i = 0; i < targets.length; i += 500) {
    const batch = targets.slice(i, i + 500);
    const result = await deps.messaging.sendEachForMulticast({
      tokens: batch.map((t) => t.token),
      notification: { title: message.title, body: message.body },
      // The web's service worker puts badge on the icon itself. Android's
      // launchers count the notifications showing, so none for them: theirs
      // add up across notifications.
      data: { cid, kind, link, badge: String(badge) },
      apns: { payload: { aps: { sound: 'default', badge } } },
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
