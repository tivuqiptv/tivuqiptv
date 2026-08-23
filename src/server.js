import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  expiredSessionCookie,
  hashPassword,
  hashSessionToken,
  newSessionToken,
  readCookie,
  sessionCookie,
  verifyPassword,
} from './admin_auth.js';
import { loadConfig } from './config.js';
import { createDatabase } from './db.js';
import {
  issueLicenseToken,
  newChallenge,
  validateDeviceIdentity,
  verifyChallengeSignature,
} from './license_crypto.js';
import {
  decryptProfile,
  encryptProfile,
  encryptionKey,
  newPairingCode,
  newPullToken,
  secretHash,
} from './remote_profile_crypto.js';
import {
  privacyDisclosure,
  renderPrivacyPage,
  resolvePrivacyLanguage,
} from './privacy.js';

const config = loadConfig();
const db = createDatabase(config.databaseUrl, { max: config.databasePoolMax });
const publicDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'public');

function json(response, statusCode, payload, extraHeaders = {}) {
  response.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    ...extraHeaders,
  });
  response.end(JSON.stringify(payload));
}

function applySecurityHeaders(response, requestId) {
  response.setHeader('x-request-id', requestId);
  response.setHeader('x-content-type-options', 'nosniff');
  response.setHeader('referrer-policy', 'no-referrer');
  response.setHeader('permissions-policy', 'camera=(), microphone=(), geolocation=()');
  if (config.production) {
    response.setHeader('strict-transport-security', 'max-age=31536000; includeSubDomains');
  }
}

async function readJson(request) {
  if (request.body !== undefined && request.body !== null) {
    if (typeof request.body === 'object' && !Buffer.isBuffer(request.body)) {
      return request.body;
    }
    try {
      const raw = Buffer.isBuffer(request.body)
        ? request.body.toString('utf8')
        : String(request.body);
      if (Buffer.byteLength(raw) > 64 * 1024) {
        throw Object.assign(new Error('payload_too_large'), { status: 413 });
      }
      return JSON.parse(raw);
    } catch (error) {
      if (error.status) throw error;
      throw Object.assign(new Error('invalid_json'), { status: 400 });
    }
  }
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 64 * 1024) throw Object.assign(new Error('payload_too_large'), { status: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw Object.assign(new Error('invalid_json'), { status: 400 });
  }
}

function text(value, max = 160) {
  return typeof value === 'string' && value.trim() && value.length <= max
    ? value.trim()
    : null;
}

function validPlaylistUrl(value) {
  const urlText = text(value, 4096);
  if (!urlText) return null;
  try {
    const url = new URL(urlText);
    return ['http:', 'https:'].includes(url.protocol) && url.hostname
      ? url.toString()
      : null;
  } catch {
    return null;
  }
}

function remoteProfileKey() {
  const secret = config.remoteProfileEncryptionSecret;
  if (!secret || secret.length < 32) {
    throw Object.assign(new Error('remote_setup_not_configured'), { status: 503 });
  }
  return encryptionKey(secret);
}

async function requireAdmin(request) {
  const supplied = request.headers.authorization?.replace(/^Bearer\s+/i, '') ?? '';
  const expected = Buffer.from(config.adminToken);
  const actual = Buffer.from(supplied);
  if (actual.length === expected.length && timingSafeEqual(actual, expected)) {
    return { id: 'api', email: 'api-token', authType: 'api_token' };
  }

  const token = readCookie(request, 'tivuq_admin_session');
  if (!token) throw Object.assign(new Error('unauthorized'), { status: 401 });
  const session = await db.query(
    `SELECT u.id, u.email, u.display_name
       FROM admin_sessions s
       JOIN admin_users u ON u.id = s.admin_user_id
      WHERE s.token_hash = $1 AND s.expires_at > now() AND u.is_active = true`,
    [hashSessionToken(token)],
  );
  if (!session.rowCount) throw Object.assign(new Error('unauthorized'), { status: 401 });
  await db.query(
    'UPDATE admin_sessions SET last_seen_at = now() WHERE token_hash = $1',
    [hashSessionToken(token)],
  );
  return { ...session.rows[0], authType: 'session' };
}

function requestIp(request) {
  if (config.trustProxy) {
    const forwarded = request.headers['x-forwarded-for'];
    const first = Array.isArray(forwarded) ? forwarded[0] : forwarded?.split(',')[0];
    if (first?.trim()) return first.trim();
  }
  return request.socket?.remoteAddress?.replace(/^::ffff:/, '') ?? null;
}

function rateLimitSubject(value) {
  return createHash('sha256').update(value).digest('hex');
}

async function rateLimitAllowed(bucket, subject, maximum, windowSeconds) {
  const result = await db.query(
    `SELECT attempt_count < $3 AS allowed
       FROM request_rate_limits
      WHERE bucket = $1 AND subject_hash = $2
        AND window_started_at > now() - ($4 * interval '1 second')`,
    [bucket, rateLimitSubject(subject), maximum, windowSeconds],
  );
  return !result.rowCount || result.rows[0].allowed;
}

async function recordRateLimitFailure(bucket, subject, windowSeconds) {
  await db.query(
    `INSERT INTO request_rate_limits
       (bucket, subject_hash, window_started_at, attempt_count)
     VALUES ($1, $2, now(), 1)
     ON CONFLICT (bucket, subject_hash) DO UPDATE SET
       window_started_at = CASE
         WHEN request_rate_limits.window_started_at <= now() - ($3 * interval '1 second')
           THEN now()
         ELSE request_rate_limits.window_started_at
       END,
       attempt_count = CASE
         WHEN request_rate_limits.window_started_at <= now() - ($3 * interval '1 second')
           THEN 1
         ELSE request_rate_limits.attempt_count + 1
       END`,
    [bucket, rateLimitSubject(subject), windowSeconds],
  );
}

async function clearRateLimit(bucket, subject) {
  await db.query(
    'DELETE FROM request_rate_limits WHERE bucket = $1 AND subject_hash = $2',
    [bucket, rateLimitSubject(subject)],
  );
}

function requireTrustedAdminOrigin(request) {
  if (!config.production || !config.publicBaseUrl) return;
  const origin = request.headers.origin;
  if (!origin) throw Object.assign(new Error('origin_required'), { status: 403 });
  if (new URL(origin).origin !== new URL(config.publicBaseUrl).origin) {
    throw Object.assign(new Error('invalid_origin'), { status: 403 });
  }
}

async function createChallenge(request, response) {
  const body = await readJson(request);
  const deviceCode = text(body.deviceCode, 14)?.toUpperCase();
  const publicKey = text(body.publicKey, 4096);
  const deviceBinding = text(body.deviceBinding, 64)?.toLowerCase();
  if (!deviceCode || !publicKey ||
      !/^[0-9A-F]{4}(?:-[0-9A-F]{4}){2}$/.test(deviceCode) ||
      !/^[0-9a-f]{64}$/.test(deviceBinding ?? '')) {
    return json(response, 400, { error: 'invalid_device_identity' });
  }

  try {
    if (!validateDeviceIdentity(deviceCode, publicKey, deviceBinding)) {
      return json(response, 400, { error: 'device_code_public_key_mismatch' });
    }
  } catch {
    return json(response, 400, { error: 'invalid_public_key' });
  }

  const nonce = newChallenge();
  const challengeId = randomUUID();
  const device = await db.transaction(async (client) => {
    const tombstone = await client.query(
      `SELECT 1 FROM device_tombstones
        WHERE device_binding_hash = $1 AND retain_until > now()`,
      [deviceBinding],
    );
    if (tombstone.rowCount) {
      throw Object.assign(new Error('device_data_deleted'), { status: 410 });
    }
    const existing = await client.query(
      `SELECT id, public_key_der, blocked_at, device_binding_hash
         FROM devices WHERE device_code = $1 FOR UPDATE`,
      [deviceCode],
    );
    if (existing.rowCount && existing.rows[0].device_binding_hash &&
        existing.rows[0].device_binding_hash.trim() !== deviceBinding) {
      throw Object.assign(new Error('device_binding_conflict'), { status: 409 });
    }
    if (existing.rowCount && existing.rows[0].public_key_der !== publicKey &&
        !existing.rows[0].device_binding_hash) {
      throw Object.assign(new Error('device_identity_conflict'), { status: 409 });
    }

    const bound = existing.rowCount
      ? { rowCount: 0, rows: [] }
      : await client.query(
          `SELECT id, blocked_at FROM devices
            WHERE device_binding_hash = $1 FOR UPDATE`,
          [deviceBinding],
        );

    // Uygulama yeniden kurulduğunda Android Keystore anahtarı değişebilir.
    // Aynı tek-yönlü cihaz bağı eski satırı ve deneme/lisans hakkını koruyarak
    // yeni anahtara taşır; yeni bir 30 günlük dönem oluşturmaz.
    const result = bound.rowCount
      ? await client.query(
          `UPDATE devices
              SET device_code = $2, public_key_der = $3,
                  last_seen_at = now(), model = COALESCE($4, model),
                  app_version = COALESCE($5, app_version)
            WHERE id = $1 RETURNING id, blocked_at`,
          [
            bound.rows[0].id,
            deviceCode,
            publicKey,
            text(body.model),
            text(body.appVersion, 32),
          ],
        )
      : existing.rowCount
      ? await client.query(
          `UPDATE devices
             SET last_seen_at = now(), model = COALESCE($2, model),
                 app_version = COALESCE($3, app_version),
                 device_binding_hash = COALESCE(device_binding_hash, $4),
                 public_key_der = $5
           WHERE id = $1 RETURNING id, blocked_at`,
          [
            existing.rows[0].id,
            text(body.model),
            text(body.appVersion, 32),
            deviceBinding,
            publicKey,
          ],
        )
      : await client.query(
          `INSERT INTO devices
             (device_code, public_key_der, device_binding_hash, platform, model, app_version)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING id, blocked_at`,
          [
            deviceCode,
            publicKey,
            deviceBinding,
            text(body.platform, 32) ?? 'android_tv',
            text(body.model),
            text(body.appVersion, 32),
          ],
        );

    const row = result.rows[0];
    if (row.blocked_at) throw Object.assign(new Error('device_blocked'), { status: 403 });
    await client.query(
      `INSERT INTO license_challenges (id, device_id, nonce, expires_at)
       VALUES ($1, $2, $3, now() + interval '2 minutes')`,
      [challengeId, row.id, nonce],
    );
    return row;
  });

  await db.query(
    `INSERT INTO audit_events
       (actor_type, actor_id, action, target_type, target_id, ip_address)
     VALUES ('device', $1, 'challenge.created', 'device', $2, $3)`,
    [deviceCode, device.id, requestIp(request)],
  );
  return json(response, 201, { challengeId, nonce, expiresIn: 120 });
}

function sha256(value) {
  return createHash('sha256').update(String(value)).digest('hex');
}

async function consumeVerifiedDeviceChallenge(client, body) {
  const challengeId = text(body.challengeId, 64);
  const deviceCode = text(body.deviceCode, 14)?.toUpperCase();
  const signature = text(body.signature, 4096);
  if (!challengeId || !deviceCode || !signature) {
    throw Object.assign(new Error('missing_verification_fields'), { status: 400 });
  }
  const found = await client.query(
    `SELECT c.id, c.nonce, c.expires_at, c.used_at,
            d.id AS device_id, d.device_code, d.public_key_der, d.blocked_at
       FROM license_challenges c
       JOIN devices d ON d.id = c.device_id
      WHERE c.id = $1 FOR UPDATE OF c`,
    [challengeId],
  );
  if (!found.rowCount) throw Object.assign(new Error('challenge_not_found'), { status: 404 });
  const challenge = found.rows[0];
  if (challenge.device_code !== deviceCode) {
    throw Object.assign(new Error('challenge_device_mismatch'), { status: 403 });
  }
  if (challenge.used_at || new Date(challenge.expires_at) <= new Date()) {
    throw Object.assign(new Error('challenge_expired'), { status: 410 });
  }
  if (challenge.blocked_at) throw Object.assign(new Error('device_blocked'), { status: 403 });
  if (!verifyChallengeSignature(challenge.public_key_der, challenge.nonce, signature)) {
    throw Object.assign(new Error('invalid_device_signature'), { status: 403 });
  }
  await client.query('UPDATE license_challenges SET used_at = now() WHERE id = $1', [challengeId]);
  return challenge;
}

async function requestPrivacyDeletion(request, response) {
  const body = await readJson(request);
  const result = await db.transaction(async (client) => {
    const challenge = await consumeVerifiedDeviceChallenge(client, body);
    const existing = await client.query(
      `SELECT id, status, requested_at FROM privacy_deletion_requests
        WHERE device_id = $1 AND status = 'pending'`,
      [challenge.device_id],
    );
    if (existing.rowCount) return existing.rows[0];
    const inserted = await client.query(
      `INSERT INTO privacy_deletion_requests
         (device_id, device_code_hash, request_ip)
       VALUES ($1, $2, $3)
       RETURNING id, status, requested_at`,
      [challenge.device_id, sha256(challenge.device_code), requestIp(request)],
    );
    await client.query(
      `INSERT INTO audit_events
         (actor_type, actor_id, action, target_type, target_id, ip_address)
       VALUES ('device', $1, 'privacy.deletion_requested', 'privacy_request', $2, $3)`,
      [challenge.device_code, inserted.rows[0].id, requestIp(request)],
    );
    return inserted.rows[0];
  });
  return json(response, 202, { request: result });
}

async function listPrivacyDeletionRequests(request, response) {
  await requireAdmin(request);
  const result = await db.query(
    `SELECT r.id, r.status, r.requested_at, r.completed_at, r.notes,
            d.device_code, d.model,
            l.id AS license_id, l.status AS license_status,
            c.email AS customer_email
       FROM privacy_deletion_requests r
       LEFT JOIN devices d ON d.id = r.device_id
       LEFT JOIN licenses l ON l.device_id = d.id
       LEFT JOIN customers c ON c.id = l.customer_id
      ORDER BY (r.status = 'pending') DESC, r.requested_at DESC
      LIMIT 500`,
  );
  return json(response, 200, { requests: result.rows });
}

async function completePrivacyDeletionRequest(request, response, requestId) {
  const admin = await requireAdmin(request);
  if (admin.authType === 'session') requireTrustedAdminOrigin(request);
  const body = await readJson(request);
  const result = await db.transaction(async (client) => {
    const found = await client.query(
      `SELECT r.id, r.device_id, r.status, d.device_code, d.device_binding_hash,
              l.customer_id
         FROM privacy_deletion_requests r
         LEFT JOIN devices d ON d.id = r.device_id
         LEFT JOIN licenses l ON l.device_id = d.id
        WHERE r.id = $1 FOR UPDATE OF r`,
      [requestId],
    );
    if (!found.rowCount) throw Object.assign(new Error('privacy_request_not_found'), { status: 404 });
    const row = found.rows[0];
    if (row.status !== 'pending') {
      throw Object.assign(new Error('privacy_request_already_processed'), { status: 409 });
    }
    if (!row.device_id) throw Object.assign(new Error('privacy_device_missing'), { status: 409 });

    if (row.device_binding_hash) {
      await client.query(
        `INSERT INTO device_tombstones
           (device_binding_hash, reason, retain_until)
         VALUES ($1, 'verified_deletion', now() + ($2 * interval '1 day'))
         ON CONFLICT (device_binding_hash) DO UPDATE SET
           retain_until = GREATEST(device_tombstones.retain_until, EXCLUDED.retain_until)`,
        [row.device_binding_hash, config.deviceTombstoneRetentionDays],
      );
    }
    await client.query('DELETE FROM license_challenges WHERE device_id = $1', [row.device_id]);
    await client.query('DELETE FROM remote_profile_pairings WHERE device_id = $1', [row.device_id]);
    await client.query('UPDATE payments SET device_id = NULL, raw_event = $2::jsonb WHERE device_id = $1', [row.device_id, '{}']);
    await client.query(
      `UPDATE licenses SET status = 'revoked', revoked_at = now(),
              revoke_reason = 'privacy_deletion', updated_at = now()
        WHERE device_id = $1 AND status = 'active'`,
      [row.device_id],
    );
    await client.query(
      `UPDATE audit_events SET actor_id = NULL, ip_address = NULL,
              metadata = metadata - 'deviceCode' - 'userAgent'
        WHERE actor_id = $1 OR (target_type = 'device' AND target_id = $2)`,
      [row.device_code, row.device_id],
    );
    if (row.customer_id) {
      const otherLinks = await client.query(
        `SELECT 1 FROM licenses WHERE customer_id = $1 AND device_id <> $2
         UNION ALL SELECT 1 FROM orders WHERE customer_id = $1 AND device_id <> $2
         UNION ALL SELECT 1 FROM payments WHERE customer_id = $1 AND device_id IS DISTINCT FROM $2
         LIMIT 1`,
        [row.customer_id, row.device_id],
      );
      if (!otherLinks.rowCount) {
        await client.query(
          `UPDATE customers SET email = NULL, display_name = NULL, updated_at = now()
            WHERE id = $1`,
          [row.customer_id],
        );
      }
    }
    const anonymousCode = `DEL-${randomUUID().replaceAll('-', '').slice(0, 10).toUpperCase()}`;
    await client.query(
      `UPDATE devices SET
          device_code = $2, public_key_der = 'deleted', device_binding_hash = NULL,
          model = NULL, app_version = NULL, last_verified_at = NULL,
          blocked_at = now(), block_reason = 'privacy_deletion', privacy_deleted_at = now()
        WHERE id = $1`,
      [row.device_id, anonymousCode],
    );
    await client.query(
      `UPDATE privacy_deletion_requests SET device_id = NULL, status = 'completed',
              completed_at = now(), completed_by = $2, request_ip = NULL, notes = $3
        WHERE id = $1`,
      [requestId, admin.id === 'api' ? null : admin.id, text(body.notes, 1000)],
    );
    await client.query(
      `INSERT INTO audit_events
         (actor_type, actor_id, action, target_type, target_id, metadata)
       VALUES ('admin', $1, 'privacy.deletion_completed', 'privacy_request', $2, $3::jsonb)`,
      [admin.id, requestId, JSON.stringify({ admin: admin.email })],
    );
    return { id: requestId, status: 'completed' };
  });
  return json(response, 200, { request: result });
}

async function createRemoteProfilePairing(request, response) {
  remoteProfileKey();
  const body = await readJson(request);
  const deviceCode = text(body.deviceCode, 14)?.toUpperCase();
  const publicKey = text(body.publicKey, 4096);
  const deviceBinding = text(body.deviceBinding, 64)?.toLowerCase();
  let validIdentity = false;
  try {
    validIdentity = Boolean(
      deviceCode && publicKey && deviceBinding &&
      validateDeviceIdentity(deviceCode, publicKey, deviceBinding),
    );
  } catch {
    validIdentity = false;
  }
  if (!validIdentity) {
    return json(response, 400, { error: 'invalid_device_identity' });
  }

  const pairingCode = newPairingCode();
  const pullToken = newPullToken();
  const pairingId = randomUUID();
  await db.transaction(async (client) => {
    const device = await client.query(
      `UPDATE devices SET last_seen_at = now(),
              model = COALESCE($3, model), app_version = COALESCE($4, app_version)
        WHERE device_code = $1 AND public_key_der = $2
          AND device_binding_hash = $5
          AND privacy_deleted_at IS NULL
        RETURNING id, public_key_der, blocked_at`,
      [deviceCode, publicKey, text(body.model), text(body.appVersion, 32), deviceBinding],
    );
    if (!device.rowCount) {
      throw Object.assign(new Error('device_not_registered'), { status: 403 });
    }
    if (device.rows[0].blocked_at) {
      throw Object.assign(new Error('device_blocked'), { status: 403 });
    }
    await client.query(
      `UPDATE remote_profile_pairings
          SET status = 'expired'
        WHERE device_id = $1 AND status IN ('waiting', 'ready')`,
      [device.rows[0].id],
    );
    await client.query(
      `INSERT INTO remote_profile_pairings
         (id, device_id, pairing_code_hash, pull_token_hash, expires_at)
       VALUES ($1, $2, $3, $4, now() + interval '10 minutes')`,
      [
        pairingId,
        device.rows[0].id,
        secretHash(pairingCode, pairingId),
        secretHash(pullToken, 'pull'),
      ],
    );
  });
  return json(response, 201, {
    pairingId,
    pairingCode,
    pullToken,
    expiresIn: 600,
    setupUrl: config.publicBaseUrl ? `${config.publicBaseUrl}/setup` : null,
  });
}

async function submitRemoteProfile(request, response) {
  const ip = requestIp(request) ?? 'unknown';
  if (!await rateLimitAllowed('remote_setup', ip, 12, 10 * 60)) {
    return json(response, 429, { error: 'too_many_attempts' });
  }
  const body = await readJson(request);
  const deviceCode = text(body.deviceCode, 14)?.toUpperCase();
  const pairingCode = text(body.pairingCode, 8);
  const playlistUrl = validPlaylistUrl(body.playlistUrl);
  const profileName = text(body.profileName, 80) ?? 'Uzaktan Eklenen';
  if (!deviceCode || !/^\d{8}$/.test(pairingCode ?? '') || !playlistUrl) {
    return json(response, 400, { error: 'invalid_setup_fields' });
  }

  const result = await db.transaction(async (client) => {
    const found = await client.query(
      `SELECT p.id, p.pairing_code_hash, p.failed_attempts
         FROM remote_profile_pairings p
         JOIN devices d ON d.id = p.device_id
        WHERE d.device_code = $1 AND p.status = 'waiting' AND p.expires_at > now()
        ORDER BY p.created_at DESC LIMIT 1
        FOR UPDATE OF p`,
      [deviceCode],
    );
    if (!found.rowCount) return null;
    const pairing = found.rows[0];
    if (pairing.failed_attempts >= 8 ||
        secretHash(pairingCode, pairing.id) !== pairing.pairing_code_hash) {
      await client.query(
        `UPDATE remote_profile_pairings SET failed_attempts = failed_attempts + 1
          WHERE id = $1`,
        [pairing.id],
      );
      return null;
    }
    await client.query(
      `UPDATE remote_profile_pairings
          SET encrypted_profile = $2, status = 'ready', submitted_at = now()
        WHERE id = $1`,
      [pairing.id, encryptProfile(remoteProfileKey(), { name: profileName, playlistUrl })],
    );
    return pairing.id;
  });
  if (!result) {
    await recordRateLimitFailure('remote_setup', ip, 10 * 60);
    return json(response, 404, { error: 'pairing_not_found_or_code_invalid' });
  }
  await clearRateLimit('remote_setup', ip);
  await db.query(
    `INSERT INTO audit_events
       (actor_type, actor_id, action, target_type, target_id, ip_address)
     VALUES ('customer', $1, 'remote_profile.submitted', 'pairing', $2, $3)`,
    [deviceCode, result, requestIp(request)],
  );
  return json(response, 202, { ok: true });
}

async function pullRemoteProfile(request, response, pairingId) {
  const supplied = request.headers.authorization?.replace(/^Bearer\s+/i, '') ?? '';
  if (!supplied) return json(response, 401, { error: 'pull_token_required' });
  const result = await db.transaction(async (client) => {
    const found = await client.query(
      `SELECT id, pull_token_hash, encrypted_profile, status, expires_at
         FROM remote_profile_pairings WHERE id = $1 FOR UPDATE`,
      [pairingId],
    );
    if (!found.rowCount ||
        secretHash(supplied, 'pull') !== found.rows[0].pull_token_hash) {
      throw Object.assign(new Error('unauthorized'), { status: 401 });
    }
    const pairing = found.rows[0];
    if (new Date(pairing.expires_at) <= new Date()) return { status: 'expired' };
    if (pairing.status !== 'ready') return { status: pairing.status };
    const profile = decryptProfile(remoteProfileKey(), pairing.encrypted_profile);
    await client.query(
      `UPDATE remote_profile_pairings
          SET status = 'consumed', consumed_at = now(), encrypted_profile = NULL
        WHERE id = $1`,
      [pairingId],
    );
    return { status: 'ready', profile };
  });
  return json(response, 200, result);
}

async function verifyLicense(request, response) {
  const body = await readJson(request);
  const challengeId = text(body.challengeId, 64);
  const deviceCode = text(body.deviceCode, 14)?.toUpperCase();
  const signature = text(body.signature, 4096);
  if (!challengeId || !deviceCode || !signature) {
    return json(response, 400, { error: 'missing_verification_fields' });
  }

  const result = await db.transaction(async (client) => {
    const found = await client.query(
      `SELECT c.id, c.nonce, c.expires_at, c.used_at,
              d.id AS device_id, d.device_code, d.public_key_der, d.blocked_at
         FROM license_challenges c
         JOIN devices d ON d.id = c.device_id
        WHERE c.id = $1
        FOR UPDATE OF c`,
      [challengeId],
    );
    if (!found.rowCount) throw Object.assign(new Error('challenge_not_found'), { status: 404 });
    const challenge = found.rows[0];
    if (challenge.device_code !== deviceCode) {
      throw Object.assign(new Error('challenge_device_mismatch'), { status: 403 });
    }
    if (challenge.used_at || new Date(challenge.expires_at) <= new Date()) {
      throw Object.assign(new Error('challenge_expired'), { status: 410 });
    }
    if (challenge.blocked_at) throw Object.assign(new Error('device_blocked'), { status: 403 });
    if (!verifyChallengeSignature(challenge.public_key_der, challenge.nonce, signature)) {
      throw Object.assign(new Error('invalid_device_signature'), { status: 403 });
    }
    await client.query('UPDATE license_challenges SET used_at = now() WHERE id = $1', [challengeId]);

    const license = await client.query(
      `SELECT id, kind, status, activated_at
         FROM licenses
        WHERE device_id = $1`,
      [challenge.device_id],
    );
    if (license.rowCount && license.rows[0].status === 'active') {
      await client.query(
        'UPDATE devices SET last_seen_at = now(), last_verified_at = now() WHERE id = $1',
        [challenge.device_id],
      );
      return {
        active: true,
        deviceId: challenge.device_id,
        entitlement: license.rows[0],
        tokenStatus: 'active',
      };
    }

    // İptal/iade edilmiş lisans denemeye geri dönemez. Yalnızca daha önce hiç
    // lisans açılmamış cihazlar kalan sunucu denemesini kullanabilir.
    if (license.rowCount) return { active: false, deviceId: challenge.device_id };

    const trial = await client.query(
      `SELECT trial_started_at, trial_expires_at
         FROM devices
        WHERE id = $1 AND trial_expires_at > now()`,
      [challenge.device_id],
    );
    if (!trial.rowCount) return { active: false, deviceId: challenge.device_id };
    await client.query(
      'UPDATE devices SET last_seen_at = now(), last_verified_at = now() WHERE id = $1',
      [challenge.device_id],
    );
    return {
      active: true,
      deviceId: challenge.device_id,
      entitlement: {
        id: `trial:${challenge.device_id}`,
        kind: 'trial',
        activated_at: trial.rows[0].trial_started_at,
      },
      tokenStatus: 'trial',
      trialExpiresAt: trial.rows[0].trial_expires_at,
    };
  });

  if (!result.active) {
    return json(response, 200, { active: false, status: 'unlicensed' });
  }

  const now = Math.floor(Date.now() / 1000);
  const trialExpiry = result.trialExpiresAt
    ? Math.floor(new Date(result.trialExpiresAt).getTime() / 1000)
    : null;
  const tokenExpiry = trialExpiry == null
    ? now + config.tokenTtlSeconds
    : Math.min(trialExpiry, now + config.tokenTtlSeconds);
  const token = issueLicenseToken(config.signingPrivateKey, {
    v: 1,
    sub: result.entitlement.id,
    deviceCode,
    kind: result.entitlement.kind,
    status: result.tokenStatus,
    iat: now,
    exp: tokenExpiry,
    ...(trialExpiry == null ? {} : { trialExp: trialExpiry }),
  });
  await db.query(
    `INSERT INTO audit_events
       (actor_type, actor_id, action, target_type, target_id, ip_address)
     VALUES ('device', $1, 'license.verified', 'license', $2, $3)`,
    [deviceCode, result.entitlement.id, requestIp(request)],
  );
  return json(response, 200, {
    active: true,
    status: result.tokenStatus,
    kind: result.entitlement.kind,
    licenseToken: token,
    offlineUntil: new Date(tokenExpiry * 1000).toISOString(),
    trialExpiresAt: result.trialExpiresAt ?? null,
  });
}

async function activateLicense(request, response) {
  const admin = await requireAdmin(request);
  if (admin.authType === 'session') requireTrustedAdminOrigin(request);
  const body = await readJson(request);
  const deviceCode = text(body.deviceCode, 14)?.toUpperCase();
  if (!deviceCode) return json(response, 400, { error: 'device_code_required' });

  const result = await db.transaction(async (client) => {
    const device = await client.query('SELECT id FROM devices WHERE device_code = $1', [deviceCode]);
    if (!device.rowCount) throw Object.assign(new Error('device_not_found'), { status: 404 });

    let customerId = null;
    const email = text(body.customerEmail, 320)?.toLowerCase();
    if (email) {
      const customer = await client.query(
        `INSERT INTO customers (email, display_name)
         VALUES ($1, $2)
         ON CONFLICT (email) DO UPDATE SET
           display_name = COALESCE(EXCLUDED.display_name, customers.display_name),
           updated_at = now()
         RETURNING id`,
        [email, text(body.customerName)],
      );
      customerId = customer.rows[0].id;
    }

    return client.query(
      `INSERT INTO licenses
         (device_id, customer_id, status, source, external_reference)
       VALUES ($1, $2, 'active', $3, $4)
       ON CONFLICT (device_id) DO UPDATE SET
         customer_id = COALESCE(EXCLUDED.customer_id, licenses.customer_id),
         status = 'active', source = EXCLUDED.source,
         external_reference = COALESCE(EXCLUDED.external_reference, licenses.external_reference),
         activated_at = now(), revoked_at = NULL, revoke_reason = NULL,
         updated_at = now()
       RETURNING id, status, kind, activated_at`,
      [
        device.rows[0].id,
        customerId,
        text(body.source, 32) ?? 'manual',
        text(body.externalReference, 200),
      ],
    );
  });

  const license = result.rows[0];
  await db.query(
    `INSERT INTO audit_events
       (actor_type, actor_id, action, target_type, target_id, ip_address, metadata)
     VALUES ('admin', $1, 'license.activated', 'license', $2, $3, $4::jsonb)`,
    [admin.id, license.id, requestIp(request), JSON.stringify({ deviceCode, admin: admin.email })],
  );
  return json(response, 200, { license });
}

async function revokeLicense(request, response, licenseId) {
  const admin = await requireAdmin(request);
  if (admin.authType === 'session') requireTrustedAdminOrigin(request);
  const body = await readJson(request);
  const status = ['revoked', 'refunded', 'chargeback'].includes(body.status)
    ? body.status
    : 'revoked';
  const result = await db.query(
    `UPDATE licenses SET status = $2, revoked_at = now(), revoke_reason = $3, updated_at = now()
      WHERE id = $1 RETURNING id, status, revoked_at`,
    [licenseId, status, text(body.reason, 500)],
  );
  if (!result.rowCount) return json(response, 404, { error: 'license_not_found' });
  await db.query(
    `INSERT INTO audit_events
       (actor_type, actor_id, action, target_type, target_id, ip_address, metadata)
     VALUES ('admin', $1, 'license.revoked', 'license', $2, $3, $4::jsonb)`,
    [admin.id, licenseId, requestIp(request), JSON.stringify({ status, admin: admin.email })],
  );
  return json(response, 200, { license: result.rows[0] });
}

async function listDevices(request, response) {
  await requireAdmin(request);
  const result = await db.query(
    `SELECT d.device_code, d.platform, d.model, d.app_version,
            d.first_seen_at, d.last_seen_at, d.last_verified_at, d.blocked_at,
            d.trial_started_at, d.trial_expires_at,
            l.id AS license_id, l.status AS license_status, l.kind AS license_kind,
            l.activated_at, c.email AS customer_email
       FROM devices d
       LEFT JOIN licenses l ON l.device_id = d.id
       LEFT JOIN customers c ON c.id = l.customer_id
      WHERE d.privacy_deleted_at IS NULL
      ORDER BY d.last_seen_at DESC
      LIMIT 500`,
  );
  return json(response, 200, { devices: result.rows });
}

async function dashboard(request, response) {
  await requireAdmin(request);
  const result = await db.query(
    `SELECT
       (SELECT count(*)::int FROM devices WHERE privacy_deleted_at IS NULL) AS total_devices,
       (SELECT count(*)::int FROM licenses WHERE status = 'active') AS active_licenses,
       (SELECT count(*)::int FROM licenses WHERE status IN ('revoked', 'refunded', 'chargeback')) AS inactive_licenses,
       (SELECT count(*)::int FROM devices
         WHERE privacy_deleted_at IS NULL
           AND last_seen_at > now() - interval '24 hours') AS devices_last_24h`,
  );
  return json(response, 200, { summary: result.rows[0] });
}

async function listAuditEvents(request, response) {
  await requireAdmin(request);
  const result = await db.query(
    `SELECT id, actor_type, actor_id, action, target_type, target_id,
            ip_address, metadata, created_at
       FROM audit_events
      ORDER BY created_at DESC
      LIMIT 250`,
  );
  return json(response, 200, { events: result.rows });
}

async function listPayments(request, response) {
  await requireAdmin(request);
  const result = await db.query(
    `SELECT p.id, p.provider, p.provider_payment_id, p.amount_minor, p.currency,
            p.status, p.created_at, p.updated_at, p.order_id,
            c.email AS customer_email, d.device_code
       FROM payments p
       LEFT JOIN customers c ON c.id = p.customer_id
       LEFT JOIN devices d ON d.id = p.device_id
      ORDER BY p.created_at DESC
      LIMIT 250`,
  );
  return json(response, 200, { payments: result.rows });
}

async function createAdminSession(request, response) {
  requireTrustedAdminOrigin(request);
  const ip = requestIp(request) ?? 'unknown';
  if (!await rateLimitAllowed('admin_login', ip, 5, 15 * 60)) {
    return json(response, 429, { error: 'too_many_login_attempts' });
  }
  const body = await readJson(request);
  const email = text(body.email, 320)?.toLowerCase();
  const password = typeof body.password === 'string' ? body.password : '';
  const found = email
    ? await db.query(
        'SELECT id, email, display_name, password_hash FROM admin_users WHERE email = $1 AND is_active = true',
        [email],
      )
    : { rowCount: 0, rows: [] };
  const valid = found.rowCount
    ? await verifyPassword(password, found.rows[0].password_hash)
    : false;
  if (!valid) {
    await recordRateLimitFailure('admin_login', ip, 15 * 60);
    await db.query(
      `INSERT INTO audit_events
         (actor_type, actor_id, action, ip_address, metadata)
       VALUES ('admin', $1, 'admin.login_failed', $2, $3::jsonb)`,
      [email ?? 'unknown', requestIp(request), JSON.stringify({ userAgent: text(request.headers['user-agent'], 500) })],
    );
    return json(response, 401, { error: 'invalid_credentials' });
  }

  await clearRateLimit('admin_login', ip);
  const user = found.rows[0];
  const token = newSessionToken();
  await db.transaction(async (client) => {
    await client.query(
      `INSERT INTO admin_sessions
         (admin_user_id, token_hash, expires_at, ip_address, user_agent)
       VALUES ($1, $2, now() + ($3 * interval '1 second'), $4, $5)`,
      [
        user.id,
        hashSessionToken(token),
        config.adminSessionTtlSeconds,
        requestIp(request),
        text(request.headers['user-agent'], 500),
      ],
    );
    await client.query('UPDATE admin_users SET last_login_at = now() WHERE id = $1', [user.id]);
    await client.query(
      `INSERT INTO audit_events
         (actor_type, actor_id, action, target_type, target_id, ip_address)
       VALUES ('admin', $1, 'admin.login_succeeded', 'admin_user', $1, $2)`,
      [user.id, requestIp(request)],
    );
  });
  return json(
    response,
    200,
    { user: { email: user.email, displayName: user.display_name } },
    {
      'set-cookie': sessionCookie(
        token,
        config.adminSessionTtlSeconds,
        config.production,
      ),
    },
  );
}

async function currentAdminSession(request, response) {
  const admin = await requireAdmin(request);
  return json(response, 200, {
    user: { email: admin.email, displayName: admin.display_name },
  });
}

async function deleteAdminSession(request, response) {
  requireTrustedAdminOrigin(request);
  const token = readCookie(request, 'tivuq_admin_session');
  if (token) {
    await db.transaction(async (client) => {
      const session = await client.query(
        `DELETE FROM admin_sessions
          WHERE token_hash = $1
          RETURNING admin_user_id`,
        [hashSessionToken(token)],
      );
      if (session.rowCount) {
        await client.query(
          `INSERT INTO audit_events
             (actor_type, actor_id, action, target_type, target_id, ip_address)
           VALUES ('admin', $1, 'admin.logout', 'admin_user', $1, $2)`,
          [session.rows[0].admin_user_id, requestIp(request)],
        );
      }
    });
  }
  return json(response, 200, { ok: true }, {
    'set-cookie': expiredSessionCookie(config.production),
  });
}

async function serveAdminAsset(response, pathname) {
  const assets = {
    '/admin': ['index.html', 'text/html; charset=utf-8'],
    '/admin/': ['index.html', 'text/html; charset=utf-8'],
    '/admin/app.js': ['app.js', 'text/javascript; charset=utf-8'],
    '/admin/styles.css': ['styles.css', 'text/css; charset=utf-8'],
    '/setup': ['setup.html', 'text/html; charset=utf-8'],
    '/setup/': ['setup.html', 'text/html; charset=utf-8'],
    '/setup/app.js': ['setup.js', 'text/javascript; charset=utf-8'],
    '/setup/styles.css': ['setup.css', 'text/css; charset=utf-8'],
  };
  const asset = assets[pathname];
  if (!asset) return false;
  const folder = pathname.startsWith('/setup') ? 'setup' : 'admin';
  const content = await readFile(resolve(publicDirectory, folder, asset[0]));
  response.writeHead(200, {
    'content-type': asset[1],
    'cache-control': asset[0].endsWith('.html') ? 'no-store' : 'public, max-age=300',
    'content-security-policy': "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
  });
  response.end(content);
  return true;
}

function servePrivacyPage(request, response, url) {
  const language = resolvePrivacyLanguage(
    url.searchParams.get('lang'),
    request.headers['accept-language'],
  );
  const content = renderPrivacyPage({
    language,
    controllerName: config.privacyControllerName,
    contactEmail: config.privacyContactEmail,
    effectiveDate: config.privacyEffectiveDate,
    retention: {
      auditDays: config.auditRetentionDays,
      pairingMetadataDays: config.pairingMetadataRetentionDays,
      paymentRawEventDays: config.paymentRawEventRetentionDays,
      deletionRequestDays: config.privacyRequestRetentionDays,
      tombstoneDays: config.deviceTombstoneRetentionDays,
    },
  });
  response.writeHead(200, {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'public, max-age=300',
    'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
    'x-frame-options': 'DENY',
  });
  response.end(content);
}

async function ensureBootstrapAdmin() {
  const existing = await db.query('SELECT id FROM admin_users WHERE email = $1', [config.adminEmail]);
  if (existing.rowCount) return;
  const inserted = await db.query(
    `INSERT INTO admin_users (email, password_hash, display_name)
     VALUES ($1, $2, 'TIVUQIPTV Yöneticisi')
     ON CONFLICT (email) DO NOTHING
     RETURNING id`,
    [config.adminEmail, await hashPassword(config.adminPassword)],
  );
  if (inserted.rowCount) console.log(`Bootstrap admin created: ${config.adminEmail}`);
}

let initializationPromise;

export function initializeServer() {
  initializationPromise ??= ensureBootstrapAdmin().catch((error) => {
    initializationPromise = null;
    throw error;
  });
  return initializationPromise;
}

export async function requestHandler(request, response) {
  const requestId = randomUUID();
  applySecurityHeaders(response, requestId);
  try {
    await initializeServer();
    const url = new URL(request.url ?? '/', 'http://localhost');
    if (request.method === 'GET' && ['/privacy', '/privacy/'].includes(url.pathname)) {
      return servePrivacyPage(request, response, url);
    }
    if (request.method === 'GET' && url.pathname === '/privacy/data-disclosure.json') {
      return json(response, 200, privacyDisclosure(config));
    }
    if (request.method === 'GET' && await serveAdminAsset(response, url.pathname)) {
      return;
    }
    if (request.method === 'GET' && url.pathname === '/health') {
      await db.query('SELECT 1');
      return json(response, 200, { ok: true });
    }
    if (request.method === 'POST' && url.pathname === '/v1/device/challenges') {
      return await createChallenge(request, response);
    }
    if (request.method === 'POST' && url.pathname === '/v1/device/profile-pairings') {
      return await createRemoteProfilePairing(request, response);
    }
    if (request.method === 'POST' && url.pathname === '/v1/setup/profile') {
      return await submitRemoteProfile(request, response);
    }
    const profilePull = url.pathname.match(/^\/v1\/device\/profile-pairings\/([0-9a-f-]+)$/i);
    if (request.method === 'GET' && profilePull) {
      return await pullRemoteProfile(request, response, profilePull[1]);
    }
    if (request.method === 'POST' && url.pathname === '/v1/license/verify') {
      return await verifyLicense(request, response);
    }
    if (request.method === 'POST' && url.pathname === '/v1/privacy/deletion-requests') {
      return await requestPrivacyDeletion(request, response);
    }
    if (request.method === 'POST' && url.pathname === '/v1/admin/licenses/activate') {
      return await activateLicense(request, response);
    }
    const revoke = url.pathname.match(/^\/v1\/admin\/licenses\/([0-9a-f-]+)\/revoke$/i);
    if (request.method === 'POST' && revoke) {
      return await revokeLicense(request, response, revoke[1]);
    }
    if (request.method === 'GET' && url.pathname === '/v1/admin/devices') {
      return await listDevices(request, response);
    }
    if (request.method === 'GET' && url.pathname === '/v1/admin/dashboard') {
      return await dashboard(request, response);
    }
    if (request.method === 'GET' && url.pathname === '/v1/admin/audit-events') {
      return await listAuditEvents(request, response);
    }
    if (request.method === 'GET' && url.pathname === '/v1/admin/payments') {
      return await listPayments(request, response);
    }
    if (request.method === 'GET' && url.pathname === '/v1/admin/privacy/deletion-requests') {
      return await listPrivacyDeletionRequests(request, response);
    }
    const privacyCompletion = url.pathname.match(
      /^\/v1\/admin\/privacy\/deletion-requests\/([0-9a-f-]+)\/complete$/i,
    );
    if (request.method === 'POST' && privacyCompletion) {
      return await completePrivacyDeletionRequest(request, response, privacyCompletion[1]);
    }
    if (request.method === 'POST' && url.pathname === '/v1/admin/session') {
      return await createAdminSession(request, response);
    }
    if (request.method === 'GET' && url.pathname === '/v1/admin/session') {
      return await currentAdminSession(request, response);
    }
    if (request.method === 'DELETE' && url.pathname === '/v1/admin/session') {
      return await deleteAdminSession(request, response);
    }
    return json(response, 404, { error: 'not_found' });
  } catch (error) {
    if (!error.status || error.status >= 500) console.error(`[${requestId}]`, error);
    return json(response, error.status ?? 500, {
      error: error.status ? error.message : 'internal_error',
    });
  }
}

export async function closeServerResources() {
  await db.close();
}
