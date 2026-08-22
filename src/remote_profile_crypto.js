import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

export function newPairingCode() {
  return String(randomBytes(4).readUInt32BE() % 100_000_000).padStart(8, '0');
}

export function newPullToken() {
  return randomBytes(32).toString('base64url');
}

export function secretHash(value, context = '') {
  return createHash('sha256').update(`${context}:${value}`).digest('hex');
}

export function encryptionKey(value) {
  return createHash('sha256').update(value).digest();
}

export function encryptProfile(key, profile) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([
    cipher.update(JSON.stringify(profile), 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [iv, tag, encrypted].map((part) => part.toString('base64url')).join('.');
}

export function decryptProfile(key, value) {
  const [ivText, tagText, encryptedText] = String(value).split('.');
  if (!ivText || !tagText || !encryptedText) throw new Error('invalid_encrypted_profile');
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(ivText, 'base64url'));
  decipher.setAuthTag(Buffer.from(tagText, 'base64url'));
  return JSON.parse(Buffer.concat([
    decipher.update(Buffer.from(encryptedText, 'base64url')),
    decipher.final(),
  ]).toString('utf8'));
}
