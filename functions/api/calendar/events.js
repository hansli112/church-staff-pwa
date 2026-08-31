// POST /api/calendar/events — create a calendar event.
//
// Same origin as the app, so no CORS and no second domain to configure. Only
// the exported onRequest* methods are routed; every other verb gets a 405 from
// the Pages runtime.

import {
  buildGoogleEvent,
  callCalendar,
  handle,
  jsonResponse,
  readJsonBody,
  requireEditor,
} from '../../../worker/google_calendar.js';
import { notifyN8n, notifyPayload, scheduleNotify } from '../../../worker/line_notify.js';

export const onRequestPost = ({ request, env, waitUntil }) =>
  handle(async () => {
    const actor = await requireEditor(request, env);
    const event = buildGoogleEvent(await readJsonBody(request));
    const response = await callCalendar(env, { method: 'POST', body: event });
    // The raw Google item is returned on purpose: the client parses it with the
    // same code that parses the month listing, so the two cannot drift.
    const created = await response.json();
    // 活動已經建好，通知成不成功都不改變這個回應。有 waitUntil 時它在背景跑完，
    // 使用者不必等 LINE。
    await scheduleNotify(waitUntil, notifyN8n(env, notifyPayload('created', created, actor)));
    return jsonResponse(created, 201);
  });
