BEGIN;

CREATE TABLE remote_profile_pairings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    pairing_code_hash char(64) NOT NULL,
    pull_token_hash char(64) NOT NULL UNIQUE,
    encrypted_profile text,
    status varchar(20) NOT NULL DEFAULT 'waiting'
        CHECK (status IN ('waiting', 'ready', 'consumed', 'expired')),
    failed_attempts integer NOT NULL DEFAULT 0,
    expires_at timestamptz NOT NULL,
    submitted_at timestamptz,
    consumed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX remote_profile_pairings_device_idx
    ON remote_profile_pairings (device_id, created_at DESC);
CREATE INDEX remote_profile_pairings_expiry_idx
    ON remote_profile_pairings (expires_at) WHERE status IN ('waiting', 'ready');

COMMIT;
