-- TV ve tarayıcı Supabase Data API'ye doğrudan bağlanmaz.
-- Yalnız Vercel'deki gizli DATABASE_URL (postgres rolü) veritabanını kullanır.
REVOKE ALL ON TABLE
  schema_migrations,
  devices,
  customers,
  licenses,
  payments,
  license_challenges,
  audit_events,
  orders,
  admin_users,
  admin_sessions,
  remote_profile_pairings,
  device_tombstones,
  privacy_deletion_requests,
  request_rate_limits,
  backend_retention_policy
FROM anon, authenticated;

REVOKE ALL ON SEQUENCE audit_events_id_seq FROM anon, authenticated;
REVOKE ALL ON FUNCTION perform_backend_maintenance() FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON FUNCTIONS FROM anon, authenticated;

DO $$
DECLARE
  table_name text;
BEGIN
  FOR table_name IN
    SELECT unnest(ARRAY[
      'schema_migrations', 'devices', 'customers', 'licenses', 'payments',
      'license_challenges', 'audit_events', 'orders', 'admin_users',
      'admin_sessions', 'remote_profile_pairings', 'device_tombstones',
      'privacy_deletion_requests', 'request_rate_limits',
      'backend_retention_policy'
    ])
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
  END LOOP;
END
$$;
