-- 009: Pro Plus (PayPal sandbox). Cap-enforcing data only: no payer name,
-- email, address or payment detail is ever stored (spec FR-022).
CREATE TABLE pro_subscriptions (
  subscription_id TEXT PRIMARY KEY,          -- PayPal "I-..." id
  device_hash     TEXT NOT NULL,             -- devices.device_hash, fixed at checkout (FR-005)
  status          TEXT NOT NULL,             -- research.md R-6 table
  period_end      TEXT,                      -- ISO-8601; NULL until PayPal reports one
  confirmed_at    TEXT NOT NULL              -- last time PayPal was read (or row created)
);
CREATE INDEX pro_subscriptions_device ON pro_subscriptions (device_hash);

-- Operator-key tokens spent by Pro devices, per UTC day. Apart from
-- provider_day so Pro and free never drain each other (FR-018).
CREATE TABLE pro_spend (
  date         TEXT PRIMARY KEY,
  tokens_spent INTEGER NOT NULL DEFAULT 0
);

-- The device's current Pro session and today's count (FR-011).
ALTER TABLE devices ADD COLUMN pro_day_date     TEXT;
ALTER TABLE devices ADD COLUMN pro_day_sessions INTEGER NOT NULL DEFAULT 0;
ALTER TABLE devices ADD COLUMN pro_problem_id   TEXT;

-- FR-027: the UTC date this device last reset a session (replay lever).
ALTER TABLE devices ADD COLUMN replay_reset_date TEXT;
