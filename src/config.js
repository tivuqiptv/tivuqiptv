import { readFileSync } from 'node:fs';

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function positiveInteger(name, fallback) {
  const value = Number.parseInt(process.env[name] ?? String(fallback), 10);
  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

function signingPrivateKey() {
  const encoded = process.env.LICENSE_SIGNING_PRIVATE_KEY_BASE64?.trim();
  if (encoded) {
    const decoded = Buffer.from(encoded, 'base64').toString('utf8');
    if (!decoded.includes('PRIVATE KEY')) {
      throw new Error('LICENSE_SIGNING_PRIVATE_KEY_BASE64 is invalid');
    }
    return decoded;
  }
  return readFileSync(required('LICENSE_SIGNING_PRIVATE_KEY_FILE'), 'utf8');
}

export function loadConfig() {
  const adminToken = required('ADMIN_API_TOKEN');
  if (adminToken.length < 32) {
    throw new Error('ADMIN_API_TOKEN must contain at least 32 characters');
  }
  const adminEmail = required('ADMIN_EMAIL').toLowerCase();
  const adminPassword = required('ADMIN_PASSWORD');
  if (adminPassword.length < 12) {
    throw new Error('ADMIN_PASSWORD must contain at least 12 characters');
  }

  const production = process.env.NODE_ENV === 'production';
  const publicBaseUrl = process.env.PUBLIC_BASE_URL?.trim() || null;
  if (production && !publicBaseUrl) {
    throw new Error('PUBLIC_BASE_URL is required in production');
  }
  if (publicBaseUrl) {
    const parsedPublicUrl = new URL(publicBaseUrl);
    if (production && parsedPublicUrl.protocol !== 'https:') {
      throw new Error('PUBLIC_BASE_URL must use HTTPS in production');
    }
  }

  const privacyControllerName = process.env.PRIVACY_CONTROLLER_NAME?.trim()
    || (production ? null : 'TIVUQIPTV Development');
  const privacyContactEmail = process.env.PRIVACY_CONTACT_EMAIL?.trim()
    || (production ? null : adminEmail);
  const privacyEffectiveDate = process.env.PRIVACY_EFFECTIVE_DATE?.trim()
    || (production ? null : new Date().toISOString().slice(0, 10));
  if (!privacyControllerName) throw new Error('PRIVACY_CONTROLLER_NAME is required in production');
  if (!privacyContactEmail || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(privacyContactEmail)) {
    throw new Error('PRIVACY_CONTACT_EMAIL must be a valid email address');
  }
  if (!privacyEffectiveDate || !/^\d{4}-\d{2}-\d{2}$/.test(privacyEffectiveDate)) {
    throw new Error('PRIVACY_EFFECTIVE_DATE must use YYYY-MM-DD');
  }

  return Object.freeze({
    port: Number.parseInt(process.env.PORT ?? '8080', 10),
    databaseUrl: required('DATABASE_URL'),
    databasePoolMax: positiveInteger(
      'DATABASE_POOL_MAX',
      process.env.VERCEL ? 1 : 10,
    ),
    adminToken,
    adminEmail,
    adminPassword,
    adminSessionTtlSeconds: Number.parseInt(
      process.env.ADMIN_SESSION_TTL_SECONDS ?? '43200',
      10,
    ),
    production,
    publicBaseUrl,
    trustProxy: process.env.TRUST_PROXY === 'true',
    paymentWebhookSecret: process.env.PAYMENT_WEBHOOK_SECRET?.trim() || null,
    remoteProfileEncryptionSecret:
      process.env.REMOTE_PROFILE_ENCRYPTION_SECRET?.trim() || null,
    privacyControllerName,
    privacyContactEmail,
    privacyEffectiveDate,
    auditRetentionDays: positiveInteger('AUDIT_RETENTION_DAYS', 180),
    pairingMetadataRetentionDays: positiveInteger('PAIRING_METADATA_RETENTION_DAYS', 30),
    paymentRawEventRetentionDays: positiveInteger('PAYMENT_RAW_EVENT_RETENTION_DAYS', 30),
    privacyRequestRetentionDays: positiveInteger('PRIVACY_REQUEST_RETENTION_DAYS', 365),
    deviceTombstoneRetentionDays: positiveInteger('DEVICE_TOMBSTONE_RETENTION_DAYS', 365),
    signingPrivateKey: signingPrivateKey(),
    tokenTtlSeconds: Number.parseInt(
      process.env.LICENSE_TOKEN_TTL_SECONDS ?? '604800',
      10,
    ),
  });
}
