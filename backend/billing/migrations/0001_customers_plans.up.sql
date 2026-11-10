-- Financeiro (ADR-007, ADR-017). Dinheiro sempre em centavos inteiros
-- (BIGINT + moeda); nenhuma coluna monetária é NUMERIC/float. student_id e
-- demais ids de usuário vêm do identity: banco por serviço (ADR-013 §2),
-- logo UUID sem FK entre bancos.

-- Titular retido (ADR-017 §5): cópia de nome e e-mail do aluno, tirada ao
-- criar a assinatura. Na exclusão da conta o registro fica, com
-- account_deleted_at, por obrigação legal de guarda (LGPD art. 7º II e VI).
CREATE TABLE billing_customers (
    tenant_id          UUID NOT NULL,
    student_id         UUID NOT NULL,
    name               TEXT NOT NULL,
    email              TEXT NOT NULL,
    account_deleted_at TIMESTAMPTZ,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, student_id)
);

-- Planos de mensalidade (só do owner, ADR-017 §3).
CREATE TABLE billing_plans (
    id           UUID PRIMARY KEY,
    tenant_id    UUID NOT NULL,
    name         TEXT NOT NULL CHECK (length(btrim(name)) > 0),
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    currency     CHAR(3) NOT NULL DEFAULT 'BRL',
    active       BOOLEAN NOT NULL DEFAULT true,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Alvo das FKs compostas (mesmo tenant) das tabelas filhas.
    UNIQUE (tenant_id, id)
);

CREATE INDEX idx_billing_plans_tenant ON billing_plans (tenant_id, active, name);

ALTER TABLE billing_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_customers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON billing_customers
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE billing_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_plans FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON billing_plans
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
