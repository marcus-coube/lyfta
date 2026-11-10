-- Recebimentos (ADR-007 §2/§5): append-only. A baixa manual do 2.0 é um
-- payment com method=manual; o estorno é um NOVO payment com reversal_of,
-- e o original ganha reversed_by (única mudança permitida numa linha).
CREATE TABLE payments (
    id           UUID PRIMARY KEY,
    tenant_id    UUID NOT NULL,
    invoice_id   UUID NOT NULL,
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    currency     CHAR(3) NOT NULL DEFAULT 'BRL',
    method       TEXT NOT NULL CHECK (method IN ('manual', 'pix', 'card')),
    provider     TEXT,
    provider_ref TEXT,
    paid_at      TIMESTAMPTZ NOT NULL,
    recorded_by  UUID NOT NULL,
    note         TEXT,
    reversed_by  UUID,
    reversal_of  UUID,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (method <> 'manual' OR provider IS NULL),
    CHECK (reversal_of IS NULL OR reversed_by IS NULL),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoices (tenant_id, id),
    FOREIGN KEY (tenant_id, reversed_by) REFERENCES payments (tenant_id, id),
    FOREIGN KEY (tenant_id, reversal_of) REFERENCES payments (tenant_id, id)
);

CREATE INDEX idx_payments_invoice ON payments (tenant_id, invoice_id);
CREATE INDEX idx_payments_paid_at ON payments (tenant_id, paid_at DESC);
-- Idempotência do driver futuro: uma referência de provedor, um pagamento.
CREATE UNIQUE INDEX uq_payments_provider_ref
    ON payments (tenant_id, provider, provider_ref) WHERE provider_ref IS NOT NULL;

CREATE FUNCTION payments_append_only() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND OLD.reversed_by IS NULL AND NEW.reversed_by IS NOT NULL
       AND (to_jsonb(NEW) - 'reversed_by') = (to_jsonb(OLD) - 'reversed_by') THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'payments é append-only (correção = estorno)'
        USING ERRCODE = 'check_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payments_append_only
    BEFORE UPDATE OR DELETE ON payments
    FOR EACH ROW EXECUTE FUNCTION payments_append_only();

-- Webhooks crus de provedores (ADR-007 §4). Vazia no 2.0: PIX é adiado
-- (ADR-017 §2); a tabela existe para o driver futuro não exigir migração.
CREATE TABLE payment_provider_events (
    id           UUID PRIMARY KEY,
    tenant_id    UUID NOT NULL,
    provider     TEXT NOT NULL,
    event_id     TEXT NOT NULL,
    payload      JSONB NOT NULL,
    received_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ,
    UNIQUE (tenant_id, provider, event_id)
);

ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON payments
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE payment_provider_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_provider_events FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON payment_provider_events
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
