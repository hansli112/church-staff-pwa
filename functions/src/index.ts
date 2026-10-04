// Entry point: wires the handlers to Cloud Functions triggers. Handlers take
// their dependencies as arguments so tests run them against the emulators
// without the Functions runtime.
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { getStorage } from 'firebase-admin/storage';
import {
  onDocumentDeletedWithAuthContext,
  onDocumentWritten,
  onDocumentUpdated,
  onDocumentWrittenWithAuthContext,
} from 'firebase-functions/v2/firestore';
import { onCall, onRequest, type CallableRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onObjectFinalized } from 'firebase-functions/v2/storage';

import * as account from './account.js';
import * as calendar from './calendar.js';
import * as church from './church.js';
import { REGION, type Caller, type Deps } from './common.js';
import * as invites from './invites.js';
import { logClientError as logClientErrorHandler } from './logging.js';
import * as notifications from './notifications.js';
import * as operator from './operator.js';
import * as photo from './photo.js';
import { monitoringUsageReader, writeDailyStats } from './stats.js';
import * as triggers from './triggers.js';

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
    appUrl: process.env.APP_URL ?? `https://${process.env.GCLOUD_PROJECT}.web.app`,
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
export const purgeDeletedChurches = onSchedule(
  { region: REGION, schedule: 'every day 03:00', timeZone: 'Asia/Taipei', secrets: calendarSecrets },
  async () => {
    const cal = calDeps();
    await church.purgeDeletedChurches(deps(), getStorage(), (cid) => calendar.forgetCalendar(cal, cid));
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
      { db: getFirestore(), messaging: getMessaging() },
      event.params.cid,
      event.data,
      event.authType === 'system' ? undefined : event.authId,
    );
  },
);

export const onLogoUploaded = onObjectFinalized({ region: REGION }, async (event) => {
  await triggers.onLogoUploaded(deps(), event.data.name, String(event.data.generation));
});

// Push: roster changes and evening reminders
export const onRosterWritten = onDocumentWrittenWithAuthContext(
  { region: REGION, document: 'churches/{cid}/rosters/{rosterId}' },
  async (event) => {
    await notifications.onRosterWritten(
      { db: getFirestore(), messaging: getMessaging(), now: () => new Date() },
      event.params.cid,
      event.data?.before,
      event.data?.after,
      event.authType === 'system' ? undefined : event.authId,
    );
  },
);

export const sendReminders = onSchedule(
  { region: REGION, schedule: 'every day 19:00', timeZone: 'Asia/Taipei' },
  async () => {
    await notifications.sendReminders({ db: getFirestore(), messaging: getMessaging(), now: () => new Date() });
  },
);

// Photo recognition (Gemini, paid tier). The key is a Secret Manager secret.
const geminiKey = defineSecret('GEMINI_API_KEY');
export const recognizeRoster = onCall(
  { ...callOpts, secrets: [geminiKey], timeoutSeconds: 180, memory: '512MiB' },
  (req) =>
    photo.recognizeRoster(
      { ...deps(), gemini: photo.geminiClient(geminiKey.value(), (process.env.GEMINI_MODELS ?? '').split(',').filter(Boolean).length ? process.env.GEMINI_MODELS!.split(',') : undefined) },
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
