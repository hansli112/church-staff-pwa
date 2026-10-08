import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

import { deleteAccount } from '../src/account.js';
import type { CalDeps, GoogleApi } from '../src/calendar.js';
import { previewInvite, redeemInvite } from '../src/invites.js';
import { notifyMembers } from '../src/push.js';
import { seal } from '../src/sealing.js';
import {
  editorOf,
  onLogoUploaded,
  onMemberDeleted,
  onMemberLeft,
  onMemberUpdated,
  syncProfileName,
} from '../src/triggers.js';
import { auth, caller, clearFirestore, db, deps, rejectsWith, seedChurch, setNow } from './support.js';

const appUrl = 'https://app.example';

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-01T10:00:00+08:00'));
});

async function invite(code: string, cid: string, opts: { expiresAt?: Date; revoked?: boolean } = {}) {
  await db.doc(`invites/${code}`).set({
    cid,
    churchName: cid,
    expiresAt: Timestamp.fromDate(opts.expiresAt ?? new Date('2026-10-08T00:00:00Z')),
    revoked: opts.revoked ?? false,
  });
}

describe('invites', () => {
  test('redeeming adds a staff member with the profile name', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await invite('JOINME2026', 'C1');
    await db.doc('users/newbie').set({ name: '新同工' });

    const preview = await previewInvite(deps, caller('newbie'), { code: 'joinme2026' });
    assert.equal(preview.churchName, 'C1');
    const { churchId } = await redeemInvite(deps, caller('newbie'), { code: 'JOINME2026' });

    assert.equal(churchId, 'C1');
    const member = await db.doc('churches/C1/members/newbie').get();
    assert.equal(member.get('role'), 'staff');
    assert.equal(member.get('name'), '新同工');
    assert.equal(member.get('uid'), 'newbie');
  });

  test('previews an invite before sign-in, so the login page can name the church', async () => {
    await seedChurch('C1', {});
    await invite('JOINME2026', 'C1');
    const preview = await previewInvite(deps, null, { code: 'JOINME2026' });
    assert.deepEqual(preview, { churchName: 'C1' }, 'signed out: only the name');
  });

  test('redeeming twice keeps one member doc and does not reset the role', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'leader' });
    await invite('JOINME2026', 'C1');
    await redeemInvite(deps, caller('bob'), { code: 'JOINME2026' });
    assert.equal((await db.doc('churches/C1/members/bob').get()).get('role'), 'leader');
    assert.equal((await db.collection('churches/C1/members').get()).size, 2);
  });

  test('expired, revoked and unknown invites are rejected with a reason', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await invite('EXPIRED00', 'C1', { expiresAt: new Date('2026-09-30T00:00:00Z') });
    await invite('REVOKED00', 'C1', { revoked: true });
    await rejectsWith(redeemInvite(deps, caller('x'), { code: 'EXPIRED00' }), 'inviteExpired');
    await rejectsWith(redeemInvite(deps, caller('x'), { code: 'REVOKED00' }), 'inviteInvalid');
    await rejectsWith(redeemInvite(deps, caller('x'), { code: 'NOSUCH000' }), 'inviteInvalid');
    await rejectsWith(redeemInvite(deps, caller('x'), { code: '../../x' }), 'inviteInvalid');
    assert.equal((await db.doc('churches/C1/members/x').get()).exists, false);
  });

  test('an invite to a suspended church does not work', async () => {
    await seedChurch('C1', { alice: 'admin' }, { status: 'suspended' });
    await invite('JOINME2026', 'C1');
    await rejectsWith(redeemInvite(deps, caller('x'), { code: 'JOINME2026' }), 'inviteInvalid');
  });

  test('requires sign-in', async () => {
    await rejectsWith(redeemInvite(deps, null, { code: 'JOINME2026' }), 'permissionDenied');
  });
});

describe('deleteAccount', () => {
  test('removes every membership, the profile and the Auth user', async () => {
    const user = await auth.createUser({ email: 'leaver@example.com', password: 'secret123' });
    const uid = user.uid;
    await seedChurch('C1', { alice: 'admin', [uid]: 'staff' });
    await seedChurch('C2', { bob: 'admin', [uid]: 'admin' });
    await db.doc(`users/${uid}`).set({ name: '要走的人' });
    await db.doc('churches/C1/rosters/r1').set({
      type: 'sunday',
      dateKey: '2026-10-04',
      duties: [{ role: '司琴', people: ['要走的人'], uids: { 要走的人: uid } }],
    });

    await deleteAccount({ ...deps, auth }, caller(uid));

    assert.equal((await db.doc(`churches/C1/members/${uid}`).get()).exists, false);
    assert.equal((await db.doc(`churches/C2/members/${uid}`).get()).exists, false);
    assert.equal((await db.doc(`users/${uid}`).get()).exists, false);
    await assert.rejects(auth.getUser(uid));
    const roster = await db.doc('churches/C1/rosters/r1').get();
    assert.deepEqual(roster.get('duties')[0].people, ['要走的人'], 'names on rosters stay');
  });

  test('the only admin of a church is told which church to hand over', async () => {
    await seedChurch('Solo', { alice: 'admin', bob: 'staff' });
    await seedChurch('Shared', { alice: 'admin', carol: 'admin' });
    const err = await rejectsWith(deleteAccount({ ...deps, auth }, caller('alice')), 'lastAdmin');
    assert.deepEqual((err as { details: { detail: string[] } }).details.detail, ['Solo']);
    assert.ok((await db.doc('churches/Solo/members/alice').get()).exists);
    assert.ok((await db.doc('churches/Shared/members/alice').get()).exists);
  });

  test('being the only admin of a deleted church does not block', async () => {
    const user = await auth.createUser({ email: 'gone@example.com' });
    await seedChurch('Gone', { [user.uid]: 'admin' }, { status: 'deleted' });
    await deleteAccount({ ...deps, auth }, caller(user.uid));
    assert.equal((await db.doc(`churches/Gone/members/${user.uid}`).get()).exists, false);
  });
});

describe('triggers', () => {
  test('a new profile name is copied to every membership', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await seedChurch('C2', { alice: 'staff', bob: 'admin' });
    const before = await db.doc('users/alice').get();
    await db.doc('users/alice').set({ name: '新名字' });
    const after = await db.doc('users/alice').get();

    assert.equal(await syncProfileName(deps, 'alice', before, after), 2);
    assert.equal((await db.doc('churches/C1/members/alice').get()).get('name'), '新名字');
    assert.equal((await db.doc('churches/C2/members/alice').get()).get('name'), '新名字');
    assert.equal((await db.doc('churches/C2/members/bob').get()).get('name'), 'bob');
  });

  test('a profile name past 40 characters reaches the church cut to 40', async () => {
    await seedChurch('C1', { alice: 'staff' });
    const before = await db.doc('users/alice').get();
    await db.doc('users/alice').set({ name: `  ${'🙏'.repeat(45)}` });
    const after = await db.doc('users/alice').get();

    assert.equal(await syncProfileName(deps, 'alice', before, after), 1);
    assert.equal((await db.doc('churches/C1/members/alice').get()).get('name'), '🙏'.repeat(40));
  });

  test('leaving notifies the admins; removal by an admin does not', async () => {
    await seedChurch('C1', { alice: 'admin', carol: 'admin', bob: 'staff' });
    await db.doc('users/alice').set({ fcm: { phone: 'tok-alice' } });
    await db.doc('users/carol').set({ fcm: { phone: 'tok-carol', web: 'tok-carol-web' } });
    await db.doc('churches/C1/members/carol').update({ 'notificationPrefs.muted': ['memberLeft'] });
    const sent: string[][] = [];
    const messaging = {
      sendEachForMulticast: async (m: { tokens: string[] }) => {
        sent.push(m.tokens);
        return {
          successCount: m.tokens.length,
          failureCount: 0,
          responses: m.tokens.map(() => ({ success: true })),
        };
      },
    } as never;
    const bob = await db.doc('churches/C1/members/bob').get();

    assert.equal(await onMemberLeft({ db, messaging, appUrl }, 'C1', bob, 'bob'), 1);
    assert.deepEqual(sent, [['tok-alice']], 'carol muted it');
    assert.equal(await onMemberLeft({ db, messaging, appUrl }, 'C1', bob, 'alice'), 0);
  });

  test('dead tokens are removed, live ones kept', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await db.doc('users/alice').set({ fcm: { old: 'dead', phone: 'live' } });
    const messaging = {
      sendEachForMulticast: async (m: { tokens: string[] }) => ({
        successCount: 1,
        failureCount: 1,
        responses: m.tokens.map((t) =>
          t === 'dead'
            ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
            : { success: true },
        ),
      }),
    } as never;
    const n = await notifyMembers({ db, messaging, appUrl }, 'C1', ['alice'], 'reminder', { title: 't', body: 'b' });
    assert.equal(n, 1);
    assert.deepEqual((await db.doc('users/alice').get()).get('fcm'), { phone: 'live' });
  });

  test('the web push opens an absolute HTTPS link, as FCM documents', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await db.doc('users/alice').set({ fcm: { laptop: 'tok' } });
    let link = '';
    const messaging = {
      sendEachForMulticast: async (m: { tokens: string[]; webpush: { fcmOptions: { link: string } } }) => {
        link = m.webpush.fcmOptions.link;
        return { successCount: 1, failureCount: 0, responses: [{ success: true }] };
      },
    } as never;
    await notifyMembers({ db, messaging, appUrl }, 'C1', ['alice'], 'reminder', { title: 't', body: 'b', link: '/rosters' });
    assert.equal(link, 'https://app.example/c/C1?to=%2Frosters', 'through the church URL, so it opens this church');
  });

  test('another church never gets the push', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await seedChurch('C2', { eve: 'admin' });
    await db.doc('users/eve').set({ fcm: { phone: 'tok-eve' } });
    let calls = 0;
    const messaging = {
      sendEachForMulticast: async () => {
        calls++;
        return { successCount: 0, failureCount: 0, responses: [] };
      },
    } as never;
    // eve is not a member of C1, so asking C1 to notify eve sends nothing.
    assert.equal(await notifyMembers({ db, messaging, appUrl }, 'C1', ['eve'], 'reminder', { title: 't', body: 'b' }), 0);
    assert.equal(calls, 0);
  });

  test('a logo upload bumps logoVersion; other paths are ignored', async () => {
    await seedChurch('C1', { alice: 'admin' });
    const logoDeps = { ...deps, bucket: getStorage().bucket('demo-martha.appspot.com') };
    assert.equal(await onLogoUploaded(logoDeps, 'churches/C1/logo.png', '123'), true);
    assert.equal((await db.doc('churches/C1').get()).get('logoVersion'), '123');
    assert.equal(await onLogoUploaded(logoDeps, 'other/thing.png', '1'), false);
  });
});

describe('member triggers', () => {
  const key = randomBytes(32).toString('base64');
  let revoked: string[];
  let cal: CalDeps;

  /** C1 with admins alice (who connected the calendar) and bob, and staff carol. */
  async function connected() {
    await seedChurch('C1', { alice: 'admin', bob: 'admin', carol: 'staff' });
    await db.doc('calendarTokens/C1').set({ token: seal('refresh-alice', key), connectedBy: 'alice', calendarId: 'cal' });
    await db.doc('churches/C1/settings/calendar').set({ connected: true });
    await db.doc('users/alice').set({ fcm: { phone: 'tok-alice' } });
    await db.doc('users/bob').set({ fcm: { phone: 'tok-bob' } });
  }

  /** Changes a member doc and returns it before and after. */
  async function change(uid: string, fields: Record<string, unknown>) {
    const ref = db.doc(`churches/C1/members/${uid}`);
    const before = await ref.get();
    await ref.update(fields);
    return [before, await ref.get()] as const;
  }

  beforeEach(() => {
    revoked = [];
    const google = { revoke: async (rt: string) => void revoked.push(rt) } as unknown as GoogleApi;
    cal = { ...deps, secretKey: key, google, config: { clientId: '', clientSecret: '', redirectUri: '', appUrl, tokenKey: key } };
  });

  test('who made a write: a person, or nobody for the backend itself', () => {
    assert.equal(editorOf({ authType: 'unknown', authId: 'alice' }), 'alice');
    assert.equal(editorOf({ authType: 'service_account', authId: 'sa@example.com' }), 'sa@example.com');
    assert.equal(editorOf({ authType: 'system', authId: 'anything' }), undefined);
    assert.equal(editorOf({ authType: 'unauthenticated' }), undefined);
  });

  test('an admin made staff lets go of the calendar they connected', async () => {
    await connected();
    assert.equal(await onMemberUpdated(cal, 'C1', ...(await change('alice', { role: 'staff' }))), true);
    assert.deepEqual(revoked, ['refresh-alice']);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
  });

  test('other member changes keep the calendar', async () => {
    await connected();
    assert.equal(await onMemberUpdated(cal, 'C1', ...(await change('alice', { name: '愛麗絲' }))), false, 'still admin');
    assert.equal(await onMemberUpdated(cal, 'C1', ...(await change('bob', { role: 'staff' }))), false, 'not who connected');
    assert.equal(await onMemberUpdated(cal, 'C1', ...(await change('carol', { role: 'admin' }))), false, 'promoted');
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, true);
  });

  test('the connector leaving: the calendar goes and the admins hear, independently', async () => {
    await connected();
    const sent: string[][] = [];
    const messaging = {
      sendEachForMulticast: async (m: { tokens: string[] }) => {
        sent.push(m.tokens);
        return { successCount: m.tokens.length, failureCount: 0, responses: m.tokens.map(() => ({ success: true })) };
      },
    } as never;
    const alice = await db.doc('churches/C1/members/alice').get();
    await alice.ref.delete();
    assert.deepEqual(await onMemberDeleted({ ...cal, messaging, appUrl }, 'C1', alice, 'alice'), { calendar: true, memberLeft: 1 });
    assert.deepEqual(revoked, ['refresh-alice']);
    assert.deepEqual(sent, [['tok-bob']]);
  });

  test('the push failing still releases the calendar', async () => {
    await connected();
    const messaging = { sendEachForMulticast: async () => Promise.reject(new Error('fcm down')) } as never;
    const alice = await db.doc('churches/C1/members/alice').get();
    await alice.ref.delete();
    await assert.rejects(onMemberDeleted({ ...cal, messaging, appUrl }, 'C1', alice, 'alice'), /fcm down/);
    assert.equal((await db.doc('calendarTokens/C1').get()).exists, false);
  });
});
