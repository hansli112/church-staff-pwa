// Builds the prompt that goes to Gemini with the roster photo.
//
// The prompt is in two halves, and the split is the whole point:
//
//   authored — how to read *this church's* tables. Layout, which column is
//              which ministry, nicknames, how a worship team expands. Changes
//              only when someone edits .local/import-rules.json, so
//              scripts/build-import-prompt.py --publish bakes it into
//              settings/import_prompts and leaves it there.
//
//   live     — the ministries, the event catalogue, the staff list, today's
//              date. These change whenever an admin touches the app, so they
//              are filled here, on every call, from Firestore as it is right
//              now.
//
// Baking the staff list into the published prompt was the first design, and it
// was wrong: a new volunteer got an account and then someone had to remember to
// re-run a script before their name would be recognised. Nobody remembers.

import { HttpError, listDocuments, readDocument } from './firebase_user.js';
import { churchConfig, dateKeyInZone } from './church_config.js';

/// Must match LIVE_FIELDS in scripts/build-import-prompt.py. If the two drift,
/// a published template keeps a `{{NAMES}}` in it and that literal text is what
/// gets sent to the model.
const LIVE_FIELDS = ['ROLES', 'EVENTS', 'NAMES', 'TODAY', 'SAMPLE_ROLE_A', 'SAMPLE_ROLE_B'];

/// How many names per line in the whitelist, and what an empty event catalogue
/// prints as. Both have a twin in scripts/build-import-prompt.py; if they drift,
/// the prompt verified locally is not the prompt that goes out, and nothing
/// would say so. functions-tests/prompt_parity.test.js pins them together.
const NAMES_PER_LINE = 6;
const NO_EVENTS = '（尚未設定）';

/// Reads everything that changes, as the caller.
///
/// Three reads rather than one cached blob: this runs once per photo, which is
/// a few times a quarter, and a cache that can be stale is exactly the problem
/// this module exists to remove.
export async function loadRosterContext(env, type, token, fetchImpl = fetch) {
  const [templates, options, users] = await Promise.all([
    readDocument(env, 'settings/roster_templates', token, fetchImpl),
    readDocument(env, 'settings/event_options', token, fetchImpl),
    // Only the display name: the user documents also hold email addresses and
    // FCM tokens, and none of that belongs in a prompt sent to Google.
    listDocuments(env, 'users', token, { mask: ['name'], fetchImpl }),
  ]);

  const roles = stringArray(templates?.fields?.[type]);
  if (roles.length === 0) {
    // Without the ministry list the model has no vocabulary to map columns
    // onto, and every duty would come back as a name the app cannot place.
    console.error('no roster template for type', type);
    throw new HttpError(500, '這個崇拜還沒有服事項目設定，請管理員先新增');
  }

  return {
    roles,
    events: namedArray(options?.fields?.[type]),
    names: staffNames(users),
    today: dateKeyInZone(new Date(), churchConfig(env).timeZone),
  };
}

/// Substitutes the live fields into a published template.
///
/// Throws rather than sending a prompt with a leftover `{{...}}` in it: the
/// model would happily treat the literal braces as part of the instructions and
/// the result would be subtly wrong instead of obviously broken.
export function fillPrompt(template, { roles, events, names, today }) {
  const filled = template
    .replaceAll('{{ROLES}}', roles.join('、'))
    .replaceAll('{{EVENTS}}', events.length > 0 ? events.join('、') : NO_EVENTS)
    .replaceAll('{{NAMES}}', nameBlock(names))
    .replaceAll('{{TODAY}}', today)
    .replaceAll('{{SAMPLE_ROLE_A}}', roles[0])
    .replaceAll('{{SAMPLE_ROLE_B}}', roles[1] ?? roles[0]);

  const leftover = filled.match(/\{\{[A-Z_]+\}\}/g);
  if (leftover) {
    console.error('template has unfilled fields', [...new Set(leftover)].join(', '));
    throw new HttpError(500, '辨識設定有誤，請聯絡管理員');
  }
  return filled;
}

/// Exported for prompt_parity.test.js, which reads the Python's constants and
/// fails if either side is changed alone.
export const parityConstants = {
  liveFields: LIVE_FIELDS,
  namesPerLine: NAMES_PER_LINE,
  noEvents: NO_EVENTS,
};

function nameBlock(names) {
  const lines = [];
  for (let i = 0; i < names.length; i += NAMES_PER_LINE) {
    lines.push('  ' + names.slice(i, i + NAMES_PER_LINE).join('、'));
  }
  return lines.join('\n');
}

/// `settings/roster_templates` stores each type as an array of plain strings.
function stringArray(field) {
  const values = field?.arrayValue?.values;
  if (!Array.isArray(values)) return [];
  return values.map((entry) => entry?.stringValue).filter((name) => typeof name === 'string' && name !== '');
}

/// `settings/event_options` stores maps of `{ name, color }`; only the name is
/// wanted here. Colours are applied by the app after import, and the prompt
/// deliberately never asks the model for one.
function namedArray(field) {
  const values = field?.arrayValue?.values;
  if (!Array.isArray(values)) return [];
  return values
    .map((entry) => entry?.mapValue?.fields?.name?.stringValue)
    .filter((name) => typeof name === 'string' && name !== '');
}

/// Sorted and de-duplicated, matching fetch_names() in the Python so both sides
/// produce the same whitelist for the same roster.
function staffNames(documents) {
  const names = new Set();
  for (const doc of documents) {
    const name = doc?.fields?.name?.stringValue;
    if (typeof name === 'string' && name.trim() !== '') names.add(name.trim());
  }
  return [...names].sort();
}
