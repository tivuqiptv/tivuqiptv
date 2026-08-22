import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import pg from 'pg';

const connectionString = process.env.MIGRATION_DATABASE_URL?.trim()
  || process.env.DATABASE_URL?.trim();
if (!connectionString) throw new Error('MIGRATION_DATABASE_URL or DATABASE_URL is required');

const { Client } = pg;
const client = new Client({ connectionString });
await client.connect();
try {
  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);
  const directory = resolve('migrations');
  for (const name of readdirSync(directory).filter((value) => value.endsWith('.sql')).sort()) {
    const exists = await client.query('SELECT 1 FROM schema_migrations WHERE name = $1', [name]);
    if (exists.rowCount) continue;
    const sql = readFileSync(resolve(directory, name), 'utf8');
    await client.query(sql);
    await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [name]);
    console.log(`Applied ${name}`);
  }
  const retentionTable = await client.query(
    "SELECT to_regclass('public.backend_retention_policy') AS name",
  );
  if (retentionTable.rows[0]?.name) {
    const days = (name, fallback) => {
      const value = Number.parseInt(process.env[name] ?? String(fallback), 10);
      if (!Number.isInteger(value) || value < 1) throw new Error(`${name} must be positive`);
      return value;
    };
    await client.query(
      `UPDATE backend_retention_policy SET
         audit_days = $1, pairing_metadata_days = $2,
         payment_raw_event_days = $3, privacy_request_days = $4,
         device_tombstone_days = $5, updated_at = now()
       WHERE id = 1`,
      [
        days('AUDIT_RETENTION_DAYS', 180),
        days('PAIRING_METADATA_RETENTION_DAYS', 30),
        days('PAYMENT_RAW_EVENT_RETENTION_DAYS', 30),
        days('PRIVACY_REQUEST_RETENTION_DAYS', 365),
        days('DEVICE_TOMBSTONE_RETENTION_DAYS', 365),
      ],
    );
  }
} finally {
  await client.end();
}
