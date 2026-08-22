import assert from 'node:assert/strict';
import test from 'node:test';

import {
  hashPassword,
  hashSessionToken,
  newSessionToken,
  verifyPassword,
} from '../src/admin_auth.js';

test('admin passwords are salted and verified with scrypt', async () => {
  const first = await hashPassword('correct horse battery staple');
  const second = await hashPassword('correct horse battery staple');
  assert.notEqual(first, second);
  assert.equal(await verifyPassword('correct horse battery staple', first), true);
  assert.equal(await verifyPassword('wrong password', first), false);
});

test('session tokens are random and stored only as hashes', () => {
  const first = newSessionToken();
  const second = newSessionToken();
  assert.notEqual(first, second);
  assert.match(hashSessionToken(first), /^[0-9a-f]{64}$/);
  assert.notEqual(hashSessionToken(first), first);
});
