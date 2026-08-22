import { createHmac, timingSafeEqual } from 'node:crypto';

export function signWebhook(secret, timestamp, rawBody) {
  return createHmac('sha256', secret)
    .update(`${timestamp}.${rawBody}`)
    .digest('hex');
}

export function verifyWebhookSignature({ secret, timestamp, rawBody, signature, now = Date.now() }) {
  if (!secret || !timestamp || !signature) return false;
  const timestampNumber = Number.parseInt(timestamp, 10);
  if (!Number.isSafeInteger(timestampNumber)) return false;
  if (Math.abs(Math.floor(now / 1000) - timestampNumber) > 300) return false;
  const expected = Buffer.from(signWebhook(secret, timestamp, rawBody), 'hex');
  const supplied = Buffer.from(signature, 'hex');
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}

export function normalizePaymentEvent(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const eventId = clean(value.eventId, 200);
  const paymentId = clean(value.paymentId, 200);
  const orderCode = clean(value.orderCode, 20)?.toUpperCase();
  const status = clean(value.status, 24)?.toLowerCase();
  const amountMinor = Number.isSafeInteger(value.amountMinor) ? value.amountMinor : null;
  const currency = clean(value.currency, 3)?.toUpperCase();
  if (!eventId || !paymentId || !orderCode || amountMinor === null || amountMinor <= 0) return null;
  if (!/^[A-Z0-9-]{8,20}$/.test(orderCode)) return null;
  if (!['paid', 'refunded', 'chargeback'].includes(status)) return null;
  if (!/^[A-Z]{3}$/.test(currency ?? '')) return null;
  return { eventId, paymentId, orderCode, status, amountMinor, currency };
}

function clean(value, max) {
  return typeof value === 'string' && value.trim() && value.length <= max
    ? value.trim()
    : null;
}
