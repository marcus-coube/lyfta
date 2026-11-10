-- Assinatura: vínculo aluno↔plano com o valor congelado na adesão (mudar o
-- preço do plano não reajusta quem já assinou).
CREATE TABLE subscriptions (
    id              UUID PRIMARY KEY,
    tenant_id       UUID NOT NULL,
    student_id      UUID NOT NULL,
    billing_plan_id UUID NOT NULL,
    amount_cents    BIGINT NOT NULL CHECK (amount_cents > 0),
    currency        CHAR(3) NOT NULL DEFAULT 'BRL',
    due_day         SMALLINT NOT NULL CHECK (due_day BETWEEN 1 AND 28),
    starts_on       DATE NOT NULL,
    status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'paused', 'canceled')),
    canceled_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((status = 'canceled') = (canceled_at IS NOT NULL)),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, billing_plan_id) REFERENCES billing_plans (tenant_id, id),
    FOREIGN KEY (tenant_id, student_id) REFERENCES billing_customers (tenant_id, student_id)
);

-- Uma assinatura vigente por aluno. Pausada conta como vigente: retomar não
-- pode colidir com uma assinatura nova criada durante a pausa.
CREATE UNIQUE INDEX uq_subscriptions_one_live_per_student
    ON subscriptions (tenant_id, student_id) WHERE status IN ('active', 'paused');
CREATE INDEX idx_subscriptions_plan ON subscriptions (tenant_id, billing_plan_id);

-- Fatura gerada por job mensal; período = mês de competência (YYYY-MM).
CREATE TABLE invoices (
    id              UUID PRIMARY KEY,
    tenant_id       UUID NOT NULL,
    subscription_id UUID NOT NULL,
    student_id      UUID NOT NULL,
    period          CHAR(7) NOT NULL CHECK (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
    due_date        DATE NOT NULL,
    amount_cents    BIGINT NOT NULL CHECK (amount_cents > 0),
    currency        CHAR(3) NOT NULL DEFAULT 'BRL',
    status          TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open', 'paid', 'overdue', 'canceled')),
    paid_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((status = 'paid') = (paid_at IS NOT NULL)),
    UNIQUE (tenant_id, id),
    -- Idempotência do job mensal: um mês, uma fatura por assinatura.
    UNIQUE (tenant_id, subscription_id, period),
    FOREIGN KEY (tenant_id, subscription_id) REFERENCES subscriptions (tenant_id, id)
);

CREATE INDEX idx_invoices_student ON invoices (tenant_id, student_id, due_date DESC);
-- Varredura diária open → overdue e listagem por status.
CREATE INDEX idx_invoices_status_due ON invoices (tenant_id, status, due_date);

-- Fatura paga é imutável (ADR-007 §2). Única saída: estorno, que a devolve a
-- open|overdue limpando paid_at; nenhum outro campo muda e ela nunca some.
CREATE FUNCTION invoices_guard_paid() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'paid' THEN
            RAISE EXCEPTION 'fatura paga é imutável' USING ERRCODE = 'check_violation';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.status = 'paid' THEN
        IF NEW.status NOT IN ('open', 'overdue') OR NEW.paid_at IS NOT NULL
           OR (NEW.id, NEW.tenant_id, NEW.subscription_id, NEW.student_id, NEW.period,
               NEW.due_date, NEW.amount_cents, NEW.currency, NEW.created_at)
              IS DISTINCT FROM
              (OLD.id, OLD.tenant_id, OLD.subscription_id, OLD.student_id, OLD.period,
               OLD.due_date, OLD.amount_cents, OLD.currency, OLD.created_at) THEN
            RAISE EXCEPTION 'fatura paga é imutável (só estorno a reabre)'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_invoices_guard_paid
    BEFORE UPDATE OR DELETE ON invoices
    FOR EACH ROW EXECUTE FUNCTION invoices_guard_paid();

ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON subscriptions
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON invoices
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
