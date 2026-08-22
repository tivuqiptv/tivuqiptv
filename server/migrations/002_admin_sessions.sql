BEGIN;

CREATE TABLE admin_users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text NOT NULL UNIQUE,
    password_hash text NOT NULL,
    display_name text,
    is_active boolean NOT NULL DEFAULT true,
    last_login_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE admin_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id uuid NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
    token_hash char(64) NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    ip_address inet,
    user_agent text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX admin_sessions_expiry_idx ON admin_sessions (expires_at);

COMMIT;
