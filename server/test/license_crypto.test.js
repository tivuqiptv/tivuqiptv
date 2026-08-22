import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import test from 'node:test';

import {
  base64UrlEncode,
  deviceCodeForPublicKey,
  issueLicenseToken,
  newChallenge,
  validateDeviceIdentity,
  verifyChallengeSignature,
} from '../src/license_crypto.js';

function keys() {
  return generateKeyPairSync('rsa', { modulusLength: 2048 });
}

test('device code is derived from the public key', () => {
  const { publicKey } = keys();
  const der = publicKey.export({ format: 'der', type: 'spki' });
  const encoded = base64UrlEncode(der);
  const code = deviceCodeForPublicKey(der);
  assert.match(code, /^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$/);
  assert.equal(validateDeviceIdentity(code, encoded), true);
  assert.equal(validateDeviceIdentity('0000-0000-0000', encoded), false);
});

test('challenge requires possession of the private key', () => {
  const { publicKey, privateKey } = keys();
  const nonce = newChallenge();
  const signature = sign('RSA-SHA256', Buffer.from(nonce, 'base64url'), privateKey);
  const encodedKey = base64UrlEncode(
    publicKey.export({ format: 'der', type: 'spki' }),
  );
  assert.equal(
    verifyChallengeSignature(encodedKey, nonce, base64UrlEncode(signature)),
    true,
  );
  assert.equal(
    verifyChallengeSignature(encodedKey, newChallenge(), base64UrlEncode(signature)),
    false,
  );
});

test('license token is signed as a compact RS256 token', () => {
  const { privateKey } = keys();
  const token = issueLicenseToken(
    privateKey.export({ format: 'pem', type: 'pkcs8' }),
    { deviceCode: 'ABCD-EF12-3456', status: 'active', exp: 2_000_000_000 },
  );
  assert.equal(token.split('.').length, 3);
});
