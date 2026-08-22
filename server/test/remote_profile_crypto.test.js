import assert from 'node:assert/strict';
import test from 'node:test';

import {
  decryptProfile,
  encryptProfile,
  encryptionKey,
  newPairingCode,
  newPullToken,
  secretHash,
} from '../src/remote_profile_crypto.js';

test('pairing secrets are strong and stored as hashes', () => {
  assert.match(newPairingCode(), /^\d{8}$/);
  assert.ok(newPullToken().length >= 40);
  assert.notEqual(secretHash('12345678', 'a'), secretHash('12345678', 'b'));
});

test('remote profile is encrypted and authenticated', () => {
  const key = encryptionKey('test-encryption-secret');
  const profile = { name: 'Ev', playlistUrl: 'https://example.test/list.m3u' };
  const encrypted = encryptProfile(key, profile);
  assert.equal(encrypted.includes(profile.playlistUrl), false);
  assert.deepEqual(decryptProfile(key, encrypted), profile);
  assert.throws(() => decryptProfile(key, `${encrypted}x`));
});
