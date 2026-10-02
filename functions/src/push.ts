import type { Messaging } from 'firebase-admin/messaging';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';

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
}

const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/**
 * Sends [message] to every device of [uids] in church [cid], skipping
 * members who muted [kind] there. Tokens FCM reports as dead are removed
 * from users/{uid}.fcm. Returns how many devices it was sent to.
 */
export async function notifyMembers(
  deps: PushDeps,
  cid: string,
  uids: string[],
  kind: NotificationKind,
  message: PushMessage,
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
  const targets: { uid: string; device: string; token: string }[] = [];
  for (const u of users) {
    const fcm = (u.get('fcm') as Record<string, string> | undefined) ?? {};
    for (const [device, token] of Object.entries(fcm)) {
      if (typeof token === 'string' && token) targets.push({ uid: u.id, device, token });
    }
  }
  if (targets.length === 0) return 0;

  let sent = 0;
  for (let i = 0; i < targets.length; i += 500) {
    const batch = targets.slice(i, i + 500);
    const result = await deps.messaging.sendEachForMulticast({
      tokens: batch.map((t) => t.token),
      notification: { title: message.title, body: message.body },
      data: { cid, kind, link: message.link ?? '/home' },
      apns: { payload: { aps: { sound: 'default' } } },
      webpush: { fcmOptions: { link: message.link ?? '/home' } },
    });
    const dead: typeof batch = [];
    result.responses.forEach((r, j) => {
      if (r.success) sent++;
      else if (r.error && DEAD_TOKEN_CODES.has(r.error.code)) dead.push(batch[j]);
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
