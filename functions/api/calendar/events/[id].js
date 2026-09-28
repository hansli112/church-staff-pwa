// PATCH  /api/calendar/events/:id — edit an event
// DELETE /api/calendar/events/:id — remove an event

import { churchConfig, requireFeature } from '../../../../worker/church_config.js';
import { authorize } from '../../../../worker/authorize.js';
import { HttpError } from '../../../../worker/firebase_user.js';
import {
  CALENDAR_LOG_LABEL,
  buildGoogleEvent,
  callCalendar,
} from '../../../../worker/google_calendar.js';
import { handleWith, jsonResponse, readJsonBody } from '../../../../worker/http.js';

function eventId(params) {
  const id = params?.id;
  if (typeof id !== 'string' || id.trim() === '') {
    throw new HttpError(400, '找不到這個活動');
  }
  return id;
}

export const onRequestPatch = ({ request, env, params }) =>
  handleWith(CALENDAR_LOG_LABEL, async () => {
    requireFeature(env, 'calendar');
    await authorize(request, env, { edit: 'calendar' });
    const id = eventId(params);
    const event = buildGoogleEvent(await readJsonBody(request), { forPatch: true, timeZone: churchConfig(env).timeZone });
    const response = await callCalendar(env, {
      method: 'PATCH',
      eventId: id,
      body: event,
    });
    return jsonResponse(await response.json());
  });

export const onRequestDelete = ({ request, env, params }) =>
  handleWith(CALENDAR_LOG_LABEL, async () => {
    requireFeature(env, 'calendar');
    await authorize(request, env, { edit: 'calendar' });
    const id = eventId(params);
    // Google answers 204; the app only needs to know it worked.
    await callCalendar(env, { method: 'DELETE', eventId: id });
    return new Response(null, { status: 204, headers: { 'cache-control': 'no-store' } });
  });
