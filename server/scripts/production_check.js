import { accessSync, constants, readFileSync } from 'node:fs';

const errors = [];
const warnings = [];

function required(name, minimum = 1) {
  const value = process.env[name]?.trim() ?? '';
  if (value.length < minimum) errors.push(`${name} eksik veya çok kısa.`);
  return value;
}

const domain = process.env.TIVUQ_DOMAIN?.trim() ?? '';
const publicBaseUrl = process.env.PUBLIC_BASE_URL?.trim() ?? '';
required('POSTGRES_PASSWORD', 24);
const databaseUrl = required('DATABASE_URL', 20);
required('ADMIN_API_TOKEN', 32);
required('ADMIN_EMAIL', 5);
required('ADMIN_PASSWORD', 12);
const webhookSecret = process.env.PAYMENT_WEBHOOK_SECRET?.trim() ?? '';
required('REMOTE_PROFILE_ENCRYPTION_SECRET', 32);
required('PRIVACY_CONTROLLER_NAME', 2);
const privacyEmail = required('PRIVACY_CONTACT_EMAIL', 5);
const privacyDate = required('PRIVACY_EFFECTIVE_DATE', 10);
if (webhookSecret && webhookSecret.length < 32) {
  errors.push('PAYMENT_WEBHOOK_SECRET en az 32 karakter olmalı.');
}

if (!domain && !publicBaseUrl) {
  errors.push('TIVUQ_DOMAIN veya barındırma hizmetinin verdiği PUBLIC_BASE_URL gerekli.');
}
if (domain.includes('example.com')) errors.push('TIVUQ_DOMAIN gerçek alan adı olmalı.');
if (publicBaseUrl) {
  try {
    if (new URL(publicBaseUrl).protocol !== 'https:') {
      errors.push('PUBLIC_BASE_URL üretimde HTTPS olmalı.');
    }
  } catch {
    errors.push('PUBLIC_BASE_URL geçerli bir adres olmalı.');
  }
}
if (!webhookSecret) warnings.push('Ödeme sağlayıcısı seçilmedi; otomatik satış kapalı kalacak.');
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(privacyEmail)) {
  errors.push('PRIVACY_CONTACT_EMAIL geçerli bir e-posta olmalı.');
}
if (!/^\d{4}-\d{2}-\d{2}$/.test(privacyDate)) {
  errors.push('PRIVACY_EFFECTIVE_DATE YYYY-MM-DD biçiminde olmalı.');
}
if (/replace-with|example/i.test(process.env.PRIVACY_CONTROLLER_NAME ?? '')) {
  errors.push('PRIVACY_CONTROLLER_NAME gerçek veri sorumlusu adı olmalı.');
}
if (/example\.(com|test)$/i.test(privacyEmail)) {
  errors.push('PRIVACY_CONTACT_EMAIL gerçek ve takip edilen bir adres olmalı.');
}

if (process.env.VERCEL && !databaseUrl.includes(':6543/')) {
  warnings.push('Vercel için Supabase Transaction pooler (6543) DATABASE_URL önerilir.');
}

const signingKeyBase64 = process.env.LICENSE_SIGNING_PRIVATE_KEY_BASE64?.trim();
if (signingKeyBase64) {
  const privateKey = Buffer.from(signingKeyBase64, 'base64').toString('utf8');
  if (!privateKey.includes('PRIVATE KEY')) {
    errors.push('LICENSE_SIGNING_PRIVATE_KEY_BASE64 geçersiz.');
  }
} else {
  const signingKeyFile = process.env.LICENSE_SIGNING_PRIVATE_KEY_FILE?.trim()
    || './secrets/license-private.pem';
  try {
    accessSync(signingKeyFile, constants.R_OK);
    const privateKey = readFileSync(signingKeyFile, 'utf8');
    if (!privateKey.includes('PRIVATE KEY')) errors.push('Lisans özel anahtarı geçersiz.');
  } catch {
    errors.push(`${signingKeyFile} bulunamadı veya okunamıyor.`);
  }
}

for (const warning of warnings) console.warn(`UYARI: ${warning}`);
for (const error of errors) console.error(`HATA: ${error}`);
if (errors.length) process.exit(1);
console.log('TIVUQIPTV üretim yapılandırması temel kontrollerden geçti.');
