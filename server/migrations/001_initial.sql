BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_code varchar(14) NOT NULL UNIQUE,
    public_key_der text NOT NULL,
    key_algorithm varchar(32) NOT NULL DEFAULT 'RSA-SHA256',
    platform varchar(32) NOT NULL DEFAULT 'android_tv',
    model varchar(160),
    app_version varchar(32),
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    last_verified_at timestamptz,
    blocked_at timestamptz,
    block_reason text
);

CREATE TABLE customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text UNIQUE,
    display_name text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE licenses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id uuid NOT NULL UNIQUE REFERENCES devices(id) ON DELETE RESTRICT,
    customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
    kind varchar(24) NOT NULL DEFAULT 'lifetime' CHECK (kind IN ('lifetime')),
    status varchar(24) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'revoked', 'refunded', 'chargeback')),
    source varchar(32) NOT NULL DEFAULT 'manual',
    external_reference text UNIQUE,
    activated_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    revoke_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider varchar(32) NOT NULL,
    provider_event_id text NOT NULL UNIQUE,
    provider_payment_id text,
    customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
    device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
    amount_minor integer CHECK (amount_minor >= 0),
    currency char(3),
    status varchar(24) NOT NULL,
    raw_event jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE license_challenges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    nonce text NOT NULL,
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX license_challenges_expiry_idx
    ON license_challenges (expires_at) WHERE used_at IS NULL;

CREATE TABLE audit_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_type varchar(24) NOT NULL,
    actor_id text,
    action varchar(80) NOT NULL,
    target_type varchar(40),
    target_id text,
    ip_address inet,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMIT;
