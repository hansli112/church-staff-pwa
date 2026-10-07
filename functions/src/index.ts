// Entry point: wires the handlers to Cloud Functions triggers. Handlers take
// their dependencies as arguments so tests run them against the emulators
// without the Functions runtime.
import { Environment } from '@apple/app-store-server-library';
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
import { onCall, onRequest, type CallableRequest, type Request } from 'firebase-functions/v2/https';
import type { Response } from 'express';
import { defineSecret } from 'firebase-functions/params';
import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onObjectFinalized } from 'firebase-functions/v2/storage';

import * as account from './account.js';
import * as calendar from './calendar.js';
import * as church from './church.js';
import * as claim from './claim.js';
import * as churchLink from './churchLink.js';
import { churchPage as churchPageHandler } from './churchPage.js';
import { PROD_PROJECT, REGION, appUrl, type Caller, type Deps } from './common.js';
import * as funding from './funding.js';
import * as fundingApple from './fundingApple.js';
import * as fundingNewebpay from './fundingNewebpay.js';
import * as fundingPlay from './fundingPlay.js';
import * as invites from './invites.js';
import * as move from './move.js';
import { logClientError as logClientErrorHandler } from './logging.js';
import * as notifications from './notifications.js';
import * as operator from './operator.js';
import * as photo from './photo.js';
import { monitoringUsageReader, writeDailyStats } from './stats.js';
import * as rosterWebhook from './rosterWebhook.js';
import * as triggers from './triggers.js';
import * as webhook from './webhook.js';

initializeApp();

const deps = (): Deps => ({ db: getFirestore(), now: () => new Date(), fetch: globalThis.fetch });

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

// Calendar secrets and deps, defined early: several triggers use them.
const oauthClientId = defineSecret('GOOGLE_OAUTH_CLIENT_ID');
const oauthClientSecret = defineSecret('GOOGLE_OAUTH_CLIENT_SECRET');
const calendarTokenKey = defineSecret('CALENDAR_TOKEN_KEY');
const calendarSecrets = [oauthClientId, oauthClientSecret, calendarTokenKey];
const calDeps = () => ({
  ...deps(),
  google: calendar.googleApi(),
  config: {
    clientId: oauthClientId.value(),
    clientSecret: oauthClientSecret.value(),
    redirectUri: `https://${REGION}-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/calendarCallback`,
    appUrl: appUrl(),
    tokenKey: calendarTokenKey.value(),
  },
});
type Handler = (d: Deps, c: Caller | null, data: unknown) => Promise<unknown>;
const callable = (handler: Handler) =>
  onCall(callOpts, (req) => handler(deps(), caller(req), req.data));

// Churches
export const createChurch = callable(church.createChurch);
export const deleteChurch = callable(church.deleteChurch);
export const restoreChurch = callable(church.restoreChurch);
export const churchPreview = callable(church.churchPreview);
export const purgeDeletedChurches = onSchedule(
  { region: REGION, schedule: 'every day 03:00', timeZone: 'Asia/Taipei', secrets: calendarSecrets },
  async () => {
    const cal = calDeps();
    await church.purgeDeletedChurches(deps(), getStorage(), (cid) => calendar.forgetCalendar(cal, cid));
  },
);

// Church URL: /c/<id> pages, manifests and icons, through Hosting.
export const churchPage = onRequest({ region: REGION, maxInstances: 10 }, async (req, res) => {
  const r = await churchPageHandler({ ...deps(), bucket: getStorage().bucket(), appUrl: appUrl() }, req.path);
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

// 外部通知 (webhooks). The secret is sealed with the calendar token key.
type WebhookHandler = (d: webhook.WebhookDeps, c: Caller | null, data: unknown) => Promise<unknown>;
const webhookDeps = (): webhook.WebhookDeps => ({ ...deps(), secretKey: calendarTokenKey.value() });
const webhookCallable = (handler: WebhookHandler) =>
  onCall({ ...callOpts, secrets: [calendarTokenKey] }, (req) => handler(webhookDeps(), caller(req), req.data));
export const webhookSave = webhookCallable(webhook.webhookSave);
export const webhookRotateSecret = webhookCallable(webhook.webhookRotateSecret);
export const webhookTest = webhookCallable(webhook.webhookTest);

// 自助搬家 (self-serve move from self-host)
type MoveHandler = (d: move.MoveDeps, c: Caller | null, data: unknown) => Promise<unknown>;
const moveCallable = (handler: MoveHandler) =>
  onCall({ ...callOpts, timeoutSeconds: 300, memory: '1GiB' }, (req) =>
    handler({ ...deps(), bucket: getStorage().bucket() }, caller(req), req.data),
  );
export const movePreview = moveCallable(move.movePreview);
export const moveCommit = moveCallable(move.moveCommit);
export const pendingClaims = onCall(callOpts, (req) => claim.pendingClaims(deps(), caller(req)));
export const claimPending = callable(claim.claimPending);
export const mergePending = callable(claim.mergePending);
export const onPendingMemberDeleted = onDocumentDeleted(
  { region: REGION, document: 'churches/{cid}/pendingMembers/{pid}' },
  async (event) => {
    if (event.data) await claim.onPendingMemberDeleted(deps(), event.params.cid, event.data);
  },
);

// Invites
export const previewInvite = callable(invites.previewInvite);
export const redeemInvite = callable(invites.redeemInvite);

// Account
export const deleteAccount = onCall(callOpts, (req) =>
  account.deleteAccount({ ...deps(), auth: getAuth() }, caller(req)),
);

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
  apple ??= fundingApple.appleVerifier(
    process.env.GCLOUD_PROJECT === PROD_PROJECT ? Environment.PRODUCTION : Environment.SANDBOX,
  );
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
const newebpaySecrets = [newebpayHashKey, newebpayHashIv];
const newebpayConfig = () =>
  fundingNewebpay.newebpayConfig({
    merchantId: process.env.NEWEBPAY_MERCHANT_ID,
    gateway: process.env.NEWEBPAY_ENV,
    hashKey: newebpayHashKey.value(),
    hashIv: newebpayHashIv.value(),
    project: process.env.GCLOUD_PROJECT ?? '',
    appUrl: appUrl(),
  });
export const newebpayStart = onRequest(
  { region: REGION, maxInstances: 2, secrets: newebpaySecrets },
  postOnly(async (req, res) => {
    const r = await fundingNewebpay.newebpayStart(deps(), newebpayConfig(), req.body);
    res.set('Cache-Control', 'no-store').status(r.status).json(r.body);
  }),
);
export const newebpayNotify = onRequest(
  { region: REGION, maxInstances: 5, secrets: newebpaySecrets },
  postOnly(async (req, res) => {
    const status = await fundingNewebpay.newebpayNotify(deps(), newebpayConfig(), req.body);
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
    await funding.publishFunding(deps());
    await fundingNewebpay.dropExpiredOrders(deps());
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
  { region: REGION, document: 'churches/{cid}/members/{uid}', secrets: calendarSecrets },
  async (event) => {
    if (!event.data) return;
    // Removed, left, or deleted their account: a calendar they connected
    // goes with them.
    await calendar.releaseCalendarIfConnector(calDeps(), event.params.cid, event.params.uid);
    await triggers.onMemberLeft(
      { db: getFirestore(), messaging: getMessaging(), appUrl: appUrl() },
      event.params.cid,
      event.data,
      event.authType === 'system' ? undefined : event.authId,
    );
  },
);

export const onLogoUploaded = onObjectFinalized({ region: REGION, memory: '512MiB' }, async (event) => {
  await triggers.onLogoUploaded(
    { ...deps(), bucket: getStorage().bucket(event.data.bucket) },
    event.data.name,
    String(event.data.generation),
  );
});

// Push: roster changes and evening reminders
export const onRosterWritten = onDocumentWrittenWithAuthContext(
  { region: REGION, document: 'churches/{cid}/rosters/{rosterId}' },
  async (event) => {
    const editedBy = event.authType === 'system' ? undefined : event.authId;
    await notifications.onRosterWritten(
      { db: getFirestore(), messaging: getMessaging(), appUrl: appUrl(), now: () => new Date() },
      event.params.cid,
      event.data?.before,
      event.data?.after,
      editedBy,
    );
    await rosterWebhook.queueRosterChange(deps(), event.params.cid, event.data?.before, event.data?.after, editedBy, event.id);
  },
);

export const sendRosterChanges = onSchedule(
  { region: REGION, schedule: 'every 5 minutes', timeZone: 'Asia/Taipei', secrets: [calendarTokenKey] },
  async () => {
    await rosterWebhook.sendRosterChanges(webhookDeps());
  },
);

export const sendReminders = onSchedule(
  { region: REGION, schedule: 'every day 19:00', timeZone: 'Asia/Taipei' },
  async () => {
    await notifications.sendReminders({ db: getFirestore(), messaging: getMessaging(), appUrl: appUrl(), now: () => new Date() });
  },
);

// Photo recognition: Gemini on Vertex AI, signed as the Functions service
// account (roles/aiplatform.user), so no API key.
const vertex: photo.VertexConfig = {
  project: process.env.GCLOUD_PROJECT ?? '',
  accessToken: async () => (await applicationDefault().getAccessToken()).access_token,
};
export const recognizeRoster = onCall(
  { ...callOpts, timeoutSeconds: 180, memory: '512MiB' },
  (req) =>
    photo.recognizeRoster(
      { ...deps(), gemini: photo.geminiClient(vertex, (process.env.GEMINI_MODELS ?? '').split(',').filter(Boolean).length ? process.env.GEMINI_MODELS!.split(',') : undefined) },
      caller(req),
      req.data,
    ),
);
export const photoQuota = callable(photo.photoQuota);

// Calendar (Google OAuth, per church)
type CalHandler = (d: ReturnType<typeof calDeps>, c: Caller | null, data: unknown) => Promise<unknown>;
const calendarCallable = (handler: CalHandler) =>
  onCall({ ...callOpts, secrets: calendarSecrets }, (req) => handler(calDeps(), caller(req), req.data));

export const calendarAuthUrl = calendarCallable(calendar.calendarAuthUrl);
export const calendarList = calendarCallable(calendar.calendarList);
export const calendarSelect = calendarCallable(calendar.calendarSelect);
export const calendarDisconnect = calendarCallable(calendar.calendarDisconnect);
export const calendarEvents = calendarCallable(calendar.calendarEvents);
export const calendarWrite = calendarCallable(calendar.calendarWrite);
export const calendarCallback = onRequest({ region: REGION, secrets: calendarSecrets }, async (req, res) => {
  res.redirect(303, await calendar.calendarCallback(calDeps(), req.query as Record<string, unknown>));
});

export const onMemberDemoted = onDocumentUpdated(
  { region: REGION, document: 'churches/{cid}/members/{uid}', secrets: calendarSecrets },
  async (event) => {
    const before = event.data?.before.get('role');
    const after = event.data?.after.get('role');
    if (before === 'admin' && after !== 'admin') {
      await calendar.releaseCalendarIfConnector(calDeps(), event.params.cid, event.params.uid);
    }
  },
);
