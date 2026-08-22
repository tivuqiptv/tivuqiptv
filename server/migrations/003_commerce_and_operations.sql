BEGIN;

CREATE TABLE orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_code varchar(20) NOT NULL UNIQUE,
    device_id uuid NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
    provider varchar(32),
    provider_checkout_id text,
    amount_minor integer NOT NULL CHECK (amount_minor > 0),
    currency char(3) NOT NULL,
    status varchar(24) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'cancelled', 'expired', 'refunded', 'chargeback')),
    paid_at timestamptz,
    expires_at timestamptz NOT NULL DEFAULT now() + interval '24 hours',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX orders_provider_checkout_idx
    ON orders (provider, provider_checkout_id)
    WHERE provider IS NOT NULL AND provider_checkout_id IS NOT NULL;
CREATE INDEX orders_device_created_idx ON orders (device_id, created_at DESC);
CREATE INDEX orders_status_created_idx ON orders (status, created_at DESC);

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_provider_event_id_key;
CREATE UNIQUE INDEX payments_provider_event_idx
    ON payments (provider, provider_event_id);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS order_id uuid REFERENCES orders(id) ON DELETE SET NULL;

CREATE INDEX audit_events_created_idx ON audit_events (created_at DESC);
CREATE INDEX audit_events_action_created_idx ON audit_events (action, created_at DESC);

COMMIT;
