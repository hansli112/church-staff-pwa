// POST /api/roster/import-image — turn a photo of the paper roster into the
// JSON the import dialog already accepts.
//
// The conversion used to happen on claude.ai: generate a skill with the staff
// list baked in, upload it, attach the photo there, copy the JSON back. That
// meant the name list went stale every time someone joined, and it meant
// leaving the app. This route does the same job against the prompt that
// scripts/build-import-prompt.py publishes to Firestore.
//
// It returns the parsed rows and nothing else — validating them against the
// roster, matching names to accounts and reporting what did not match all stay
// in parseRosterImportJson on the client, which is the same code path a pasted
// JSON goes through. One place decides what an import means.

import { requireGroupMember, readDocument, HttpError } from '../../../worker/firebase_user.js';
import { handleWith, jsonResponse, readJsonBody } from '../../../worker/http.js';
import { callGemini } from '../../../worker/gemini.js';
import { fillPrompt, loadRosterContext } from '../../../worker/roster_prompt.js';

/// Kept in sync with ServiceType in the Flutter app and the keys of
/// settings/roster_templates.
const TYPES = new Set(['sundayService', 'youth', 'children']);

/// The permission group that may edit rosters. Same name as inGroup() in
/// firestore.rules and UserGroup in the app.
const ROSTER_GROUP = 'roster-editors';

/// What a phone camera produces, plus the screenshot formats. Anything else is
/// refused here rather than sent upstream to be refused there.
const IMAGE_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
]);

const MAX_IMAGES = 3;

/// Per-image ceiling, measured on the decoded bytes. A modern phone photo is
/// 2-5MB; three of those already makes a large request, and the whole thing is
/// held in memory while it is forwarded.
const MAX_IMAGE_BYTES = 6 * 1024 * 1024;

export const onRequestPost = ({ request, env }) =>
  handleWith('roster import function failed', async () => {
    const { token, isAdmin, zoneTypes } = await requireGroupMember(
      request,
      env,
      { group: ROSTER_GROUP, denied: '沒有編輯服事表的權限' },
      fetch,
    );

    const { type, images } = parseImportRequest(await readJsonBody(request));

    // The group says "may edit rosters", the zone says "which one" — the same
    // split canEditRosterType() makes in firestore.rules. Without this a 青崇
    // editor could not write the result, but could still spend the recognition
    // quota on every other service type.
    if (!isAdmin && !zoneTypes.includes(type)) {
      throw new HttpError(403, '沒有編輯這個崇拜服事表的權限');
    }

    // The template says how to read this church's tables; the context is the
    // ministries, events and staff list as they are right now. Reading the
    // second half live is what makes a volunteer who got an account this
    // morning recognised this afternoon, with nobody re-running anything.
    const [template, context] = await Promise.all([
      loadTemplate(env, type, token),
      loadRosterContext(env, type, token, fetch),
    ]);
    const entries = await callGemini(env, {
      prompt: fillPrompt(template, context),
      images,
    });
    return jsonResponse({ entries });
  });

/// Validates the request body and returns it in the shape callGemini wants.
///
/// Exported for the tests: every rejection here is a message someone will see
/// on a phone with a photo already picked, so they are worth asserting on
/// directly rather than through a full round trip.
export function parseImportRequest(body) {
  const type = body?.type;
  if (typeof type !== 'string' || !TYPES.has(type)) {
    throw new HttpError(400, '不知道這是哪一個崇拜的服事表');
  }

  const images = body?.images;
  if (!Array.isArray(images) || images.length === 0) {
    throw new HttpError(400, '請先選一張服事表照片');
  }
  if (images.length > MAX_IMAGES) {
    throw new HttpError(400, `一次最多 ${MAX_IMAGES} 張照片`);
  }

  const parsed = images.map((image, index) => {
    const at = images.length === 1 ? '照片' : `第 ${index + 1} 張照片`;
    const mimeType = image?.mimeType;
    if (typeof mimeType !== 'string' || !IMAGE_TYPES.has(mimeType)) {
      throw new HttpError(400, `${at}的格式不支援，請用 JPG 或 PNG`);
    }
    const data = image?.data;
    if (typeof data !== 'string' || data === '') {
      throw new HttpError(400, `${at}讀不到內容，請重新選一次`);
    }
    // base64 inflates by 4/3, so the decoded size can be checked without
    // decoding — which matters when the point of the check is not holding the
    // decoded bytes in memory.
    if (Math.floor((data.length * 3) / 4) > MAX_IMAGE_BYTES) {
      throw new HttpError(
        413,
        `${at}太大了（上限 ${MAX_IMAGE_BYTES / 1024 / 1024}MB），請先縮小再試`,
      );
    }
    return { mimeType, data };
  });

  return { type, images: parsed };
}

/// The published prompt *template* for this service type.
///
/// A template, not a finished prompt: the staff list and the ministry names are
/// filled in by fillPrompt from live Firestore. What is published here is only
/// the part a person wrote — how this church's tables are laid out.
///
/// Read as the caller, like every other Firestore read here, so a user who
/// cannot read settings/ cannot reach it through this route either.
async function loadTemplate(env, type, token) {
  const doc = await readDocument(env, 'settings/import_prompts', token, fetch);
  const prompt = doc?.fields?.[type]?.stringValue;
  if (typeof prompt !== 'string' || prompt.trim() === '') {
    // The operator has not run `scripts/build-import-prompt.py --publish`, or
    // ran it before this service type existed. Nothing the caller can do about
    // it, so the detail goes to the log and they get told who to ask.
    console.error('no published import prompt', type);
    throw new HttpError(500, '辨識設定還沒建立，請聯絡管理員');
  }
  return prompt;
}
