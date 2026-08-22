BEGIN;

ALTER TABLE devices
    ADD COLUMN device_binding_hash char(64);

CREATE UNIQUE INDEX devices_binding_unique_idx
    ON devices (device_binding_hash)
    WHERE device_binding_hash IS NOT NULL;

COMMIT;
