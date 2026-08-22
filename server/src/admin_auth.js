import {
  createHash,
  randomBytes,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);

export async function hashPassword(password) {
  const salt = randomBytes(16);
  const derived = await scrypt(password, salt, 64);
  return `scrypt$${salt.toString('base64url')}$${derived.toString('base64url')}`;
}

export async function verifyPassword(password, encoded) {
  const [algorithm, saltText, hashText] = encoded.split('$');
  if (algorithm !== 'scrypt' || !saltText || !hashText) return false;
  const expected = Buffer.from(hashText, 'base64url');
  const actual = await scrypt(password, Buffer.from(saltText, 'base64url'), expected.length);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function newSessionToken() {
  return randomBytes(32).toString('base64url');
}

export function hashSessionToken(token) {
  return createHash('sha256').update(token).digest('hex');
}

export function readCookie(request, name) {
  const cookies = request.headers.cookie?.split(';') ?? [];
  for (const cookie of cookies) {
    const separator = cookie.indexOf('=');
    if (separator < 0) continue;
    if (cookie.slice(0, separator).trim() === name) {
      return decodeURIComponent(cookie.slice(separator + 1).trim());
    }
  }
  return null;
}

export function sessionCookie(token, maxAge, secure) {
  return [
    `tivuq_admin_session=${encodeURIComponent(token)}`,
    'Path=/',
    'HttpOnly',
    'SameSite=Strict',
    secure ? 'Secure' : null,
    `Max-Age=${maxAge}`,
  ].filter(Boolean).join('; ');
}

export function expiredSessionCookie(secure) {
  return [
    'tivuq_admin_session=',
    'Path=/',
    'HttpOnly',
    'SameSite=Strict',
    secure ? 'Secure' : null,
    'Max-Age=0',
  ].filter(Boolean).join('; ');
}
