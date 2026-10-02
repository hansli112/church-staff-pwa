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
  onDocumentWrittenWithAuthContext,
} from 'firebase-functions/v2/firestore';
import { onCall, type CallableRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onObjectFinalized } from 'firebase-functions/v2/storage';

import * as account from './account.js';
import * as church from './church.js';
import { REGION, type Caller, type Deps } from './common.js';
import * as invites from './invites.js';
import { logClientError as logClientErrorHandler } from './logging.js';
import * as notifications from './notifications.js';
import * as operator from './operator.js';
import { monitoringUsageReader, writeDailyStats } from './stats.js';
import * as triggers from './triggers.js';

initializeApp();

const deps = (): Deps => ({ db: getFirestore(), now: () => new Date() });

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

type Handler = (d: Deps, c: Caller | null, data: unknown) => Promise<unknown>;
const callable = (handler: Handler) =>
  onCall(callOpts, (req) => handler(deps(), caller(req), req.data));

// Churches
export const createChurch = callable(church.createChurch);
export const deleteChurch = callable(church.deleteChurch);
export const restoreChurch = callable(church.restoreChurch);
export const purgeDeletedChurches = onSchedule(
  { region: REGION, schedule: 'every day 03:00', timeZone: 'Asia/Taipei' },
  async () => {
    await church.purgeDeletedChurches(deps(), getStorage());
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
  { region: REGION, document: 'churches/{cid}/members/{uid}' },
  async (event) => {
    if (!event.data) return;
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
