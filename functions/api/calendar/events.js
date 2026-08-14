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

export const onRequestPost = ({ request, env }) =>
  handle(async () => {
    await requireEditor(request, env);
    const event = buildGoogleEvent(await readJsonBody(request));
    const response = await callCalendar(env, { method: 'POST', body: event });
    // The raw Google item is returned on purpose: the client parses it with the
    // same code that parses the month listing, so the two cannot drift.
    return jsonResponse(await response.json(), 201);
  });
