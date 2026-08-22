import { generateKeyPairSync } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const outputDirectory = resolve('secrets');
mkdirSync(outputDirectory, { recursive: true });

const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 3072,
  publicKeyEncoding: { type: 'spki', format: 'der' },
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
});

writeFileSync(resolve(outputDirectory, 'license-private.pem'), privateKey, {
  mode: 0o600,
  flag: 'wx',
});
writeFileSync(resolve(outputDirectory, 'license-public.der'), publicKey, {
  mode: 0o644,
  flag: 'wx',
});

console.log('Signing keys created in server/secrets/.');
console.log('Keep license-private.pem only on the production server.');
console.log(`LICENSE_SERVER_PUBLIC_KEY=${publicKey.toString('base64url')}`);
