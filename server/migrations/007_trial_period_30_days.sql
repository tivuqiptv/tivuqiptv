BEGIN;

ALTER TABLE devices
    ALTER COLUMN trial_expires_at SET DEFAULT now() + interval '30 days';

UPDATE devices
   SET trial_expires_at = LEAST(
       trial_expires_at,
       trial_started_at + interval '30 days'
   );

COMMIT;
