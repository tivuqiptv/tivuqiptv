BEGIN;

CREATE TABLE request_rate_limits (
    bucket varchar(40) NOT NULL,
    subject_hash char(64) NOT NULL,
    window_started_at timestamptz NOT NULL DEFAULT now(),
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    PRIMARY KEY (bucket, subject_hash)
);

CREATE INDEX request_rate_limits_expiry_idx
    ON request_rate_limits (window_started_at);

CREATE TABLE backend_retention_policy (
    id smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    audit_days integer NOT NULL CHECK (audit_days > 0),
    pairing_metadata_days integer NOT NULL CHECK (pairing_metadata_days > 0),
    payment_raw_event_days integer NOT NULL CHECK (payment_raw_event_days > 0),
    privacy_request_days integer NOT NULL CHECK (privacy_request_days > 0),
    device_tombstone_days integer NOT NULL CHECK (device_tombstone_days > 0),
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO backend_retention_policy
    (id, audit_days, pairing_metadata_days, payment_raw_event_days,
     privacy_request_days, device_tombstone_days)
VALUES (1, 180, 30, 30, 365, 365)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION perform_backend_maintenance()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    policy backend_retention_policy%ROWTYPE;
BEGIN
    SELECT * INTO STRICT policy FROM backend_retention_policy WHERE id = 1;

    DELETE FROM admin_sessions WHERE expires_at <= now();
    DELETE FROM license_challenges WHERE created_at < now() - interval '24 hours';
    UPDATE remote_profile_pairings
       SET status = 'expired', encrypted_profile = NULL
     WHERE expires_at <= now() AND status IN ('waiting', 'ready');
    DELETE FROM remote_profile_pairings
     WHERE created_at < now() - (policy.pairing_metadata_days * interval '1 day');
    DELETE FROM audit_events
     WHERE created_at < now() - (policy.audit_days * interval '1 day');
    UPDATE payments
       SET raw_event = '{}'::jsonb
     WHERE raw_event <> '{}'::jsonb
       AND created_at < now() - (policy.payment_raw_event_days * interval '1 day');
    DELETE FROM device_tombstones WHERE retain_until <= now();
    DELETE FROM privacy_deletion_requests
     WHERE status <> 'pending'
       AND completed_at < now() - (policy.privacy_request_days * interval '1 day');
    DELETE FROM request_rate_limits
     WHERE window_started_at < now() - interval '24 hours';
END;
$$;

REVOKE ALL ON FUNCTION perform_backend_maintenance() FROM PUBLIC;

COMMIT;
