DROP INDEX IF EXISTS uq_payments_idempotency_key;
ALTER TABLE payments DROP COLUMN IF EXISTS idempotency_key;
