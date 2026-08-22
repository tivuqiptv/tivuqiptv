-- Supabase Dashboard > SQL Editor içinde bir kez çalıştırın.
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule(jobid)
  FROM cron.job
 WHERE jobname = 'tivuq-hourly-maintenance';

SELECT cron.schedule(
  'tivuq-hourly-maintenance',
  '5 * * * *',
  'SELECT public.perform_backend_maintenance()'
);
