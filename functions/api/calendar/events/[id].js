// PATCH  /api/calendar/events/:id — edit an event
// DELETE /api/calendar/events/:id — remove an event

import {
  buildGoogleEvent,
  callCalendar,
  handle,
  HttpError,
  jsonResponse,
  readJsonBody,
  requireAdmin,
} from '../../../../worker/google_calendar.js';

function eventId(params) {
  const id = params?.id;
  if (typeof id !== 'string' || id.trim() === '') {
    throw new HttpError(400, '找不到這個活動');
  }
  return id;
}

export const onRequestPatch = ({ request, env, params }) =>
  handle(async () => {
    await requireAdmin(request, env);
    const id = eventId(params);
    const event = buildGoogleEvent(await readJsonBody(request), { forPatch: true });
    const response = await callCalendar(env, {
      method: 'PATCH',
      eventId: id,
      body: event,
    });
    return jsonResponse(await response.json());
  });

export const onRequestDelete = ({ request, env, params }) =>
  handle(async () => {
    await requireAdmin(request, env);
    const id = eventId(params);
    // Google answers 204; the app only needs to know it worked.
    await callCalendar(env, { method: 'DELETE', eventId: id });
    return new Response(null, { status: 204, headers: { 'cache-control': 'no-store' } });
  });
