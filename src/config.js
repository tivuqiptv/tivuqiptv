import { readFileSync } from 'node:fs';

const EMBEDDED_KEY = `-----BEGIN PRIVATE KEY-----
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
io7SEIBWGdXqDKMFMXDqLWs=
-----END PRIVATE KEY-----`;

function required(name, fallback = null) {
  const value = process.env[name]?.trim();
  if (!value) {
    if (fallback !== null) return fallback;
    throw new Error(`${name} is required`);
  }
  return value;
}

function positiveInteger(name, fallback) {
  const value = Number.parseInt(process.env[name] ?? String(fallback), 10);
  if (!Number.isInteger(value) || value < 1) {
    return fallback;
  }
  return value;
}

function signingPrivateKey() {
  const encoded = process.env.LICENSE_SIGNING_PRIVATE_KEY_BASE64?.trim();
  if (encoded) {
    try {
      const decoded = Buffer.from(encoded, 'base64').toString('utf8');
      if (decoded.includes('PRIVATE KEY')) {
        return decoded;
      }
    } catch (_) {}
  }
  try {
    const file = process.env.LICENSE_SIGNING_PRIVATE_KEY_FILE || './secrets/license-private.pem';
    return readFileSync(file, 'utf8');
  } catch (_) {
    return EMBEDDED_KEY;
  }
}

export function loadConfig() {
  const adminToken = required('ADMIN_API_TOKEN', 'f9013f6f2705b3c491fdc23d8111a10d6a0c905347df0e9c18afdfdffb9ac539');
  const adminEmail = required('ADMIN_EMAIL', 'tivuqiptv@gmail.com').toLowerCase();
  const adminPassword = required('ADMIN_PASSWORD', 'Deneme123...');

  const production = process.env.NODE_ENV === 'production';
  const publicBaseUrl = process.env.PUBLIC_BASE_URL?.trim() || 'https://tivuqiptv.vercel.app';

  const privacyControllerName = process.env.PRIVACY_CONTROLLER_NAME?.trim() || 'TIVUQIPTV';
  const privacyContactEmail = process.env.PRIVACY_CONTACT_EMAIL?.trim() || adminEmail;
  const privacyEffectiveDate = process.env.PRIVACY_EFFECTIVE_DATE?.trim() || new Date().toISOString().slice(0, 10);

  return Object.freeze({
    port: Number.parseInt(process.env.PORT ?? '8080', 10),
    databaseUrl: required('DATABASE_URL'),
    databasePoolMax: positiveInteger('DATABASE_POOL_MAX', 1),
    adminToken,
    adminEmail,
    adminPassword,
    adminSessionTtlSeconds: positiveInteger('ADMIN_SESSION_TTL_SECONDS', 43200),
    production,
    publicBaseUrl,
    trustProxy: process.env.TRUST_PROXY === 'true' || true,
    paymentWebhookSecret: process.env.PAYMENT_WEBHOOK_SECRET?.trim() || null,
    remoteProfileEncryptionSecret:
      process.env.REMOTE_PROFILE_ENCRYPTION_SECRET?.trim() || '801712367598122ee5184e4a250d5a93454ecab7f87b718ba4f377707bdb5dc6',
    privacyControllerName,
    privacyContactEmail,
    privacyEffectiveDate,
    auditRetentionDays: positiveInteger('AUDIT_RETENTION_DAYS', 180),
    pairingMetadataRetentionDays: positiveInteger('PAIRING_METADATA_RETENTION_DAYS', 30),
    paymentRawEventRetentionDays: positiveInteger('PAYMENT_RAW_EVENT_RETENTION_DAYS', 30),
    privacyRequestRetentionDays: positiveInteger('PRIVACY_REQUEST_RETENTION_DAYS', 365),
    deviceTombstoneRetentionDays: positiveInteger('DEVICE_TOMBSTONE_RETENTION_DAYS', 365),
    signingPrivateKey: signingPrivateKey(),
    tokenTtlSeconds: positiveInteger('LICENSE_TOKEN_TTL_SECONDS', 604800),
  });
}
