import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

/**
 * Sealing: AES-256-GCM for what only the backend may read, e.g. a church's
 * calendar refresh token and its webhook secret. The key is 32 bytes,
 * base64. A sealed value is `<iv>.<tag>.<body>`, each base64.
 */
export function seal(plain: string, keyB64: string) {
  const key = Buffer.from(keyB64, 'base64');
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const body = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), body].map((b) => b.toString('base64')).join('.');
}

/** The plain text of [sealed]; throws when it was not sealed with [keyB64]. */
export function unseal(sealed: string, keyB64: string) {
  const [iv, tag, body] = sealed.split('.').map((p) => Buffer.from(p, 'base64'));
  const decipher = createDecipheriv('aes-256-gcm', Buffer.from(keyB64, 'base64'), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(body), decipher.final()]).toString('utf8');
}
