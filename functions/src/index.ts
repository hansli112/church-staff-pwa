// Entry point: declares the Cloud Functions and wires each to its handler.
// Handlers take their dependencies as arguments, built here and only here,
// so tests run them against the emulators without the Functions runtime.
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { getStorage } from 'firebase-admin/storage';
import {
  onDocumentDeleted,
  onDocumentDeletedWithAuthContext,
  onDocumentWritten,
  onDocumentUpdated,
  onDocumentWrittenWithAuthContext,
} from 'firebase-functions/v2/firestore';
import { onCall, onRequest, type CallableOptions, type CallableRequest, type Request } from 'firebase-functions/v2/https';
import type { Response } from 'express';
import { defineSecret, type SecretParam } from 'firebase-functions/params';
import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onObjectFinalized } from 'firebase-functions/v2/storage';

import * as account from './account.js';
import * as calendar from './calendar.js';
import * as eventSync from './eventSync.js';
import * as church from './church.js';
import * as claim from './claim.js';
import * as pendingMembers from './pendingMembers.js';
import * as churchLink from './churchLink.js';
import { churchPage as churchPageHandler } from './churchPage.js';
import { PROD_PROJECT, REGION, appUrl, runEach, type Caller, type Deps } from './common.js';
import * as funding from './funding.js';
import * as fundingApple from './fundingApple.js';
import * as fundingNewebpay from './fundingNewebpay.js';
import * as fundingPlay from './fundingPlay.js';
import * as invites from './invites.js';
import { memoryGoogle } from './memoryGoogle.js';
import * as move from './move.js';
import { logClientError as logClientErrorHandler } from './logging.js';
import * as notifications from './notifications.js';
import * as operator from './operator.js';
import * as photo from './photo.js';
import { monitoringUsageReader, writeDailyStats } from './stats.js';
import * as rosterChange from './rosterChange.js';
import * as serviceSettings from './serviceSettings.js';
import * as triggers from './triggers.js';
import * as webhook from './webhook.js';

initializeApp();

// Dependencies
const deps = (): Deps => ({ db: getFirestore(), now: () => new Date(), fetch: globalThis.fetch });
const bucket = () => getStorage().bucket();
const withPush = <D extends Deps>(d: D) => ({ ...d, messaging: getMessaging(), appUrl: appUrl() });
const pushDeps = () => withPush(deps());

/**
 * Dependencies that read secrets, with the secrets a function must list to
 * read them: a secret not listed fails only when read, in production. A
 * function takes both from one of these.
 */
interface WithSecrets<D> {
  make: () => D;
  secrets: SecretParam[];
}
const needing = <D>(secrets: SecretParam[], make: () => D): WithSecrets<D> => ({ make, secrets });

// One key seals both the calendar refresh tokens and the webhook secrets
// (sealing.ts).
const oauthClientId = defineSecret('GOOGLE_OAUTH_CLIENT_ID');
const oauthClientSecret = defineSecret('GOOGLE_OAUTH_CLIENT_SECRET');
const sealKey = defineSecret('CALENDAR_TOKEN_KEY');
const hook = needing<webhook.WebhookDeps>([sealKey], () => ({ ...deps(), secretKey: sealKey.value() }));
// One adapter per warm instance; every access still reads the church's grant.
// The emulator on a demo project never reaches Google: there it is in memory.
const offline = process.env.FUNCTIONS_EMULATOR === 'true' && process.env.GCLOUD_PROJECT?.startsWith('demo-');
const google = offline ? memoryGoogle().google : calendar.googleApi();
const cal = needing<calendar.CalDeps>([oauthClientId, oauthClientSecret, sealKey], () => ({
  ...hook.make(),
  google,
  config: {
    clientId: oauthClientId.value(),
    clientSecret: oauthClientSecret.value(),
    redirectUri: `https://${REGION}-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/calendarCallback`,
    appUrl: appUrl(),
    tokenKey: sealKey.value(),
  },
}));

function caller(req: CallableRequest): Caller | null {
  if (!req.auth) return null;
  const t = req.auth.token;
  return {
    uid: req.auth.uid,
    email: t.email,
    emailVerified: t.email_verified === true,
    name: typeof t.name === 'string' ? t.name : undefined,
    operator: t.operator === true,
  };
}

const callOpts = { region: REGION, cors: true, maxInstances: 10 };
type Handler<D> = (d: D, c: Caller | null, data: unknown) => Promise<unknown>;
/** A callable function: [handler] with deps from [make], and the secrets they read; [opts] on top of callOpts. */
const callable = <D = Deps>(handler: Handler<D>, make: (() => D) | WithSecrets<D> = deps as () => D, opts: CallableOptions = {}) => {
  const w = typeof make === 'function' ? needing([], make) : make;
  const secrets = w.secrets.length ? { secrets: w.secrets } : {};
  return onCall({ ...callOpts, ...secrets, ...opts }, (req) => handler(w.make(), caller(req), req.data));
};

// Churches
export const createChurch = callable(church.createChurch);
export const deleteChurch = callable(church.deleteChurch);
export const restoreChurch = callable(church.restoreChurch);
export const setChurchTimeZone = callable(church.setChurchTimeZone, cal);
export const churchPreview = callable(church.churchPreview);
export const purgeDeletedChurches = onSchedule(
  { region: REGION, schedule: 'every day 03:00', timeZone: 'Asia/Taipei', secrets: cal.secrets },
  async () => {
    await church.purgeDeletedChurches({ ...cal.make(), bucket: bucket() });
  },
);

// Church URL: /c/<id> pages, manifests and icons, through Hosting.
export const churchPage = onRequest({ region: REGION, maxInstances: 10 }, async (req, res) => {
  const r = await churchPageHandler({ ...deps(), bucket: bucket(), appUrl: appUrl() }, req.path, req.get('accept-language'));
  res.status(r.status).set(r.headers).send(r.body);
});

// Church link: the daily content source
export const setLinkSource = callable(churchLink.setLinkSource);
export const fetchChurchLinks = onSchedule(
  { region: REGION, schedule: 'every 15 minutes', timeZone: 'Asia/Taipei' },
  async () => {
    await churchLink.fetchDueLinks(deps());
  },
);

// 外部通知 (webhooks)
export const webhookSave = callable(webhook.webhookSave, hook);
export const webhookRotateSecret = callable(webhook.webhookRotateSecret, hook);
export const webhookTest = callable(webhook.webhookTest, hook);

// 自助搬家 (self-serve move from self-host)
const moveDeps = (): move.MoveDeps => ({ ...deps(), bucket: bucket() });
const moveOpts: CallableOptions = { timeoutSeconds: 300, memory: '1GiB' };
export const movePreview = callable(move.movePreview, moveDeps, moveOpts);
export const moveCommit = callable(move.moveCommit, moveDeps, moveOpts);
export const pendingClaims = callable(claim.pendingClaims);
export const claimPending = callable(claim.claimPending);
export const mergePending = callable(claim.mergePending);
export const onPendingMemberDeleted = onDocumentDeleted(
  { region: REGION, document: 'churches/{cid}/pendingMembers/{pid}' },
  async (event) => {
    if (event.data) await pendingMembers.onPendingMemberDeleted(deps(), event.params.cid, event.data);
  },
);

// Service settings: compared edits and atomic configured duty renames.
export const editService = callable(serviceSettings.editService);

// Invites
export const previewInvite = callable(invites.previewInvite);
export const redeemInvite = callable(invites.redeemInvite);

// Account
export const deleteAccount = callable(account.deleteAccount, () => ({ ...deps(), auth: getAuth() }));

// Platform operator
export const adminSearchChurches = callable(operator.adminSearchChurches);
export const adminRenameChurch = callable(operator.adminRenameChurch);
export const adminTransferAdmin = callable(operator.adminTransferAdmin);
export const adminSetStatus = callable(operator.adminSetStatus);
export const adminStats = callable(operator.adminStats);
export const adminChurchMembers = callable(operator.adminChurchMembers);

export const dailyStats = onSchedule(
  { region: REGION, schedule: 'every day 01:30', timeZone: 'Asia/Taipei' },
  async () => {
    const projectId = process.env.GCLOUD_PROJECT ?? '';
    await writeDailyStats(deps(), monitoringUsageReader(projectId));
  },
);

// 雲端費用進度: payments arrive from the stores (and the website's NewebPay
// payments, below) on their own; the operator only keeps the cost list.
export const adminFunding = callable(funding.adminFunding);
export const adminSetFundingCosts = callable(funding.adminSetFundingCosts);
/** [handler] for POST requests; anything else gets 405. */
const postOnly =
  (handler: (req: Request, res: Response) => Promise<void>) => async (req: Request, res: Response) => {
    if (req.method !== 'POST') {
      res.status(405).end();
      return;
    }
    await handler(req, res);
  };
// Built on first use: every function loads this file, only this one needs Apple's certificate.
let apple: fundingApple.AppleVerifier | undefined;
export const appStoreNotifications = onRequest({ region: REGION, maxInstances: 5 }, postOnly(async (req, res) => {
  if (!apple) {
    const { Environment } = await import('@apple/app-store-server-library');
    apple ??= fundingApple.appleVerifier(
      process.env.GCLOUD_PROJECT === PROD_PROJECT ? Environment.PRODUCTION : Environment.SANDBOX,
    );
  }
  res.status(await fundingApple.appStoreNotification(deps(), apple, req.body)).end();
}));
// Play Console sends to this topic. Throwing makes Pub/Sub deliver again.
export const playBillingNotifications = onMessagePublished(
  { topic: 'play-billing', region: REGION, retry: true, maxInstances: 5 },
  (event) => fundingPlay.playNotification(deps(), event.data.message.json, new Date(event.data.message.publishTime)),
);
// 線上支持 on the website, through NewebPay (藍新金流). The support page
// posts to /support/pay (a Hosting rewrite to newebpayStart) and sends the
// browser on to NewebPay; NewebPay posts the result to newebpayNotify, and
// the payer comes back through newebpayReturn. Off until NEWEBPAY_MERCHANT_ID
// and NEWEBPAY_ENV are set (functions/.env.<project>) and the two secrets
// hold the store's real keys (docs/firebase-setup.md).
const newebpayHashKey = defineSecret('NEWEBPAY_HASH_KEY');
const newebpayHashIv = defineSecret('NEWEBPAY_HASH_IV');
const newebpay = needing([newebpayHashKey, newebpayHashIv], () =>
  fundingNewebpay.newebpayConfig({
    merchantId: process.env.NEWEBPAY_MERCHANT_ID,
    gateway: process.env.NEWEBPAY_ENV,
    hashKey: newebpayHashKey.value(),
    hashIv: newebpayHashIv.value(),
    project: process.env.GCLOUD_PROJECT ?? '',
    appUrl: appUrl(),
  }),
);
export const newebpayStart = onRequest(
  { region: REGION, maxInstances: 2, secrets: newebpay.secrets },
  postOnly(async (req, res) => {
    const r = await fundingNewebpay.newebpayStart(deps(), newebpay.make(), req.body);
    res.set('Cache-Control', 'no-store').status(r.status).json(r.body);
  }),
);
export const newebpayNotify = onRequest(
  { region: REGION, maxInstances: 5, secrets: newebpay.secrets },
  postOnly(async (req, res) => {
    const status = await fundingNewebpay.newebpayNotify(deps(), newebpay.make(), req.body);
    res.status(status).send(status === 200 ? 'OK' : '');
  }),
);
export const newebpayReturn = onRequest({ region: REGION, maxInstances: 5 }, (req, res) => {
  res.redirect(303, fundingNewebpay.returnLocation(appUrl(), req.method === 'POST' ? req.body : null));
});
// Starts each month's target, refreshes the exchange rates, and drops
// 線上支持 orders nobody paid.
export const fundingDaily = onSchedule(
  { region: REGION, schedule: 'every day 00:10', timeZone: 'Asia/Taipei' },
  async () => {
    const d = deps();
    await runEach('fundingDaily', {
      publish: () => funding.publishFunding(d),
      orders: () => fundingNewebpay.dropExpiredOrders(d),
    });
  },
);

// Errors from web clients
export const logClientError = onCall({ ...callOpts, maxInstances: 3 }, (req) =>
  logClientErrorHandler(caller(req), req.data),
);

// Triggers
export const onUserWritten = onDocumentWritten(
  { region: REGION, document: 'users/{uid}' },
  async (event) => {
    await triggers.syncProfileName(deps(), event.params.uid, event.data?.before, event.data?.after);
  },
);

export const onMemberDeleted = onDocumentDeletedWithAuthContext(
  { region: REGION, document: 'churches/{cid}/members/{uid}', secrets: cal.secrets },
  async (event) => {
    if (!event.data) return;
    await triggers.onMemberDeleted(withPush(cal.make()), event.params.cid, event.data, triggers.editorOf(event));
  },
);

export const onMemberDemoted = onDocumentUpdated(
  { region: REGION, document: 'churches/{cid}/members/{uid}', secrets: cal.secrets },
  async (event) => {
    if (!event.data) return;
    await triggers.onMemberUpdated(cal.make(), event.params.cid, event.data.before, event.data.after);
  },
);

export const onLogoUploaded = onObjectFinalized({ region: REGION, memory: '512MiB' }, async (event) => {
  await triggers.onLogoUploaded(
    { ...deps(), bucket: getStorage().bucket(event.data.bucket) },
    event.data.name,
    String(event.data.generation),
  );
});

// Roster changes (push and webhook) and evening reminders
export const onRosterWritten = onDocumentWrittenWithAuthContext(
  { region: REGION, document: 'churches/{cid}/rosters/{rosterId}' },
  async (event) => {
    await rosterChange.onRosterWritten(
      pushDeps(),
      event.params.cid,
      event.data?.before,
      event.data?.after,
      triggers.editorOf(event),
      event.id,
    );
  },
);

export const sendRosterChanges = onSchedule(
  { region: REGION, schedule: 'every 5 minutes', timeZone: 'Asia/Taipei', secrets: hook.secrets },
  async () => {
    await webhook.sendQueued(hook.make());
  },
);

// Events' rosters against what was done in Google Calendar itself, at
// 6:30, 12:30 and 18:30 on each church's clock; the evening run comes
// before its reminders at 19:00, which go out every hour to the churches
// whose clock says so.
export const syncEventRosters = onSchedule(
  { region: REGION, schedule: '30 * * * *', timeZone: 'Asia/Taipei', secrets: cal.secrets, timeoutSeconds: 540 },
  async () => {
    const counts = await eventSync.syncEventRosters(cal.make());
    console.log('event rosters synced', counts);
  },
);

export const sendReminders = onSchedule(
  { region: REGION, schedule: '0 * * * *', timeZone: 'Asia/Taipei' },
  async () => {
    await notifications.sendReminders(pushDeps());
  },
);

// Photo recognition: Gemini on Vertex AI, signed as the Functions service
// account (roles/aiplatform.user), so no API key.
const vertex: photo.VertexConfig = {
  project: process.env.GCLOUD_PROJECT ?? '',
  accessToken: async () => (await applicationDefault().getAccessToken()).access_token,
};
export const recognizeRoster = callable(
  photo.recognizeRoster,
  () => ({ ...deps(), gemini: photo.geminiClient(vertex, photo.geminiModels(process.env.GEMINI_MODELS)) }),
  { timeoutSeconds: 180, memory: '512MiB' },
);
export const photoQuota = callable(photo.photoQuota);

// Calendar (Google OAuth, per church)
export const calendarAuthUrl = callable(calendar.calendarAuthUrl, cal);
export const calendarList = callable(calendar.calendarList, cal);
export const calendarSelect = callable(calendar.calendarSelect, cal);
export const calendarDisconnect = callable(calendar.calendarDisconnect, cal);
export const calendarEvents = callable(calendar.calendarEvents, cal);
export const calendarWrite = callable(calendar.calendarWrite, cal);
export const calendarCallback = onRequest({ region: REGION, secrets: cal.secrets }, async (req, res) => {
  res.redirect(303, await calendar.calendarCallback(cal.make(), req.query as Record<string, unknown>));
});
