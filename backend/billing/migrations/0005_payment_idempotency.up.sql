-- Idempotência da baixa manual (P7.2, doc 008): o cliente manda
-- `Idempotency-Key` e repetir a chamada devolve o mesmo pagamento em vez de
-- 409. O índice é por tenant: a mesma chave em tenants diferentes não colide.
ALTER TABLE payments ADD COLUMN idempotency_key TEXT
    CHECK (idempotency_key IS NULL OR length(idempotency_key) BETWEEN 1 AND 200);

CREATE UNIQUE INDEX uq_payments_idempotency_key
    ON payments (tenant_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
