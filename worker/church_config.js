// Public deployment settings, never credentials. The generator validates the
// same schema before embedding it into Flutter, this Worker and Firestore rules.
import defaultConfig from './generated_config.js';
import { HttpError } from './firebase_user.js';

const SERVICE_ID = /^[A-Za-z][A-Za-z0-9_-]{0,63}$/;
const FEATURES = ['calendar', 'photoImport', 'pushNotifications', 'lineNotifications'];
const ICONS = ['favicon', 'icon192', 'icon512', 'maskable192', 'maskable512'];

function object(value, keys, at) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${at} must be an object`);
  }
  if (Object.keys(value).some((key) => !keys.includes(key))) {
    throw new Error(`${at} contains an unknown field (credentials belong in secrets, not church config)`);
  }
}

function text(value, at, max = 100, empty = false) {
  if (typeof value !== 'string' || (!empty && !value.trim()) || value.length > max || /[\u0000-\u001f\u007f]/u.test(value)) {
    throw new Error(`${at} must be ${empty ? 'a' : 'a nonempty'} string of at most ${max} characters`);
  }
}

function boolean(value, at) {
  if (typeof value !== 'boolean') throw new Error(`${at} must be a boolean`);
}

function httpsUrl(value, at) {
  text(value, at, 2048, true);
  if (!value) return;
  let url;
  try { url = new URL(value); } catch { throw new Error(`${at} must be an HTTPS URL`); }
  if (url.protocol !== 'https:' || url.username || url.password) {
    throw new Error(`${at} must be an HTTPS URL without credentials`);
  }
}

export function validateChurchConfig(config) {
  object(config, ['schemaVersion', 'appName', 'shortName', 'timeZone', 'services', 'features', 'devotional', 'icons'], 'config');
  if (config.schemaVersion !== 1) throw new Error('schemaVersion must be 1');
  text(config.appName, 'appName');
  text(config.shortName, 'shortName', 40);
  text(config.timeZone, 'timeZone', 100);
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: config.timeZone }).format();
  } catch {
    throw new Error('timeZone must be an IANA time zone');
  }
  // Intl also accepts fixed offsets on newer runtimes; the app requires IANA.
  if (/^[+-]/.test(config.timeZone)) throw new Error('timeZone must be an IANA time zone');
  if (!Array.isArray(config.services) || config.services.length < 1 || config.services.length > 20) {
    throw new Error('services must contain 1 to 20 services');
  }
  const ids = new Set();
  for (const service of config.services) {
    object(service, ['id', 'label', 'name', 'weekday', 'enabled'], 'service');
    if (typeof service.id !== 'string' || !SERVICE_ID.test(service.id) || ['__proto__', 'constructor', 'prototype'].includes(service.id)) {
      throw new Error('service.id must be a stable identifier matching [A-Za-z][A-Za-z0-9_-]{0,63}');
    }
    if (ids.has(service.id)) throw new Error(`duplicate service id: ${service.id}`);
    ids.add(service.id);
    text(service.label, 'service.label', 40);
    text(service.name, 'service.name');
    if (!Number.isInteger(service.weekday) || service.weekday < 1 || service.weekday > 7) {
      throw new Error('service.weekday must be an integer from 1 (Monday) to 7 (Sunday)');
    }
    boolean(service.enabled, 'service.enabled');
  }
  object(config.features, FEATURES, 'features');
  for (const key of FEATURES) boolean(config.features[key], `features.${key}`);
  if (config.features.lineNotifications && !config.features.calendar) {
    throw new Error('lineNotifications requires calendar');
  }
  object(config.devotional, ['enabled', 'dataUrl', 'linkUrl', 'sourceName', 'fetchUrl', 'fetchFormat'], 'devotional');
  boolean(config.devotional.enabled, 'devotional.enabled');
  httpsUrl(config.devotional.dataUrl, 'devotional.dataUrl');
  httpsUrl(config.devotional.linkUrl, 'devotional.linkUrl');
  text(config.devotional.sourceName, 'devotional.sourceName');
  httpsUrl(config.devotional.fetchUrl ?? '', 'devotional.fetchUrl');
  if (!['json', 'dailyBibleHtml'].includes(config.devotional.fetchFormat ?? 'json')) {
    throw new Error('devotional.fetchFormat must be json or dailyBibleHtml');
  }
  if (config.devotional.enabled && (!config.devotional.dataUrl || !config.devotional.linkUrl)) {
    throw new Error('devotional.dataUrl and linkUrl are required when enabled');
  }
  object(config.icons, ICONS, 'icons');
  for (const key of ICONS) {
    const path = config.icons[key];
    text(path, `icons.${key}`, 240);
    if (!/^[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*\.png$/.test(path)) {
      throw new Error(`icons.${key} must be a safe relative PNG path`);
    }
  }
  return config;
}

// A symbol cannot be supplied by an HTTP request or a Cloudflare JSON binding.
// It lets unit tests exercise a different deployment without editing sources.
export const TEST_CHURCH_CONFIG = Symbol('test church configuration');

function sortedJsonValue(value) {
  if (Array.isArray(value)) return value.map(sortedJsonValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortedJsonValue(value[key])]));
  }
  return value;
}

function canonicalConfiguration(config) {
  return JSON.stringify(sortedJsonValue({
    ...config,
    devotional: { ...config.devotional, fetchUrl: config.devotional.fetchUrl ?? '', fetchFormat: config.devotional.fetchFormat ?? 'json' },
  }));
}

// Runtime bindings may repeat the generated configuration, but must never
// change its timezone, features, services or branding independently of Flutter
// and the rules. Object key order and optional fetch defaults are immaterial.
const generatedConfiguration = canonicalConfiguration(defaultConfig);
let cachedRaw;
let cachedConfig;
export function churchConfig(env) {
  if (env?.[TEST_CHURCH_CONFIG]) return validateChurchConfig(env[TEST_CHURCH_CONFIG]);
  if (env?.CHURCH_CONFIG_JSON === undefined) return defaultConfig;
  const raw = env.CHURCH_CONFIG_JSON;
  if (raw === cachedRaw) return cachedConfig;
  try {
    if (typeof raw !== 'string') throw new Error('CHURCH_CONFIG_JSON must be a JSON string');
    const config = validateChurchConfig(JSON.parse(raw));
    if (canonicalConfiguration(config) !== generatedConfiguration) {
      throw new Error('runtime config differs from generated deployment; prepare and deploy from one configuration source');
    }
    cachedRaw = raw;
    cachedConfig = config;
    return config;
  } catch (error) {
    console.error('invalid church configuration', error.message);
    throw new HttpError(500, '教會設定有誤，請聯絡管理員');
  }
}

export function requireFeature(env, feature) {
  if (churchConfig(env).features[feature] !== true) {
    throw new HttpError(403, '此教會尚未啟用這項功能');
  }
}

export function dateKeyInZone(date, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(date);
  const part = (name) => parts.find((entry) => entry.type === name).value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}
