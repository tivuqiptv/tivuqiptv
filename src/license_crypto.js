import {
  createPrivateKey,
  createPublicKey,
  randomBytes,
  sign,
  verify,
} from 'node:crypto';

export function base64UrlEncode(value) {
  return Buffer.from(value).toString('base64url');
}

export function base64UrlDecode(value) {
  return Buffer.from(value, 'base64url');
}

export function deviceCodeForBinding(deviceBinding) {
  const digest = String(deviceBinding).trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(digest)) throw new Error('invalid_device_binding');
  return `${digest.slice(0, 4)}-${digest.slice(4, 8)}-${digest.slice(8, 12)}`
    .toUpperCase();
}

export function validateDeviceIdentity(deviceCode, publicKeyText, deviceBinding) {
  const publicKeyDer = base64UrlDecode(publicKeyText);
  createPublicKey({ key: publicKeyDer, format: 'der', type: 'spki' });
  return deviceCodeForBinding(deviceBinding) === deviceCode.toUpperCase();
}

export function newChallenge() {
  return base64UrlEncode(randomBytes(32));
}

export function verifyChallengeSignature(publicKeyText, nonce, signatureText) {
  const publicKey = createPublicKey({
    key: base64UrlDecode(publicKeyText),
    format: 'der',
    type: 'spki',
  });
  return verify(
    'RSA-SHA256',
    base64UrlDecode(nonce),
    publicKey,
    base64UrlDecode(signatureText),
  );
}

export function issueLicenseToken(privateKeyPem, claims) {
  const header = base64UrlEncode(
    JSON.stringify({ alg: 'RS256', typ: 'PTL', v: 1 }),
  );
  const payload = base64UrlEncode(JSON.stringify(claims));
  const signingInput = `${header}.${payload}`;
  const signature = sign(
    'RSA-SHA256',
    Buffer.from(signingInput),
    createPrivateKey(privateKeyPem),
  );
  return `${signingInput}.${base64UrlEncode(signature)}`;
}
