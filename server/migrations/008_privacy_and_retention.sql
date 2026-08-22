BEGIN;

ALTER TABLE devices
    ADD COLUMN privacy_deleted_at timestamptz;

CREATE TABLE device_tombstones (
    device_binding_hash char(64) PRIMARY KEY,
    reason varchar(40) NOT NULL,
    retain_until timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX device_tombstones_retention_idx
    ON device_tombstones (retain_until);

CREATE TABLE privacy_deletion_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
    device_code_hash char(64) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'completed', 'rejected')),
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    completed_by uuid REFERENCES admin_users(id) ON DELETE SET NULL,
    request_ip inet,
    notes text
);

CREATE UNIQUE INDEX privacy_deletion_requests_pending_device_idx
    ON privacy_deletion_requests (device_id)
    WHERE status = 'pending';
CREATE INDEX privacy_deletion_requests_status_created_idx
    ON privacy_deletion_requests (status, requested_at DESC);

COMMIT;
