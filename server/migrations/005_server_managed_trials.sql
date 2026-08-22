BEGIN;

ALTER TABLE devices
    ADD COLUMN trial_started_at timestamptz,
    ADD COLUMN trial_expires_at timestamptz;

UPDATE devices
   SET trial_started_at = COALESCE(trial_started_at, now()),
       trial_expires_at = COALESCE(trial_expires_at, now() + interval '30 days');

ALTER TABLE devices
    ALTER COLUMN trial_started_at SET DEFAULT now(),
    ALTER COLUMN trial_started_at SET NOT NULL,
    ALTER COLUMN trial_expires_at SET DEFAULT now() + interval '30 days',
    ALTER COLUMN trial_expires_at SET NOT NULL;

CREATE INDEX devices_trial_expiry_idx ON devices (trial_expires_at);

COMMIT;
