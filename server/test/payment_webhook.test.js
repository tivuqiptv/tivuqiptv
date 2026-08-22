import assert from 'node:assert/strict';
import test from 'node:test';

import {
  normalizePaymentEvent,
  signWebhook,
  verifyWebhookSignature,
} from '../src/payment_webhook.js';

test('payment webhook signature is valid for five minutes and covers the body', () => {
  const secret = 'a-secure-test-secret';
  const timestamp = '1775995200';
  const rawBody = '{"eventId":"evt_1"}';
  const signature = signWebhook(secret, timestamp, rawBody);
  assert.equal(verifyWebhookSignature({
    secret, timestamp, rawBody, signature, now: 1775995200_000,
  }), true);
  assert.equal(verifyWebhookSignature({
    secret, timestamp, rawBody: `${rawBody} `, signature, now: 1775995200_000,
  }), false);
  assert.equal(verifyWebhookSignature({
    secret, timestamp, rawBody, signature, now: 1775995601_000,
  }), false);
});

test('payment events are strictly normalized', () => {
  assert.deepEqual(normalizePaymentEvent({
    eventId: 'evt_1', paymentId: 'pay_1', orderCode: 'ptv-abcd1234',
    status: 'paid', amountMinor: 14900, currency: 'try',
  }), {
    eventId: 'evt_1', paymentId: 'pay_1', orderCode: 'PTV-ABCD1234',
    status: 'paid', amountMinor: 14900, currency: 'TRY',
  });
  assert.equal(normalizePaymentEvent({ eventId: 'evt_1', status: 'paid' }), null);
});
